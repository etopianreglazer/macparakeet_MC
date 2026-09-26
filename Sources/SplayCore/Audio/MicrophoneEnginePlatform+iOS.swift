import AVFoundation
import CoreAudio
import Foundation
import os

#if os(iOS)
// The iPhone keeps Splay's own engine platform (AVAudioSession route-change and
// interruption observers feed the input hint → MicrophoneInputPolicy → restart).
// The macOS class in MicrophoneEnginePlatform.swift follows upstream MacParakeet;
// upstream has no iOS model, so this copy is deliberately separate. See
// docs/plans/upstream-mic-port.md.
/// Production adapter that drives a real `AVAudioEngine`. Mirrors the
/// engine-lifecycle invariants from `MicrophoneCapture` (PR #186):
///
/// - VPIO ducking is suppressed so other apps' audio isn't ~50% attenuated.
/// - The engine is destroyed and recreated on stop so coreaudiod releases
///   the VPAU aggregate device. A long-lived engine keeps the VPAU alive
///   indefinitely, which inherits the duplex layout into other engines.
/// - When configured with a `deviceAttemptsBuilder`, each `configureAndStart`
///   walks the resolved attempt list (selected → explicit systemDefault when
///   System Default is selected → implicit systemDefault → builtIn) and
///   recreates the engine on every failed attempt before trying the next.
public final class AVAudioEngineMicrophonePlatform: MicrophoneEnginePlatform, @unchecked Sendable {
    public typealias DeviceAttemptsBuilder = @Sendable () -> [MeetingInputDeviceAttempt]
    public typealias InputDeviceSetter = @Sendable (AudioDeviceID, AVAudioEngine) -> Bool
    typealias EngineStarter = @Sendable (
        AVAudioEngine,
        Bool,
        AVAudioFrameCount,
        @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) throws -> Void

    private let logger = Logger(
        subsystem: "com.macparakeet.core",
        category: "AVAudioEngineMicrophonePlatform"
    )
    private let queue = DispatchQueue(label: "com.macparakeet.shared-mic-platform")
    private let defaultInputListenerQueue = DispatchQueue(
        label: "com.macparakeet.shared-mic-platform.default-input-listener"
    )
    private let deviceAttemptsBuilder: DeviceAttemptsBuilder?
    private let inputDeviceSetter: InputDeviceSetter
    private let engineStarter: EngineStarter?
    private var audioEngine = AVAudioEngine()
    private var running: Bool = false
    private var lastSucceededAttemptLocked: MeetingInputDeviceAttempt?
    /// Token for the `AVAudioEngine.configurationChangeNotification` observer
    /// installed on the current `audioEngine` instance. Cleared on
    /// `tearDown` / `resetEngine` / `replaceEngineAfterFailure` so the
    /// next instance gets its own observer. Core Audio posts this when the
    /// input chain reconfigures (device change, format or sample-rate
    /// change); the engine has then stopped. The observer logs it, tears
    /// the stopped engine down, and fires the input hint so the stream's
    /// policy rebuilds.
    private var configurationChangeObserver: NSObjectProtocol?
    /// AVAudioSession route-change + interruption observers (iOS has no HAL
    /// default-input listener). Installed once for the platform's
    /// lifetime, not per engine: they describe the *session*, and a recording
    /// whose engine is between rebuild attempts (or stopped by an interruption)
    /// still needs to hear that it may come back.
    private var audioSessionObservers: [NSObjectProtocol] = []
    /// The session policy (`RecordingAudioSessionLifecycle` documents the model).
    /// Queue-held like `running`.
    private var audioSession = RecordingAudioSessionLifecycle()
    /// The input-hint handler (`setDefaultInputChangeHandler`): fired by the
    /// configuration-change observer and the route-change / interruption
    /// observers. The owner runs `MicrophoneInputPolicy` on it. Held under its
    /// own lock — the observers (`queue: nil`) fire on whichever thread posts
    /// the notification, not the engine `queue`.
    private let defaultInputChangeHandlerLock = NSLock()
    private var _defaultInputChangeHandler: (@Sendable () -> Void)?

    public init(
        deviceAttemptsBuilder: DeviceAttemptsBuilder? = nil,
        inputDeviceSetter: InputDeviceSetter? = nil
    ) {
        self.deviceAttemptsBuilder = deviceAttemptsBuilder
        self.inputDeviceSetter = inputDeviceSetter ?? avAudioEngineDefaultInputDeviceSetter
        self.engineStarter = nil
        installAudioSessionObservers()
    }

    init(
        deviceAttemptsBuilder: DeviceAttemptsBuilder? = nil,
        inputDeviceSetter: InputDeviceSetter? = nil,
        engineStarter: @escaping EngineStarter
    ) {
        self.deviceAttemptsBuilder = deviceAttemptsBuilder
        self.inputDeviceSetter = inputDeviceSetter ?? avAudioEngineDefaultInputDeviceSetter
        self.engineStarter = engineStarter
        installAudioSessionObservers()
    }

    deinit {
        // Nothing else references the platform any more, so the queue-held
        // helpers are safe to call directly.
        audioSessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    public var isEngineRunning: Bool {
        // Must not be called from the platform's own queue — `queue.sync`
        // would deadlock. Caller is expected to be on a different queue
        // (typically `SharedMicrophoneStream.engineQueue` or a UI thread).
        dispatchPrecondition(condition: .notOnQueue(queue))
        return queue.sync { running }
    }

    public var inputFormat: AVAudioFormat? {
        dispatchPrecondition(condition: .notOnQueue(queue))
        return queue.sync {
            guard running else { return nil }
            do {
                let format = try catchingObjCException {
                    audioEngine.inputNode.outputFormat(forBus: 0)
                }
                return format.sampleRate > 0 && format.channelCount > 0 ? format : nil
            } catch {
                let errorType = AudioCaptureDiagnostics.errorType(error)
                logger.error(
                    "shared_mic_engine_input_format_failed error_type=\(errorType, privacy: .public) error_detail=\(error.localizedDescription, privacy: .private)"
                )
                AudioCaptureDiagnostics.append(
                    "shared_mic_engine_input_format_failed \(AudioCaptureDiagnostics.errorFields(error))"
                )
                return nil
            }
        }
    }

    /// The device attempt that produced the most recent successful start, or
    /// `nil` if no `deviceAttemptsBuilder` was configured (the engine used
    /// whatever device the system chose) or the platform is not running.
    public var lastSucceededAttempt: MeetingInputDeviceAttempt? {
        dispatchPrecondition(condition: .notOnQueue(queue))
        return queue.sync { running ? lastSucceededAttemptLocked : nil }
    }

    public func configureAndStart(
        vpioEnabled: Bool,
        bufferSize: AVAudioFrameCount,
        tapHandler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) throws {
        try queue.sync {
            // VPIO toggle requires a stop → setVoiceProcessingEnabled → start
            // sequence; the engine cannot be reconfigured while running.
            if running {
                tearDownLocked()
            }

            let attempts = deviceAttemptsBuilder?() ?? []
            if attempts.isEmpty {
                // No device chain — use whatever the engine's input node picks.
                try startConfiguredEngineLocked(
                    vpioEnabled: vpioEnabled,
                    bufferSize: bufferSize,
                    tapHandler: tapHandler
                )
                lastSucceededAttemptLocked = nil
                return
            }

            var lastError: Error?
            for attempt in attempts {
                let transport = AudioCaptureDiagnostics.deviceTransportLabel(attempt.deviceID)
                let deviceLabel = AudioCaptureDiagnostics.deviceLabel(attempt.deviceID)
                if let deviceID = attempt.explicitDeviceID {
                    guard inputDeviceSetter(deviceID, audioEngine) else {
                        logger.warning(
                            "shared_mic_engine_input_device_set_failed source=\(attempt.source.logValue, privacy: .public) transport=\(transport, privacy: .public)"
                        )
                        AudioCaptureDiagnostics.append(
                            "shared_mic_engine_input_device_set_failed source=\(attempt.source.logValue) device=\(deviceLabel) transport=\(transport)"
                        )
                        if lastError == nil {
                            lastError = AVAudioEngineMicrophonePlatformError.deviceSetFailed(attempt)
                        }
                        resetEngineLocked()
                        continue
                    }
                }

                do {
                    try startConfiguredEngineLocked(
                        vpioEnabled: vpioEnabled,
                        bufferSize: bufferSize,
                        tapHandler: tapHandler
                    )
                    lastSucceededAttemptLocked = attempt
                    logger.info(
                        "shared_mic_engine_input_device_started source=\(attempt.source.logValue, privacy: .public) transport=\(transport, privacy: .public) vpio=\(vpioEnabled, privacy: .public)"
                    )
                    AudioCaptureDiagnostics.append(
                        "shared_mic_engine_input_device_started source=\(attempt.source.logValue) routing=\(attempt.usesImplicitSystemDefault ? "implicit" : "explicit") device=\(deviceLabel) transport=\(transport) vpio=\(vpioEnabled)"
                    )
                    return
                } catch {
                    lastError = error
                    let errorType = AudioCaptureDiagnostics.errorType(error)
                    logger.warning(
                        "shared_mic_engine_input_device_start_failed source=\(attempt.source.logValue, privacy: .public) transport=\(transport, privacy: .public) error_type=\(errorType, privacy: .public) error_detail=\(error.localizedDescription, privacy: .private)"
                    )
                    AudioCaptureDiagnostics.append(
                        "shared_mic_engine_input_device_start_failed source=\(attempt.source.logValue) device=\(deviceLabel) transport=\(transport) \(AudioCaptureDiagnostics.errorFields(error))"
                    )
                    // startConfiguredEngineLocked already replaces the engine on
                    // failure, so nothing more to reset here.
                }
            }

            throw lastError ?? AVAudioEngineMicrophonePlatformError.noDeviceAvailable
        }
    }

    public func stopEngine() {
        queue.sync {
            if running {
                tearDownLocked()
                logger.info("shared_mic_engine_stopped")
                AudioCaptureDiagnostics.append("shared_mic_engine_stopped")
            }
            // The session follows the *recording*, not the engine: a recording
            // whose engine died (failed rebuild, interruption) still holds the
            // session — mic indicator lit, background window open — until the
            // user stops. Only here, never in `tearDownLocked`: a follow-the-input
            // rebuild tears down and restarts while the recording continues and
            // must keep the session active.
            if audioSession.shouldDeactivateOnStop {
                Self.deactivateAudioSession()
            }
            audioSession.didDeactivate()
        }
    }

    // MARK: - Internals (queue-held)

    private func startConfiguredEngineLocked(
        vpioEnabled: Bool,
        bufferSize: AVAudioFrameCount,
        tapHandler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) throws {
        guard let engineStarter else {
            try startEngineLocked(
                vpioEnabled: vpioEnabled,
                bufferSize: bufferSize,
                tapHandler: tapHandler
            )
            return
        }

        do {
            try engineStarter(audioEngine, vpioEnabled, bufferSize, tapHandler)
        } catch {
            replaceEngineAfterFailureLocked()
            throw error
        }
        running = true
        installConfigurationChangeObserverLocked()
    }

    private func startEngineLocked(
        vpioEnabled: Bool,
        bufferSize: AVAudioFrameCount,
        tapHandler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) throws {
        // iOS: the engine only records while the shared audio session is
        // active in a record-capable category. The session is per *recording*
        // (`RecordingAudioSessionLifecycle`): configured once per process,
        // activated on the first start of a recording, and — the rule the
        // fourth device run broke — never re-activated by a rebuild while the
        // recording is engaged; iOS refuses that from the background (`'!int'`).
        // Doing it here (not at app launch) keeps the orange mic indicator honest.
        let preparation = audioSession.prepareForEngineStart()
        do {
            switch preparation {
            case .configureAndActivate:
                try Self.configureAudioSessionCategory()
                try Self.activateAudioSession()
            case .activateOnly:
                try Self.activateAudioSession()
            case .alreadyActive:
                break
            }
        } catch {
            audioSession.activationFailed()
            AudioCaptureDiagnostics.append(
                "audio_session_activate_failed step=\(preparation) \(AudioCaptureDiagnostics.errorFields(error))"
            )
            throw error
        }
        if preparation != .alreadyActive {
            audioSession.didActivate()
        }
        do {
            try startEngineCoreLocked(vpioEnabled: vpioEnabled, bufferSize: bufferSize, tapHandler: tapHandler)
        } catch {
            // Balanced: a start that fails right after *this call* activated
            // deactivates again, so a failed first start never leaves the mic
            // indicator lit. A failed rebuild mid-recording keeps the session —
            // the recording is still engaged and the next attempt needs it.
            if preparation != .alreadyActive {
                Self.deactivateAudioSession()
                audioSession.didDeactivate()
            }
            throw error
        }
    }

    private func startEngineCoreLocked(
        vpioEnabled: Bool,
        bufferSize: AVAudioFrameCount,
        tapHandler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) throws {
        let inputNode = audioEngine.inputNode
        do {
            try catchingObjCException {
                try inputNode.setVoiceProcessingEnabled(vpioEnabled)
            }
        } catch {
            // VPIO toggle failed before tap install / engine start. Replace
            // the engine so the next attempt isn't on a half-configured one.
            replaceEngineAfterFailureLocked()
            throw error
        }
        if vpioEnabled, #available(macOS 14.0, *) {
            do {
                try catchingObjCException {
                    inputNode.voiceProcessingOtherAudioDuckingConfiguration = .init(
                        enableAdvancedDucking: false,
                        duckingLevel: .min
                    )
                }
            } catch {
                let errorType = AudioCaptureDiagnostics.errorType(error)
                logger.debug(
                    "shared_mic_engine_ducking_config_failed error_type=\(errorType, privacy: .public) error_detail=\(error.localizedDescription, privacy: .private)"
                )
            }
        }

        let liveFormat: AVAudioFormat
        do {
            liveFormat = try catchingObjCException {
                inputNode.outputFormat(forBus: 0)
            }
        } catch {
            replaceEngineAfterFailureLocked()
            throw error
        }
        guard liveFormat.sampleRate > 0, liveFormat.channelCount > 0 else {
            replaceEngineAfterFailureLocked()
            throw AVAudioEngineMicrophonePlatformError.invalidInputFormat(
                sampleRate: liveFormat.sampleRate,
                channels: liveFormat.channelCount
            )
        }

        do {
            try catchingObjCException {
                inputNode.installTap(
                    onBus: 0,
                    bufferSize: bufferSize,
                    format: nil
                ) { buffer, time in
                    tapHandler(buffer, time)
                }
            }
        } catch {
            try? catchingObjCException {
                inputNode.removeTap(onBus: 0)
            }
            try? catchingObjCException {
                try inputNode.setVoiceProcessingEnabled(false)
            }
            replaceEngineAfterFailureLocked()
            throw error
        }

        do {
            try catchingObjCException {
                try audioEngine.start()
            }
        } catch {
            try? catchingObjCException {
                inputNode.removeTap(onBus: 0)
            }
            try? catchingObjCException {
                try inputNode.setVoiceProcessingEnabled(false)
            }
            replaceEngineAfterFailureLocked()
            throw error
        }
        running = true
        installConfigurationChangeObserverLocked()
        installDefaultInputChangeObserverLocked()
    }

    private func tearDownLocked() {
        removeConfigurationChangeObserverLocked()
        // The AVAudioSession observers are *not* removed here: they live for
        // the platform's lifetime (installed in init, removed in deinit), so a
        // recording whose rebuild failed still hears the route come back.
        guard engineStarter == nil else {
            audioEngine = AVAudioEngine()
            running = false
            lastSucceededAttemptLocked = nil
            return
        }
        let inputNode = audioEngine.inputNode
        try? catchingObjCException {
            inputNode.removeTap(onBus: 0)
        }
        try? catchingObjCException {
            try inputNode.setVoiceProcessingEnabled(false)
        }
        try? catchingObjCException {
            audioEngine.stop()
        }
        // Replace the engine. Releasing the old instance tears down the
        // VPAU aggregate device coreaudiod created for it, so a sibling
        // AVAudioEngine in the same process doesn't inherit duplex layout.
        audioEngine = AVAudioEngine()
        running = false
        lastSucceededAttemptLocked = nil
    }

    /// Reset between failed device attempts (no tap installed yet, just
    /// hand back a fresh engine for the next try).
    private func resetEngineLocked() {
        removeConfigurationChangeObserverLocked()
        try? catchingObjCException {
            audioEngine.stop()
        }
        audioEngine = AVAudioEngine()
        running = false
        lastSucceededAttemptLocked = nil
    }

    private func replaceEngineAfterFailureLocked() {
        removeConfigurationChangeObserverLocked()
        try? catchingObjCException {
            audioEngine.stop()
        }
        audioEngine = AVAudioEngine()
        running = false
        lastSucceededAttemptLocked = nil
    }

    /// Observe `AVAudioEngine.configurationChangeNotification` on the
    /// current `audioEngine`: log every fire to `dictation-audio.log` and
    /// hand the stream an input hint.
    /// Core Audio posts this when the engine's input chain is renegotiated
    /// out from under us — default-input device change, sample-rate
    /// change, exclusive-access takeover by another process. Without
    /// observing it, those events are invisible in our logs and the
    /// silent tap-stall they can leave behind has no signature beyond
    /// "buffers stopped arriving."
    private func installConfigurationChangeObserverLocked() {
        let token = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] notification in
            guard let self, let engine = notification.object as? AVAudioEngine else { return }
            let engineBox = UncheckedSendableAudioEngine(engine)
            self.queue.async { [weak self, engineBox] in
                guard let self else { return }
                let format = engineBox.inputFormat()
                let snapshot = (
                    sr: format?.sampleRate ?? 0,
                    ch: format?.channelCount ?? 0,
                    isRunning: self.running
                )
                let engineIsRunning = engineBox.isEngineRunning()
                let defaultInput = AudioCaptureDiagnostics.defaultInputDeviceSummary()
                AudioCaptureDiagnostics.append(
                    "shared_mic_engine_configuration_changed sr=\(snapshot.sr) ch=\(snapshot.ch) isRunning=\(snapshot.isRunning) engine_is_running=\(engineIsRunning) \(defaultInput)"
                )
                self.logger.info(
                    "shared_mic_engine_configuration_changed sr=\(snapshot.sr, privacy: .public) ch=\(snapshot.ch, privacy: .public) isRunning=\(snapshot.isRunning, privacy: .public)"
                )
                // On iOS this notification means the engine HAS STOPPED (the
                // I/O unit saw its input or output hardware change — including
                // the output flipping to the speaker right after our own
                // activation). Reflect that with a teardown — session untouched
                // — so the stream's policy sees `engine down` and rebuilds now
                // rather than watching for buffers that will never come.
                guard engineBox.wraps(self.audioEngine) else { return }
                if self.running {
                    self.tearDownLocked()
                    AudioCaptureDiagnostics.append("shared_mic_engine_configuration_changed_stopped")
                }
                if self.audioSession.isEngaged {
                    AudioCaptureDiagnostics.append("shared_mic_engine_configuration_changed_restart")
                    self.defaultInputChangeHandler?()
                }
            }
        }
        configurationChangeObserver = token
    }

    private func removeConfigurationChangeObserverLocked() {
        if let token = configurationChangeObserver {
            NotificationCenter.default.removeObserver(token)
            configurationChangeObserver = nil
        }
    }

    // No HAL on iOS. Per-engine install/remove are no-ops here: the session
    // observers below live for the platform's lifetime (see the property doc).
    private func installDefaultInputChangeObserverLocked() {}
    private func removeDefaultInputChangeObserverLocked() {}

    /// AVAudioSession's route-change and interruption notifications, mapped to
    /// the engine-rebuild handler the Mac uses (`RecordingAudioSessionLifecycle`
    /// spells out the model). Everything is decided on `queue` so it sees the
    /// same `audioSession` state the start/stop paths do.
    private func installAudioSessionObservers() {
        guard audioSessionObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        let routeToken = center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: nil
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw) ?? .unknown
            let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let previousInput = previous?.inputs.first
            let current = session.currentRoute
            let currentInput = current.inputs.first
            let inputChanged = RecordingAudioSessionLifecycle.inputRouteChanged(
                isCategoryChange: reason == .categoryChange,
                previousInputUID: previousInput?.uid, currentInputUID: currentInput?.uid
            )
            AudioCaptureDiagnostics.append(
                "audio_route_changed reason=\(Self.label(for: reason)) input=\(Self.portLabel(previousInput))→\(Self.portLabel(currentInput)) output=\(Self.portLabel(previous?.outputs.first))→\(Self.portLabel(current.outputs.first)) input_changed=\(inputChanged)"
            )
            guard inputChanged else { return }   // our own activation, a category set, an output override
            self?.queue.async { [weak self] in
                guard let self, self.audioSession.isEngaged else { return }
                // An input hint, like the Mac's default-input change: the
                // stream's policy rebuilds only if the engine has stopped
                // delivering. Session untouched either way.
                self.defaultInputChangeHandler?()
            }
        }
        let interruptionToken = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: nil
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            guard let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                // A call, Siri or an alarm took the session and stopped the
                // engine. The recording stays engaged (the island shows "No
                // input"); the session is marked interrupted so the resume path
                // knows it must re-activate — the one legitimate re-activation.
                AudioCaptureDiagnostics.append("audio_session_interruption_began")
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    self.audioSession.interruptionBegan()
                    // The system stopped the engine: tear it down (session
                    // untouched) so the `.ended` hint reads `engine down` and
                    // rebuilds immediately instead of after a recheck.
                    if self.running { self.tearDownLocked() }
                }
            case .ended:
                let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
                AudioCaptureDiagnostics.append("audio_session_interruption_ended should_resume=\(shouldResume)")
                guard shouldResume else { return }
                self?.queue.async { [weak self] in
                    guard let self, self.audioSession.isEngaged else { return }
                    // iOS says the interrupter is gone: the rebuild re-activates
                    // (`.activateOnly`) and restarts the engine.
                    self.defaultInputChangeHandler?()
                }
            @unknown default:
                break
            }
        }
        audioSessionObservers = [routeToken, interruptionToken]
    }

    private static func portLabel(_ port: AVAudioSessionPortDescription?) -> String {
        port?.portType.rawValue ?? "none"
    }

    /// Record-capable session. `.playAndRecord` (not `.record`) so a future
    /// start/stop sound or haptic can play, and so the audio background mode
    /// keeps the process alive while the session is active. `.default` mode
    /// keeps the system's speech-friendly input processing; `.measurement`
    /// would hand Parakeet a rawer, quieter signal.
    ///
    /// `.mixWithOthers` is not optional: a recording started from a Control
    /// or the Action Button begins with the app in the background, and iOS
    /// refuses to activate a *non-mixable* session there (`'!int'`,
    /// `cannotInterruptOthers`, 560557684 — seen on the first device run,
    /// 2026-09-13). Mixable sessions may activate in the background; the cost
    /// is that another app's music keeps playing under the recording.
    ///
    /// Issued once per process (`RecordingAudioSessionLifecycle.isConfigured`):
    /// the category persists, and re-issuing it on an active session from the
    /// background is a re-negotiation iOS may refuse.
    private static func configureAudioSessionCategory() throws {
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .mixWithOthers]
        if #available(iOS 26.0, *) {
            options.insert(.allowBluetoothHFP)
        } else {
            options.insert(.allowBluetooth)
        }
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: options)
        AudioCaptureDiagnostics.append("audio_session_configured category=playAndRecord")
    }

    /// Once per recording (and again after an interruption ended). Never from a
    /// rebuild while the recording is engaged.
    private static func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setActive(true, options: [])
        AudioCaptureDiagnostics.append(
            "audio_session_active category=playAndRecord sr=\(session.sampleRate) input=\(session.currentRoute.inputs.first?.portType.rawValue ?? "none") output=\(session.currentRoute.outputs.first?.portType.rawValue ?? "none")"
        )
    }

    /// Ending the session is what tells iOS the recording is over (mic
    /// indicator off, background-audio window closed, other apps' audio resumes).
    /// Called from `stopEngine()` whenever the session is ours — engine running
    /// or not — and from a first start that failed right after activating.
    private static func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            AudioCaptureDiagnostics.append("audio_session_inactive")
        } catch {
            AudioCaptureDiagnostics.append(
                "audio_session_deactivate_failed \(AudioCaptureDiagnostics.errorFields(error))"
            )
        }
    }

    private static func label(for reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "new_device"
        case .oldDeviceUnavailable: return "device_gone"
        case .categoryChange: return "category"
        case .override: return "override"
        case .wakeFromSleep: return "wake"
        case .noSuitableRouteForCategory: return "no_route"
        case .routeConfigurationChange: return "config"
        @unknown default: return "other"
        }
    }

    public func setDefaultInputChangeHandler(_ handler: (@Sendable () -> Void)?) {
        defaultInputChangeHandlerLock.lock()
        _defaultInputChangeHandler = handler
        defaultInputChangeHandlerLock.unlock()
    }

    private var defaultInputChangeHandler: (@Sendable () -> Void)? {
        defaultInputChangeHandlerLock.lock()
        defer { defaultInputChangeHandlerLock.unlock() }
        return _defaultInputChangeHandler
    }
}
#endif

import AVFoundation
import CoreAudio
import Foundation
import os

/// Abstract surface that `SharedMicrophoneStream` uses to drive real
/// `AVAudioEngine` operations. Splitting it out lets unit tests exercise the
/// stream's state machine and fan-out under a deterministic mock, while the
/// production adapter handles the Core Audio side.
///
/// Implementations must serialize concurrent calls. `SharedMicrophoneStream`
/// also serializes via its own engine queue, so platform implementations may
/// rely on that — but they must remain reentrancy-safe (e.g. handle a stop
/// during a partially-failed start).
public protocol MicrophoneEnginePlatform: AnyObject, Sendable {
    /// True between a successful `configureAndStart` and the next
    /// `stopEngine`. Implementations may also set this to `false` if the
    /// engine fails post-start.
    var isEngineRunning: Bool { get }

    /// Live input format reported by the running engine, or `nil` if the
    /// engine is not running or its format is invalid.
    var inputFormat: AVAudioFormat? { get }

    /// Idempotent start. Stops any existing engine and rebuilds it with the
    /// requested VPIO mode. Installs `tapHandler` as the buffer callback;
    /// the handler runs on the audio render thread.
    ///
    /// - Important: The buffer passed to `tapHandler` is valid only for the
    ///   synchronous duration of the call. Implementations must not retain
    ///   the buffer past return.
    func configureAndStart(
        vpioEnabled: Bool,
        bufferSize: AVAudioFrameCount,
        tapHandler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) throws

    /// Stop the engine, remove the tap, and tear down VPIO. Recreates the
    /// underlying `AVAudioEngine` so coreaudiod releases the VPAU aggregate
    /// (`CADefaultDeviceAggregate-<pid>-N`). Mirrors the ephemeral-engine
    /// pattern proven in `MicrophoneCapture` (PR #186).
    func stopEngine()

    /// Install a handler invoked when the **system default input device**
    /// changes while the engine is running. The owner uses this to "follow the
    /// default input" — rebuild the engine so it re-resolves onto the new
    /// device (the device-attempt chain is re-evaluated on each start) without
    /// dropping subscribers, so an in-progress recording simply continues on
    /// the new mic. Pass `nil` to clear.
    func setDefaultInputChangeHandler(_ handler: (@Sendable () -> Void)?)
}

public extension MicrophoneEnginePlatform {
    /// Default no-op so platforms that don't observe device changes (test
    /// doubles, the diagnostic-only `AudioProcessor` path) need no changes.
    func setDefaultInputChangeHandler(_ handler: (@Sendable () -> Void)?) {}
}

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
    /// next instance gets its own observer. Recorded here purely to
    /// surface the signal in `dictation-audio.log` — Core Audio sends
    /// this when the input chain reconfigures (default-input change,
    /// format change, sample-rate change), which is the most likely
    /// trigger for the silent tap-stall under investigation.
    private var configurationChangeObserver: NSObjectProtocol?
#if os(macOS)
    private var defaultInputChangeObserver: AudioObjectPropertyListenerBlock?
#else
    /// AVAudioSession route-change + interruption observers (the iOS stand-in
    /// for the HAL default-input listener). Cleared on every teardown.
    private var audioSessionObservers: [NSObjectProtocol] = []
#endif
    /// Handler invoked from the default-input listener (owner follows the new
    /// device). Held under its own lock — the listener fires on
    /// `defaultInputListenerQueue`, not the engine `queue`.
    private let defaultInputChangeHandlerLock = NSLock()
    private var _defaultInputChangeHandler: (@Sendable () -> Void)?

    public init(
        deviceAttemptsBuilder: DeviceAttemptsBuilder? = nil,
        inputDeviceSetter: InputDeviceSetter? = nil
    ) {
        self.deviceAttemptsBuilder = deviceAttemptsBuilder
        self.inputDeviceSetter = inputDeviceSetter ?? avAudioEngineDefaultInputDeviceSetter
        self.engineStarter = nil
    }

    init(
        deviceAttemptsBuilder: DeviceAttemptsBuilder? = nil,
        inputDeviceSetter: InputDeviceSetter? = nil,
        engineStarter: @escaping EngineStarter
    ) {
        self.deviceAttemptsBuilder = deviceAttemptsBuilder
        self.inputDeviceSetter = inputDeviceSetter ?? avAudioEngineDefaultInputDeviceSetter
        self.engineStarter = engineStarter
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
                        "shared_mic_engine_input_device_started source=\(attempt.source.logValue) device=\(deviceLabel) transport=\(transport) vpio=\(vpioEnabled)"
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
            guard running else { return }
            tearDownLocked()
#if !os(macOS)
            // Only here, not in `tearDownLocked`: a follow-the-input rebuild
            // (route change) tears down and restarts while the recording
            // continues, and must keep the session active — deactivating with
            // `.notifyOthersOnDeactivation` mid-recording would tell other apps
            // to resume and re-negotiate the route for nothing.
            Self.deactivateAudioSession()
#endif
            logger.info("shared_mic_engine_stopped")
            AudioCaptureDiagnostics.append("shared_mic_engine_stopped")
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
#if !os(macOS)
        // iOS: the engine only records while the shared audio session is
        // active in a record-capable category. Doing this here (not at app
        // launch) keeps the orange mic indicator honest. Activate/deactivate
        // are balanced: a start that fails after activation deactivates again,
        // so a failed start never leaves the mic indicator lit or other apps
        // ducked. The successful pair's deactivate lives in `stopEngine()`.
        do {
            try Self.activateAudioSession()
        } catch {
            AudioCaptureDiagnostics.append(
                "audio_session_activate_failed \(AudioCaptureDiagnostics.errorFields(error))"
            )
            throw error
        }
        do {
            try startEngineCoreLocked(vpioEnabled: vpioEnabled, bufferSize: bufferSize, tapHandler: tapHandler)
        } catch {
            Self.deactivateAudioSession()
            throw error
        }
#else
        try startEngineCoreLocked(vpioEnabled: vpioEnabled, bufferSize: bufferSize, tapHandler: tapHandler)
#endif
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
        removeDefaultInputChangeObserverLocked()
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
        removeDefaultInputChangeObserverLocked()
        try? catchingObjCException {
            audioEngine.stop()
        }
        audioEngine = AVAudioEngine()
        running = false
        lastSucceededAttemptLocked = nil
    }

    private func replaceEngineAfterFailureLocked() {
        removeConfigurationChangeObserverLocked()
        removeDefaultInputChangeObserverLocked()
        try? catchingObjCException {
            audioEngine.stop()
        }
        audioEngine = AVAudioEngine()
        running = false
        lastSucceededAttemptLocked = nil
    }

    /// Observe `AVAudioEngine.configurationChangeNotification` on the
    /// current `audioEngine` and log every fire to `dictation-audio.log`.
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
                let defaultInput = AudioCaptureDiagnostics.defaultInputDeviceSummary()
                AudioCaptureDiagnostics.append(
                    "shared_mic_engine_configuration_changed sr=\(snapshot.sr) ch=\(snapshot.ch) isRunning=\(snapshot.isRunning) \(defaultInput)"
                )
                self.logger.info(
                    "shared_mic_engine_configuration_changed sr=\(snapshot.sr, privacy: .public) ch=\(snapshot.ch, privacy: .public) isRunning=\(snapshot.isRunning, privacy: .public)"
                )
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

#if os(macOS)
    private func installDefaultInputChangeObserverLocked() {
        guard defaultInputChangeObserver == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            AudioCaptureDiagnostics.append(
                "audio_default_input_changed \(AudioCaptureDiagnostics.defaultInputDeviceSummary())"
            )
            // Follow the new default input (rebuild onto it, recording continues).
            self?.defaultInputChangeHandler?()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            defaultInputListenerQueue,
            block
        )
        guard status == noErr else {
            AudioCaptureDiagnostics.append(
                "audio_default_input_listener_failed status=\(status)"
            )
            return
        }
        defaultInputChangeObserver = block
    }

    private func removeDefaultInputChangeObserverLocked() {
        guard let block = defaultInputChangeObserver else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            defaultInputListenerQueue,
            block
        )
        defaultInputChangeObserver = nil
    }
#else
    // No HAL on iOS. The equivalents are AVAudioSession's route-change and
    // interruption notifications. Both funnel into the same "follow the input"
    // handler the Mac uses, so `SharedMicrophoneStream` rebuilds the engine
    // without dropping subscribers and the recording simply continues.
    private func installDefaultInputChangeObserverLocked() {
        guard audioSessionObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        let routeToken = center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: nil
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw) ?? .unknown
            AudioCaptureDiagnostics.append("audio_route_changed reason=\(Self.label(for: reason))")
            switch reason {
            case .newDeviceAvailable, .oldDeviceUnavailable, .override, .routeConfigurationChange, .wakeFromSleep:
                // Same semantics as the Mac's default-input change: re-point, keep recording.
                self?.defaultInputChangeHandler?()
            default:
                break
            }
        }
        let interruptionToken = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: nil
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            guard let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                // A call, Siri or an alarm took the session. The engine is now
                // stopped by the system; the stall observer reports it upstream
                // and the island shows Paused. Nothing to do here but log.
                AudioCaptureDiagnostics.append("audio_session_interruption_began")
            case .ended:
                let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
                AudioCaptureDiagnostics.append("audio_session_interruption_ended should_resume=\(shouldResume)")
                if shouldResume {
                    // iOS says the interrupter is gone and we may carry on: rebuild.
                    self?.defaultInputChangeHandler?()
                }
            @unknown default:
                break
            }
        }
        audioSessionObservers = [routeToken, interruptionToken]
    }

    private func removeDefaultInputChangeObserverLocked() {
        audioSessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        audioSessionObservers.removeAll()
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
    private static func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .mixWithOthers]
        if #available(iOS 26.0, *) {
            options.insert(.allowBluetoothHFP)
        } else {
            options.insert(.allowBluetooth)
        }
        try session.setCategory(.playAndRecord, mode: .default, options: options)
        try session.setActive(true, options: [])
        AudioCaptureDiagnostics.append(
            "audio_session_active category=playAndRecord sr=\(session.sampleRate) input=\(session.currentRoute.inputs.first?.portType.rawValue ?? "none")"
        )
    }

    /// Ending the session is what tells iOS the recording is over (mic
    /// indicator off, background-audio window closed, other apps' audio resumes).
    /// Called from `stopEngine()` and from a start that failed after activating.
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
#endif

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

/// Default explicit-device setter for `AVAudioEngineMicrophonePlatform`
/// (used when the initializer's `inputDeviceSetter` is `nil`). File-scope and
/// internal: a public initializer's default argument can only name public
/// symbols, so the platform choice is resolved inside the initializer instead.
#if os(macOS)
let avAudioEngineDefaultInputDeviceSetter: AVAudioEngineMicrophonePlatform.InputDeviceSetter = { deviceID, engine in
    AudioDeviceManager.setInputDevice(deviceID, on: engine)
}
#else
/// iOS never resolves an explicit device: the attempt chain is empty and
/// AVAudioSession owns routing, so an explicit set is always a refusal.
let avAudioEngineDefaultInputDeviceSetter: AVAudioEngineMicrophonePlatform.InputDeviceSetter = { _, _ in false }
#endif

public enum AVAudioEngineMicrophonePlatformError: Error, Equatable, LocalizedError {
    case deviceSetFailed(MeetingInputDeviceAttempt)
    case invalidInputFormat(sampleRate: Double, channels: AVAudioChannelCount)
    case noDeviceAvailable

    public var errorDescription: String? {
        switch self {
        case .deviceSetFailed(let attempt):
            return "Failed to set \(attempt.source.logValue) input device"
        case .invalidInputFormat(let sampleRate, let channels):
            return "Invalid input format: sampleRate=\(sampleRate) channels=\(channels)"
        case .noDeviceAvailable:
            return "No microphone input device available"
        }
    }
}

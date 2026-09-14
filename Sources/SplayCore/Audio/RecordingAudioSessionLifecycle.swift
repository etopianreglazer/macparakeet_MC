import Foundation

/// The record-capable audio session as a value-type state machine — the policy
/// half of what `AVAudioEngineMicrophonePlatform` does with `AVAudioSession` on
/// iOS, kept portable so it is tested on the Mac where `AVAudioSession` does not
/// exist.
///
/// The model is Voice Memos': **the session is per recording, the engine is per
/// configuration.** The session is configured once per process and activated
/// once per recording; an engine rebuild (route change, configuration change,
/// retry) never re-issues either. The only legitimate re-activation is after an
/// interruption, because the system deactivated us. Deactivation happens once,
/// on stop, regardless of whether the engine was still running — a recording
/// whose engine died mid-way still owns the session (mic indicator, background
/// window) until the user stops.
///
/// Why this exists: the fourth device run (2026-09-14) re-activated an already
/// active session from a route-change rebuild while the app was in the
/// background, which iOS refused with `'!int'`, three times, and the recording
/// stayed dead with the session leaked because `stopEngine` only deactivated a
/// *running* engine.
public struct RecordingAudioSessionLifecycle: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// No recording owns the session.
        case idle
        /// `setActive(true)` succeeded and nothing has taken it away.
        case active
        /// The system took the session (call, Siri, alarm). We still own the
        /// recording; the engine is stopped until we re-activate.
        case interrupted
    }

    /// What the platform must do to the session before starting the engine.
    public enum EngineStartPreparation: Equatable, Sendable {
        /// First recording in this process: set the category, then activate.
        case configureAndActivate
        /// Category is set (persists per process); the session is not active.
        case activateOnly
        /// Rebuild during a recording: touch nothing, just start the engine.
        case alreadyActive
    }

    public private(set) var phase: Phase = .idle
    public private(set) var isConfigured = false

    public init() {}

    /// A recording is in progress from the session's point of view — the engine
    /// may be running, stopped by the system, or between rebuild attempts.
    /// Route/configuration/interruption events matter only while engaged.
    public var isEngaged: Bool { phase != .idle }

    /// The stop path must call `setActive(false)` exactly when this is true.
    public var shouldDeactivateOnStop: Bool { phase == .active }

    /// Pure: does not mutate. Call `didActivate()` after the returned steps
    /// succeed, `activationFailed()` if they throw.
    public func prepareForEngineStart() -> EngineStartPreparation {
        switch phase {
        case .active:
            return .alreadyActive
        case .idle, .interrupted:
            return isConfigured ? .activateOnly : .configureAndActivate
        }
    }

    /// `setActive(true)` (and, first time, `setCategory`) succeeded.
    public mutating func didActivate() {
        isConfigured = true
        phase = .active
    }

    /// The activation steps threw. Nothing changed; the category may or may not
    /// have been applied — re-issuing it next time is harmless when idle.
    public mutating func activationFailed() {}

    /// `setActive(false)` was issued (success or not — the next start
    /// re-activates either way).
    public mutating func didDeactivate() {
        phase = .idle
    }

    /// `AVAudioSession.interruptionNotification` `.began`: the system holds the
    /// session and has stopped our engine. A recording stays engaged so the
    /// `.ended` notification can bring it back.
    public mutating func interruptionBegan() {
        guard phase == .active else { return }
        phase = .interrupted
    }

    /// Route changes on iOS are mostly self-inflicted (our own activation, a
    /// category set, an output override) and never require a rebuild unless the
    /// *input* port actually changed under a running recording. Compare the
    /// previous route's input UID with the current one; `nil` means "no input
    /// port".
    ///
    /// Two self-inflicted shapes are excluded by construction:
    /// - `isCategoryChange`: only we set the category, once per process, right
    ///   before the first engine start. The engine that follows starts on the
    ///   new route anyway; restarting it 300 ms later cut the head off every
    ///   recording (fifth device run, 2026-09-14).
    /// - `previousInputUID == nil`: the session had no input before, so no
    ///   engine could have been recording from it. Under a `.playAndRecord`
    ///   recording there is always an input port.
    public static func inputRouteChanged(
        isCategoryChange: Bool = false, previousInputUID: String?, currentInputUID: String?
    ) -> Bool {
        if isCategoryChange { return false }
        guard let previousInputUID else { return false }
        return previousInputUID != currentInputUID
    }
}

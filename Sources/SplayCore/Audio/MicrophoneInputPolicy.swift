import Foundation

/// When does an input *hint* — the engine reported a configuration change, a
/// route changed, an interruption ended (iOS) — turn into an engine rebuild?
/// Pure policy, portable, unit-tested on the Mac; applied by
/// `SharedMicrophoneStream`. **iOS only in practice:** the Mac platform follows
/// upstream MacParakeet v0.8.7 (`docs/plans/upstream-mic-port.md`), which never
/// fires hints and does its own readiness, stall detection and recovery.
///
/// The rule: **stay on the device that is delivering buffers; switch only when
/// the current one stops.** A hint is not a trigger. AirPods auto-switching
/// between the iPhone and the Mac makes the system default flip twice per
/// notification on the phone; following it tore down a healthy engine on the
/// built-in mic, rebuilt it onto a cold HFP route (CoreAudio -10868, the retry
/// ladder, up to ~3 s lost) and then back again (`docs/plans/mac-input-policy.md`
/// has the measured log). The phone's own session model already treats route
/// changes this way; this is the portable half.
///
/// Three inputs decide every hint and recheck: is the platform's engine still
/// running, when did this engine start, and when did the last buffer arrive.
public struct MicrophoneInputPolicy: Equatable, Sendable {
    /// A hint arriving while the engine is up arms rechecks at these offsets
    /// from the hint. Two, because the stop that follows a hint can land after
    /// the first recheck (a device is removed a beat after the default moves).
    public var recheckSchedule: [TimeInterval]
    /// A buffer older than this means the engine has stopped delivering.
    /// Buffers land every ~93 ms (4096 frames at 44.1 kHz), so 1 s is ten
    /// missed buffers.
    public var staleAfter: TimeInterval
    /// An engine that has never delivered is left alone for this long after
    /// it started: a cold Bluetooth mic takes ~10 s of HFP warm-up before the
    /// first buffer, and restarting it restarts the warm-up (dead ≠ silent).
    public var warmupGrace: TimeInterval

    public init(
        recheckSchedule: [TimeInterval] = [1, 3],
        staleAfter: TimeInterval = 1,
        warmupGrace: TimeInterval = 15
    ) {
        self.recheckSchedule = recheckSchedule
        self.staleAfter = staleAfter
        self.warmupGrace = warmupGrace
    }

    /// What a hint does the moment it arrives.
    public enum Verdict: Equatable, Sendable {
        /// The engine is down: rebuild immediately (nothing is delivering).
        case restartNow
        /// The engine is up: look again in `after` seconds.
        case recheck(after: TimeInterval)
        /// No recheck schedule configured: a hint on a running engine is ignored.
        case ignore
    }

    /// What a recheck decides.
    public struct RecheckAction: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case restart
            case recheck(after: TimeInterval)
            case ignore
        }

        public let kind: Kind
        /// For the log: `engine_down`, `stopped`, `never_delivered`, `alive`, `warming`.
        public let reason: String
    }

    public func onHint(engineRunning: Bool) -> Verdict {
        guard engineRunning else { return .restartNow }
        guard let first = recheckSchedule.first else { return .ignore }
        return .recheck(after: first)
    }

    /// `index` is the position in `recheckSchedule` this recheck corresponds
    /// to. Times are seconds on one monotonic clock; `lastBufferAt` is `nil`
    /// when no buffer has arrived since `engineStartedAt`.
    public func onRecheck(
        index: Int,
        engineRunning: Bool,
        engineStartedAt: TimeInterval?,
        lastBufferAt: TimeInterval?,
        now: TimeInterval
    ) -> RecheckAction {
        guard engineRunning else { return RecheckAction(kind: .restart, reason: "engine_down") }
        if let lastBufferAt {
            if now - lastBufferAt < staleAfter {
                return RecheckAction(kind: next(after: index), reason: "alive")
            }
            return RecheckAction(kind: .restart, reason: "stopped")
        }
        // Nothing delivered since this engine started.
        if let engineStartedAt, now - engineStartedAt < warmupGrace {
            return RecheckAction(kind: next(after: index), reason: "warming")
        }
        return RecheckAction(kind: .restart, reason: "never_delivered")
    }

    private func next(after index: Int) -> RecheckAction.Kind {
        let nextIndex = index + 1
        guard recheckSchedule.indices.contains(index), recheckSchedule.indices.contains(nextIndex) else {
            return .ignore
        }
        return .recheck(after: max(0, recheckSchedule[nextIndex] - recheckSchedule[index]))
    }
}

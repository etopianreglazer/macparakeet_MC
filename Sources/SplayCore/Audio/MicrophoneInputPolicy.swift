import Foundation

/// When does an input *hint* — the system default input changed, the engine
/// reported a configuration change, a route changed on iOS — turn into an
/// engine rebuild? Pure policy, portable, unit-tested on the Mac; applied by
/// `SharedMicrophoneStream`.
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
/// The liveness watchdog (`onLivenessTick`, Mac only) uses the same three plus
/// its own rebuild history (`lastRestartAt`, `restartsSinceBuffer`), which is
/// checked first: while a dead input is backing off, the tick waits regardless
/// of engine state. Its dials are `livenessInterval`, `callbackGapLimit`,
/// `livenessRetryInterval` and `livenessRetryCap`.
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

    /// How often the **liveness watchdog** looks at the engine while anyone is
    /// subscribed; `nil` turns it off. Hints are not the only way an input dies:
    /// an engine can report running while its callbacks stop (Bluetooth churn,
    /// upstream MacParakeet #860), a pinned device can start and never deliver
    /// (the reason upstream reverted the explicit System Default pin), and a
    /// follow run can give up. The watchdog catches all three.
    public var livenessInterval: TimeInterval?
    /// A delivering engine whose callbacks stop for this long is frozen. This
    /// is callbacks, not loudness: a quiet room still delivers a buffer every
    /// ~93 ms, so silence never trips it (dead ≠ silent).
    public var callbackGapLimit: TimeInterval
    /// First wait between watchdog-driven rebuilds while the input stays dead;
    /// doubles per consecutive rebuild up to `livenessRetryCap`, and resets as
    /// soon as a buffer arrives.
    public var livenessRetryInterval: TimeInterval
    public var livenessRetryCap: TimeInterval

    /// Mac only for now. On iOS an interruption (a phone call) deliberately
    /// takes the engine down and its end is already a hint; a watchdog would
    /// retry into the call. Enable there only with on-device evidence.
    public static let defaultLivenessInterval: TimeInterval? = {
        #if os(macOS)
        return 1
        #else
        return nil
        #endif
    }()

    public init(
        recheckSchedule: [TimeInterval] = [1, 3],
        staleAfter: TimeInterval = 1,
        warmupGrace: TimeInterval = 15,
        livenessInterval: TimeInterval? = MicrophoneInputPolicy.defaultLivenessInterval,
        callbackGapLimit: TimeInterval = 5,
        livenessRetryInterval: TimeInterval = 10,
        livenessRetryCap: TimeInterval = 60
    ) {
        self.recheckSchedule = recheckSchedule
        self.staleAfter = staleAfter
        self.warmupGrace = warmupGrace
        self.livenessInterval = livenessInterval
        self.callbackGapLimit = callbackGapLimit
        self.livenessRetryInterval = livenessRetryInterval
        self.livenessRetryCap = livenessRetryCap
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

    /// What a liveness tick decides.
    public enum LivenessVerdict: Equatable, Sendable {
        case ok
        /// Rebuild. `reason` for the log: `engine_down`, `callbacks_stopped`,
        /// `never_delivered`.
        case restart(reason: String)
    }

    /// One watchdog tick. `lastRestartAt` / `restartsSinceBuffer` describe the
    /// watchdog's own previous rebuilds, so a dead input is retried on a
    /// widening interval instead of every tick.
    public func onLivenessTick(
        engineRunning: Bool,
        engineStartedAt: TimeInterval?,
        lastBufferAt: TimeInterval?,
        lastRestartAt: TimeInterval?,
        restartsSinceBuffer: Int,
        now: TimeInterval
    ) -> LivenessVerdict {
        if let lastRestartAt, restartsSinceBuffer > 0 {
            let backoff = min(
                livenessRetryCap,
                livenessRetryInterval * pow(2, Double(restartsSinceBuffer - 1))
            )
            if now - lastRestartAt < backoff { return .ok }
        }
        guard engineRunning else { return .restart(reason: "engine_down") }
        if let lastBufferAt {
            return now - lastBufferAt > callbackGapLimit ? .restart(reason: "callbacks_stopped") : .ok
        }
        if let engineStartedAt, now - engineStartedAt >= warmupGrace {
            return .restart(reason: "never_delivered")
        }
        return .ok
    }

    private func next(after index: Int) -> RecheckAction.Kind {
        let nextIndex = index + 1
        guard recheckSchedule.indices.contains(index), recheckSchedule.indices.contains(nextIndex) else {
            return .ignore
        }
        return .recheck(after: max(0, recheckSchedule[nextIndex] - recheckSchedule[index]))
    }
}

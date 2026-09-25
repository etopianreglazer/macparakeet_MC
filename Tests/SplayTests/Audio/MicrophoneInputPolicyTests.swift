import XCTest
@testable import SplayCore

/// The input policy: a hint (default input changed, configuration changed,
/// route changed) restarts the engine only when the engine is no longer
/// delivering. See `docs/plans/mac-input-policy.md` for the measured case.
final class MicrophoneInputPolicyTests: XCTestCase {
    private let policy = MicrophoneInputPolicy(recheckSchedule: [1, 3], staleAfter: 1, warmupGrace: 15)

    // MARK: - Hint

    func testHintWithEngineDownRestartsNow() {
        XCTAssertEqual(policy.onHint(engineRunning: false), .restartNow)
    }

    func testHintWithEngineUpArmsTheFirstRecheck() {
        XCTAssertEqual(policy.onHint(engineRunning: true), .recheck(after: 1))
    }

    func testHintWithNoScheduleIsIgnoredWhileRunning() {
        let none = MicrophoneInputPolicy(recheckSchedule: [], staleAfter: 1, warmupGrace: 15)
        XCTAssertEqual(none.onHint(engineRunning: true), .ignore)
        XCTAssertEqual(none.onHint(engineRunning: false), .restartNow)
    }

    // MARK: - Recheck

    func testRecheckWhileBuffersFlowIgnoresAndArmsTheNext() {
        // AirPods became the default while the built-in mic keeps delivering:
        // stay put. The second recheck is 2 s after the first (3 - 1).
        let action = policy.onRecheck(
            index: 0, engineRunning: true, engineStartedAt: 100, lastBufferAt: 149.9, now: 150
        )
        XCTAssertEqual(action.kind, .recheck(after: 2))
        XCTAssertEqual(action.reason, "alive")
    }

    func testLastRecheckWhileBuffersFlowIgnoresForGood() {
        let action = policy.onRecheck(
            index: 1, engineRunning: true, engineStartedAt: 100, lastBufferAt: 151.95, now: 152
        )
        XCTAssertEqual(action.kind, .ignore)
        XCTAssertEqual(action.reason, "alive")
    }

    func testRecheckAfterBuffersStoppedRestarts() {
        // The AirPods we were recording through left for the phone: the last
        // buffer is older than the stale threshold.
        let action = policy.onRecheck(
            index: 0, engineRunning: true, engineStartedAt: 100, lastBufferAt: 148.5, now: 150
        )
        XCTAssertEqual(action.kind, .restart)
        XCTAssertEqual(action.reason, "stopped")
    }

    func testRecheckWithEngineDownRestartsRegardlessOfBuffers() {
        let action = policy.onRecheck(
            index: 0, engineRunning: false, engineStartedAt: 100, lastBufferAt: 149.95, now: 150
        )
        XCTAssertEqual(action.kind, .restart)
        XCTAssertEqual(action.reason, "engine_down")
    }

    func testRecheckDuringWarmupWithNoBufferYetWaits() {
        // Cold HFP route still waking (~10 s before the first buffer): a hint
        // 90 ms after start — the configuration change that follows every
        // start — must not restart the warm-up.
        let action = policy.onRecheck(
            index: 0, engineRunning: true, engineStartedAt: 100, lastBufferAt: nil, now: 101
        )
        XCTAssertEqual(action.kind, .recheck(after: 2))
        XCTAssertEqual(action.reason, "warming")
    }

    func testRecheckAfterWarmupWithNoBufferEverRestarts() {
        let action = policy.onRecheck(
            index: 1, engineRunning: true, engineStartedAt: 100, lastBufferAt: nil, now: 116
        )
        XCTAssertEqual(action.kind, .restart)
        XCTAssertEqual(action.reason, "never_delivered")
    }

    func testRecheckWithUnknownStartAndNoBufferRestarts() {
        // No baseline at all: treat as never delivered rather than wait forever.
        let action = policy.onRecheck(
            index: 0, engineRunning: true, engineStartedAt: nil, lastBufferAt: nil, now: 5
        )
        XCTAssertEqual(action.kind, .restart)
        XCTAssertEqual(action.reason, "never_delivered")
    }

    func testDefaultsMatchTheDocumentedNumbers() {
        let defaults = MicrophoneInputPolicy()
        XCTAssertEqual(defaults.recheckSchedule, [1, 3])
        XCTAssertEqual(defaults.staleAfter, 1)
        XCTAssertEqual(defaults.warmupGrace, 15)
    }

    // MARK: - Liveness watchdog (callbacks, never loudness)

    private func tick(
        _ policy: MicrophoneInputPolicy? = nil,
        running: Bool = true,
        startedAt: TimeInterval? = 0,
        lastBuffer: TimeInterval?,
        lastRestart: TimeInterval? = nil,
        restarts: Int = 0,
        now: TimeInterval
    ) -> MicrophoneInputPolicy.LivenessVerdict {
        (policy ?? self.policy).onLivenessTick(
            engineRunning: running,
            engineStartedAt: startedAt,
            lastBufferAt: lastBuffer,
            lastRestartAt: lastRestart,
            restartsSinceBuffer: restarts,
            now: now
        )
    }

    func testLivenessDeliveringEngineIsOk() {
        XCTAssertEqual(tick(lastBuffer: 99.9, now: 100), .ok)
    }

    func testLivenessCallbackGapRestarts() {
        // Engine claims to run, callbacks stopped 6 s ago (limit 5 s).
        XCTAssertEqual(tick(lastBuffer: 94, now: 100), .restart(reason: "callbacks_stopped"))
    }

    func testLivenessShortGapIsNotAFreeze() {
        XCTAssertEqual(tick(lastBuffer: 97, now: 100), .ok)
    }

    func testLivenessWarmingEngineIsLeftAlone() {
        // Cold HFP: no buffer yet, 10 s into a 15 s grace.
        XCTAssertEqual(tick(startedAt: 90, lastBuffer: nil, now: 100), .ok)
    }

    func testLivenessNeverDeliveredAfterGraceRestarts() {
        XCTAssertEqual(tick(startedAt: 80, lastBuffer: nil, now: 100), .restart(reason: "never_delivered"))
    }

    func testLivenessEngineDownRestarts() {
        XCTAssertEqual(tick(running: false, lastBuffer: nil, now: 100), .restart(reason: "engine_down"))
    }

    func testLivenessRetriesBackOffWhileInputStaysDead() {
        // First watchdog rebuild at t=100: wait 10 s, then 20 s after the second.
        XCTAssertEqual(tick(running: false, lastBuffer: nil, lastRestart: 100, restarts: 1, now: 105), .ok)
        XCTAssertEqual(
            tick(running: false, lastBuffer: nil, lastRestart: 100, restarts: 1, now: 111),
            .restart(reason: "engine_down")
        )
        XCTAssertEqual(tick(running: false, lastBuffer: nil, lastRestart: 100, restarts: 2, now: 115), .ok)
        XCTAssertEqual(
            tick(running: false, lastBuffer: nil, lastRestart: 100, restarts: 2, now: 121),
            .restart(reason: "engine_down")
        )
    }

    func testLivenessBackoffIsCapped() {
        XCTAssertEqual(
            tick(running: false, lastBuffer: nil, lastRestart: 0, restarts: 10, now: 61),
            .restart(reason: "engine_down")
        )
    }
}

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
}

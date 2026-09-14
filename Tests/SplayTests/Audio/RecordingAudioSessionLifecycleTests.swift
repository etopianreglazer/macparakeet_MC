import XCTest
@testable import SplayCore

/// The iOS audio-session policy, exercised on the Mac. Each test is one rule
/// from the Voice Memos model: configure once, activate once per recording,
/// never re-activate on a rebuild, re-activate after an interruption,
/// deactivate on stop whether or not the engine survived.
final class RecordingAudioSessionLifecycleTests: XCTestCase {
    func testFreshProcessConfiguresAndActivates() {
        let session = RecordingAudioSessionLifecycle()
        XCTAssertEqual(session.prepareForEngineStart(), .configureAndActivate)
        XCTAssertFalse(session.isEngaged)
        XCTAssertFalse(session.shouldDeactivateOnStop)
    }

    func testRebuildDuringRecordingTouchesNothing() {
        var session = RecordingAudioSessionLifecycle()
        session.didActivate()

        // A route-change / configuration-change rebuild, or a retry after a
        // failed rebuild: the session is ours, the engine restarts alone.
        XCTAssertEqual(session.prepareForEngineStart(), .alreadyActive)
        XCTAssertTrue(session.isEngaged)
        XCTAssertTrue(session.shouldDeactivateOnStop)
    }

    func testSecondRecordingActivatesWithoutReconfiguring() {
        var session = RecordingAudioSessionLifecycle()
        session.didActivate()
        session.didDeactivate()

        XCTAssertEqual(session.phase, .idle)
        XCTAssertFalse(session.isEngaged)
        XCTAssertEqual(session.prepareForEngineStart(), .activateOnly, "the category persists per process")
    }

    func testInterruptionKeepsTheRecordingEngagedAndRequiresReactivation() {
        var session = RecordingAudioSessionLifecycle()
        session.didActivate()
        session.interruptionBegan()

        XCTAssertEqual(session.phase, .interrupted)
        XCTAssertTrue(session.isEngaged, "the user is still recording; the .ended notification must be able to resume")
        XCTAssertFalse(session.shouldDeactivateOnStop, "the system already took the session")
        XCTAssertEqual(session.prepareForEngineStart(), .activateOnly)

        session.didActivate()
        XCTAssertEqual(session.phase, .active)
    }

    func testInterruptionWhileIdleIsIgnored() {
        var session = RecordingAudioSessionLifecycle()
        session.interruptionBegan()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertFalse(session.isEngaged)
    }

    func testFailedActivationLeavesTheSessionIdle() {
        var session = RecordingAudioSessionLifecycle()
        session.activationFailed()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(session.prepareForEngineStart(), .configureAndActivate)
    }

    func testStopAfterEngineDeathStillDeactivates() {
        // The failing device run: the rebuild failed three times, the engine
        // was left stopped, and the session had to be released on stop anyway.
        var session = RecordingAudioSessionLifecycle()
        session.didActivate()
        XCTAssertTrue(session.shouldDeactivateOnStop)
        session.didDeactivate()
        XCTAssertFalse(session.isEngaged)
    }

    // MARK: - Route changes

    func testSameInputPortIsNotAnInputChange() {
        XCTAssertFalse(RecordingAudioSessionLifecycle.inputRouteChanged(
            previousInputUID: "Built-In Microphone", currentInputUID: "Built-In Microphone"
        ))
    }

    func testDifferentInputPortIsAnInputChange() {
        XCTAssertTrue(RecordingAudioSessionLifecycle.inputRouteChanged(
            previousInputUID: "Built-In Microphone", currentInputUID: "AirPods Pro"
        ))
        XCTAssertTrue(RecordingAudioSessionLifecycle.inputRouteChanged(
            previousInputUID: "AirPods Pro", currentInputUID: nil
        ), "the input port going away is a change")
    }

    func testInputAppearingWhereThereWasNoneIsOurOwnActivation() {
        // The fifth device run: `reason=category input=none→MicrophoneBuiltIn`
        // 2 ms after activation restarted an engine that had just started.
        XCTAssertFalse(RecordingAudioSessionLifecycle.inputRouteChanged(
            previousInputUID: nil, currentInputUID: "Built-In Microphone"
        ), "no engine could have been recording from a route with no input")
    }

    func testCategoryChangeNeverRestartsTheEngine() {
        XCTAssertFalse(RecordingAudioSessionLifecycle.inputRouteChanged(
            isCategoryChange: true, previousInputUID: "Built-In Microphone", currentInputUID: "AirPods Pro"
        ), "only we set the category, and only before the first engine start")
    }

    func testNoInputOnEitherSideIsNotAnInputChange() {
        XCTAssertFalse(RecordingAudioSessionLifecycle.inputRouteChanged(previousInputUID: nil, currentInputUID: nil))
    }
}

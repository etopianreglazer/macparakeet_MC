import XCTest
import SplayCore
@testable import Splay

@MainActor
final class FnCaptureRouterTests: XCTestCase {
    private var dictationBusy = false
    private var meetingBusy = false
    private var dictationCancellable = false
    private var calls: [String] = []

    private func makeRouter() -> FnCaptureRouter {
        FnCaptureRouter(
            isDictationBusy: { [unowned self] in dictationBusy },
            isMeetingBusy: { [unowned self] in meetingBusy },
            startDictation: { [unowned self] in calls.append("startDictation") },
            stopDictation: { [unowned self] in calls.append("stopDictation") },
            startRecording: { [unowned self] source in calls.append("startRecording(\(source.rawValue))") },
            stopRecording: { [unowned self] in calls.append("stopRecording") },
            cancelDictation: { [unowned self] in calls.append("cancelDictation") },
            isDictationCancellable: { [unowned self] in dictationCancellable }
        )
    }

    func testStartRoutesEachGestureToItsCapture() {
        let router = makeRouter()
        router.start(.microphoneRecording)
        router.start(.dictation)
        router.start(.meeting)
        XCTAssertEqual(calls, [
            "startRecording(\(MeetingAudioSourceMode.microphoneOnly.rawValue))",
            "startDictation",
            "startRecording(\(MeetingAudioSourceMode.microphoneAndSystem.rawValue))",
        ])
    }

    func testCaptureActiveWhenEitherSideIsBusy() {
        let router = makeRouter()
        XCTAssertFalse(router.isCaptureActive)
        dictationBusy = true
        XCTAssertTrue(router.isCaptureActive)
        dictationBusy = false
        meetingBusy = true
        XCTAssertTrue(router.isCaptureActive)
    }

    func testStopGoesToWhicheverIsBusy() {
        let router = makeRouter()
        dictationBusy = true
        router.stop()
        dictationBusy = false
        meetingBusy = true
        router.stop()
        XCTAssertEqual(calls, ["stopDictation", "stopRecording"])
    }

    func testEscapeCancelsADictationOnly() {
        let router = makeRouter()
        dictationBusy = true
        dictationCancellable = true
        XCTAssertTrue(router.escape())
        // Transcribing: busy but not cancellable — Escape is swallowed, not a discard.
        dictationCancellable = false
        XCTAssertTrue(router.escape())
        dictationBusy = false
        meetingBusy = true
        // A stray Escape must never throw away a meeting.
        XCTAssertTrue(router.escape())
        meetingBusy = false
        XCTAssertFalse(router.escape(), "nothing running: the app's idle-Escape handler runs")
        XCTAssertEqual(calls, ["cancelDictation"])
    }

    func testStopWithNothingBusyDoesNothing() {
        makeRouter().stop()
        XCTAssertEqual(calls, [])
    }

    func testStartIsRefusedWhileAnythingIsBusy() {
        // A gesture resolved after something else started (menu bar, island
        // click) must not start a second capture on top of it.
        let router = makeRouter()
        dictationBusy = true
        router.start(.meeting)
        dictationBusy = false
        meetingBusy = true
        router.start(.dictation)
        XCTAssertEqual(calls, [])
    }

    func testDictationBusyCoversCaptureAndTranscriptionButNotDisplayStates() {
        let busy: [DictationFlowState] = [
            .checkingEntitlements(mode: .persistent),
            .startingService(mode: .persistent),
            .recording(mode: .persistent),
            .pendingStop(mode: .persistent),
            .processing,
            .cancelCountdown,
        ]
        for state in busy {
            XCTAssertTrue(DictationFlowCoordinator.isFnBusy(for: state), "\(state)")
        }
        let free: [DictationFlowState] = [
            .idle, .ready,
            .finishing(outcome: .success),
            .finishing(outcome: .noSpeech),
            .finishing(outcome: .error("x")),
            .finishing(outcome: .pasteFailedCopied("x")),
        ]
        for state in free {
            XCTAssertFalse(DictationFlowCoordinator.isFnBusy(for: state), "\(state)")
        }
    }
}

import XCTest
@testable import SplayCore

final class HotkeyGestureControllerTests: XCTestCase {
    func testFirstPressSchedulesStartupAndHoldTimers() {
        let controller = HotkeyGestureController()

        let outputs = controller.triggerPressed(timestampMs: 1_000)

        XCTAssertEqual(
            outputs,
            [
                .scheduleStartupDebounce(milliseconds: FnKeyStateMachine.defaultStartupDebounceMs),
                .scheduleHoldWindow(milliseconds: FnKeyStateMachine.defaultTapThresholdMs),
            ]
        )
    }

    func testQuickReleaseBeforeStartupShowsReadyForSecondTap() {
        let controller = HotkeyGestureController()
        _ = controller.triggerPressed(timestampMs: 1_000)

        let outputs = controller.triggerReleased(timestampMs: 1_050)

        XCTAssertEqual(
            outputs,
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .showReadyForSecondTap,
            ]
        )
    }

    func testQuickReleaseAfterStartupDiscardsWithoutDuplicateReadyOutput() {
        let controller = HotkeyGestureController()
        _ = controller.triggerPressed(timestampMs: 1_000)
        XCTAssertEqual(
            controller.startupDebounceElapsed(),
            [.startRecording(mode: .holdToTalk)]
        )

        let outputs = controller.triggerReleased(timestampMs: 1_050)

        XCTAssertEqual(
            outputs,
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .discardRecording(showReadyPill: true),
            ]
        )
    }

    func testSecondTapStartsPersistentWithoutReschedulingTimers() {
        let controller = HotkeyGestureController()
        _ = controller.triggerPressed(timestampMs: 1_000)
        _ = controller.triggerReleased(timestampMs: 1_050)

        let outputs = controller.triggerPressed(timestampMs: 1_200)

        XCTAssertEqual(outputs, [.startRecording(mode: .persistent)])
    }

    func testInterruptionBeforeStartupCancelsTimersOnly() {
        let controller = HotkeyGestureController()
        _ = controller.triggerPressed(timestampMs: 1_000)

        let outputs = controller.interrupted()

        XCTAssertEqual(outputs, [.cancelStartupDebounce, .cancelHoldWindow])
    }

    func testInterruptionAfterStartupSilentlyDiscards() {
        let controller = HotkeyGestureController()
        _ = controller.triggerPressed(timestampMs: 1_000)
        _ = controller.startupDebounceElapsed()

        let outputs = controller.interrupted()

        XCTAssertEqual(
            outputs,
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .discardRecording(showReadyPill: false),
            ]
        )
    }

    func testInterruptionDuringConfirmedHoldCancelsRecordingImmediately() {
        let controller = HotkeyGestureController()
        _ = controller.triggerPressed(timestampMs: 1_000)
        _ = controller.holdWindowElapsed()

        let outputs = controller.interrupted()

        XCTAssertEqual(
            outputs,
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .cancelRecording,
            ]
        )
        XCTAssertEqual(
            controller.triggerReleased(timestampMs: 1_500),
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
            ]
        )
    }

    func testEscapeWhileIdleDelegatesToIdleHandler() {
        let controller = HotkeyGestureController()

        XCTAssertEqual(controller.escapePressed(), [.escapeWhileIdle])
    }

    func testEscapeDuringReadyWindowResetsWithoutShowingIdleEscape() {
        let controller = HotkeyGestureController()
        _ = controller.triggerPressed(timestampMs: 1_000)
        _ = controller.triggerReleased(timestampMs: 1_050)

        let outputs = controller.escapePressed()

        XCTAssertEqual(outputs, [.cancelStartupDebounce, .cancelHoldWindow])
    }

    func testEscapeDuringProvisionalRecordingCancelsRecording() {
        let controller = HotkeyGestureController()
        _ = controller.triggerPressed(timestampMs: 1_000)
        _ = controller.startupDebounceElapsed()

        let outputs = controller.escapePressed()

        XCTAssertEqual(
            outputs,
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .cancelRecording,
            ]
        )
    }

    func testNonBareReleaseDuringHoldCancelsRecording() {
        let controller = HotkeyGestureController()
        _ = controller.triggerPressed(timestampMs: 1_000)
        _ = controller.holdWindowElapsed()

        let outputs = controller.nonBareTriggerReleased()

        XCTAssertEqual(
            outputs,
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .cancelRecording,
            ]
        )
    }

    func testLowTapThresholdClampsStartupDebounce() {
        let controller = HotkeyGestureController(tapThresholdMs: 50)

        let outputs = controller.triggerPressed(timestampMs: 1_000)

        XCTAssertEqual(
            outputs,
            [
                .scheduleStartupDebounce(milliseconds: 50),
                .scheduleHoldWindow(milliseconds: 50),
            ]
        )
    }

    func testDoubleTapOnlyDoesNotStartHoldToTalk() {
        let controller = HotkeyGestureController(mode: .doubleTapOnly)

        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_000), [])
        XCTAssertEqual(controller.startupDebounceElapsed(), [])
        XCTAssertEqual(controller.holdWindowElapsed(), [])
        XCTAssertEqual(
            controller.triggerReleased(timestampMs: 1_050),
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .showReadyForSecondTap,
            ]
        )
        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_200),
            [.startRecording(mode: .persistent)]
        )
    }

    func testHoldOnlyStartsAfterStartupAndStopsOnRelease() {
        let controller = HotkeyGestureController(mode: .holdOnly)

        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_000),
            [.scheduleStartupDebounce(milliseconds: FnKeyStateMachine.defaultStartupDebounceMs)]
        )
        XCTAssertEqual(
            controller.startupDebounceElapsed(),
            [.startRecording(mode: .holdToTalk)]
        )
        XCTAssertEqual(
            controller.triggerReleased(timestampMs: 1_300),
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .stopRecording,
            ]
        )
    }

    func testHoldOnlyQuickReleaseDoesNotShowSecondTapReadyState() {
        let controller = HotkeyGestureController(mode: .holdOnly)

        _ = controller.triggerPressed(timestampMs: 1_000)

        XCTAssertEqual(
            controller.triggerReleased(timestampMs: 1_050),
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
            ]
        )
    }

    func testSingleTapToggleStartsAndStopsPersistentRecordingOnPresses() {
        let controller = HotkeyGestureController(mode: .singleTapToggle)

        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_000),
            [.startRecording(mode: .persistent)]
        )
        XCTAssertEqual(controller.triggerReleased(timestampMs: 1_050), [])
        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_200),
            [.stopRecording]
        )
        XCTAssertEqual(controller.triggerReleased(timestampMs: 1_250), [])
    }

    func testSingleTapToggleDoesNotUseStartupOrHoldTimers() {
        let controller = HotkeyGestureController(mode: .singleTapToggle)

        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_000), [.startRecording(mode: .persistent)])
        XCTAssertEqual(controller.startupDebounceElapsed(), [])
        XCTAssertEqual(controller.holdWindowElapsed(), [])
    }

    func testSingleTapToggleEscapeCancelsActiveRecording() {
        let controller = HotkeyGestureController(mode: .singleTapToggle)
        _ = controller.triggerPressed(timestampMs: 1_000)

        XCTAssertEqual(controller.escapePressed(), [.cancelRecording])
        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_100), [])
        controller.reset()
        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_200), [.startRecording(mode: .persistent)])
    }

    func testNotifyCancelledByUIBlocksDoubleTapOnlyUntilReset() {
        let controller = HotkeyGestureController(mode: .doubleTapOnly)

        controller.notifyCancelledByUI()

        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_000), [])
        XCTAssertEqual(
            controller.triggerReleased(timestampMs: 1_050),
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
            ]
        )

        controller.reset()

        _ = controller.triggerPressed(timestampMs: 1_100)
        XCTAssertEqual(
            controller.triggerReleased(timestampMs: 1_150),
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .showReadyForSecondTap,
            ]
        )
    }

    func testNotifyCancelledByUIBlocksHoldOnlyUntilReset() {
        let controller = HotkeyGestureController(mode: .holdOnly)

        controller.notifyCancelledByUI()

        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_000), [])
        XCTAssertEqual(
            controller.triggerReleased(timestampMs: 1_050),
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
            ]
        )

        controller.reset()

        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_100),
            [.scheduleStartupDebounce(milliseconds: FnKeyStateMachine.defaultStartupDebounceMs)]
        )
    }

    func testHoldOnlyEscapeDuringCancelWindowConfirmsAndUnblocks() {
        let controller = HotkeyGestureController(mode: .holdOnly)
        _ = controller.triggerPressed(timestampMs: 1_000)
        _ = controller.startupDebounceElapsed()

        XCTAssertEqual(
            controller.escapePressed(),
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .cancelRecording,
            ]
        )
        XCTAssertEqual(
            controller.escapePressed(),
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .cancelRecording,
            ]
        )
        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_200),
            [.scheduleStartupDebounce(milliseconds: FnKeyStateMachine.defaultStartupDebounceMs)]
        )
    }

    func testSuppressedControllerIgnoresGesturesUntilReset() {
        let controller = HotkeyGestureController(mode: .holdOnly)

        controller.suppressUntilReset()

        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_000), [])
        XCTAssertEqual(controller.startupDebounceElapsed(), [])
        XCTAssertEqual(controller.escapePressed(), [])
        XCTAssertEqual(controller.triggerReleased(timestampMs: 1_200), [])

        controller.reset()

        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_300),
            [.scheduleStartupDebounce(milliseconds: FnKeyStateMachine.defaultStartupDebounceMs)]
        )
    }

    func testCancelWindowNotificationOverridesSuppression() {
        let controller = HotkeyGestureController(mode: .holdOnly)

        controller.suppressUntilReset()
        controller.notifyCancelledByUI()

        XCTAssertEqual(
            controller.escapePressed(),
            [
                .cancelStartupDebounce,
                .cancelHoldWindow,
                .cancelRecording,
            ]
        )
    }

    // MARK: - singleAndDoubleTapToggle (fork Fn recording: mic-only vs mic+system)

    func testSingleAndDoubleTap_singleTapResolvesToMicOnly() {
        let controller = HotkeyGestureController(mode: .singleAndDoubleTapToggle)

        // The manager routes a completed bare tap through triggerPressed.
        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_000),
            [.scheduleHoldWindow(milliseconds: FnKeyStateMachine.defaultTapThresholdMs)]
        )

        // No second tap → window elapses → mic-only recording toggles.
        XCTAssertEqual(
            controller.holdWindowElapsed(),
            [.toggleRecording(source: .microphoneOnly)]
        )
    }

    func testSingleAndDoubleTap_doubleTapResolvesToMicAndSystem() {
        let controller = HotkeyGestureController(mode: .singleAndDoubleTapToggle)
        _ = controller.triggerPressed(timestampMs: 1_000)

        // Second tap inside the window → mic+system, pending window cancelled.
        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_150),
            [.cancelHoldWindow, .toggleRecording(source: .microphoneAndSystem)]
        )

        // A stale window timer firing afterwards must do nothing.
        XCTAssertEqual(controller.holdWindowElapsed(), [])
    }

    func testSingleAndDoubleTap_escapeDuringWindowCancelsPending() {
        let controller = HotkeyGestureController(mode: .singleAndDoubleTapToggle)
        _ = controller.triggerPressed(timestampMs: 1_000)

        XCTAssertEqual(controller.escapePressed(), [.cancelHoldWindow])
        XCTAssertEqual(controller.holdWindowElapsed(), [])
    }

    func testSingleAndDoubleTap_ignoresReleaseAndInterruptWhileWaiting() {
        let controller = HotkeyGestureController(mode: .singleAndDoubleTapToggle)
        _ = controller.triggerPressed(timestampMs: 1_000)

        XCTAssertEqual(controller.triggerReleased(timestampMs: 1_010), [])
        XCTAssertEqual(controller.interrupted(), [])
        // Still resolves to mic-only on timeout — typing doesn't cancel a tap toggle.
        XCTAssertEqual(
            controller.holdWindowElapsed(),
            [.toggleRecording(source: .microphoneOnly)]
        )
    }

    // MARK: - tapDoubleTripleToggle (Fn: tap = mic recording, double = dictation, triple = meeting)

    private func makeTriple(active: Bool = false) -> HotkeyGestureController {
        let controller = HotkeyGestureController(mode: .tapDoubleTripleToggle)
        controller.isCaptureActive = { active }
        return controller
    }

    private let window = FnKeyStateMachine.defaultTapThresholdMs

    func testTriple_singleTapResolvesToMicRecordingAfterWindow() {
        let controller = makeTriple()

        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_000), [.scheduleHoldWindow(milliseconds: window)])
        XCTAssertEqual(controller.holdWindowElapsed(), [.startCapture(.microphoneRecording)])
        XCTAssertEqual(controller.holdWindowElapsed(), [])
    }

    func testTriple_doubleTapWaitsOneMoreWindowThenResolvesToDictation() {
        let controller = makeTriple()
        _ = controller.triggerPressed(timestampMs: 1_000)

        // Second tap re-arms the window for a possible third tap; nothing starts yet.
        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_150),
            [.cancelHoldWindow, .scheduleHoldWindow(milliseconds: window)]
        )
        XCTAssertEqual(controller.holdWindowElapsed(), [.startCapture(.dictation)])
        XCTAssertEqual(controller.holdWindowElapsed(), [])
    }

    func testTriple_tripleTapResolvesToMeetingImmediately() {
        let controller = makeTriple()
        _ = controller.triggerPressed(timestampMs: 1_000)
        _ = controller.triggerPressed(timestampMs: 1_150)

        XCTAssertEqual(
            controller.triggerPressed(timestampMs: 1_300),
            [.cancelHoldWindow, .startCapture(.meeting)]
        )
        // A stale window timer afterwards does nothing.
        XCTAssertEqual(controller.holdWindowElapsed(), [])
    }

    func testTriple_slowThirdTapIsDictationThenAnImmediateStop() {
        var active = false
        let controller = HotkeyGestureController(mode: .tapDoubleTripleToggle)
        controller.isCaptureActive = { active }
        _ = controller.triggerPressed(timestampMs: 1_000)
        _ = controller.triggerPressed(timestampMs: 1_150)
        XCTAssertEqual(controller.holdWindowElapsed(), [.startCapture(.dictation)])
        active = true

        // The too-late third tap stops the dictation; it never becomes a meeting.
        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_700), [.stopCapture])
    }

    func testTriple_tapWhileCaptureActiveStopsWithoutWindowWait() {
        let controller = makeTriple(active: true)

        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_000), [.stopCapture])
        XCTAssertEqual(controller.holdWindowElapsed(), [])
        // Every tap while active is a stop; taps never accumulate into a gesture.
        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_100), [.stopCapture])
    }

    func testTriple_defaultProviderTreatsNothingAsActive() {
        let controller = HotkeyGestureController(mode: .tapDoubleTripleToggle)
        XCTAssertEqual(controller.triggerPressed(timestampMs: 1_000), [.scheduleHoldWindow(milliseconds: window)])
    }

    func testTriple_strayKeyAndReleaseBetweenTapsDoNotCancelTheGesture() {
        let controller = makeTriple()
        _ = controller.triggerPressed(timestampMs: 1_000)

        XCTAssertEqual(controller.triggerReleased(timestampMs: 1_010), [])
        XCTAssertEqual(controller.nonBareTriggerReleased(), [])
        XCTAssertEqual(controller.interrupted(), [])

        _ = controller.triggerPressed(timestampMs: 1_150)
        XCTAssertEqual(controller.interrupted(), [])
        XCTAssertEqual(controller.holdWindowElapsed(), [.startCapture(.dictation)])
    }

    func testTriple_escapeCancelsAPendingGestureAtEitherStage() {
        let controller = makeTriple()
        _ = controller.triggerPressed(timestampMs: 1_000)
        XCTAssertEqual(controller.escapePressed(), [.cancelHoldWindow])
        XCTAssertEqual(controller.holdWindowElapsed(), [])

        _ = controller.triggerPressed(timestampMs: 2_000)
        _ = controller.triggerPressed(timestampMs: 2_150)
        XCTAssertEqual(controller.escapePressed(), [.cancelHoldWindow])
        XCTAssertEqual(controller.holdWindowElapsed(), [])

        // Escape with no gesture pending goes to the app as a cancel: it cancels a
        // running dictation (3-2-1 undo countdown) and is ignored by recordings.
        XCTAssertEqual(controller.escapePressed(), [.cancelRecording])
    }

    func testTriple_resetAndSuppressClearAPendingGesture() {
        let controller = makeTriple()
        _ = controller.triggerPressed(timestampMs: 1_000)
        controller.reset()
        XCTAssertEqual(controller.holdWindowElapsed(), [])

        _ = controller.triggerPressed(timestampMs: 2_000)
        controller.suppressUntilReset()
        XCTAssertEqual(controller.holdWindowElapsed(), [])
        XCTAssertEqual(controller.triggerPressed(timestampMs: 2_100), [])

        controller.reset()
        XCTAssertEqual(controller.triggerPressed(timestampMs: 3_000), [.scheduleHoldWindow(milliseconds: window)])
    }
}

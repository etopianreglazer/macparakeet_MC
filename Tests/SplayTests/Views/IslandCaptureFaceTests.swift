import XCTest
import SplayCore
import SplayViewModels
@testable import Splay

/// The island shows three captures on one pill: fn tap (mic recording),
/// triple-tap (meeting: mic + system) and double-tap (dictation). The meeting
/// flow drives the pill VM; dictation feeds `IslandDictationPhase`. These pure
/// mappings keep the drawn face and the click tracker in agreement.
final class IslandCaptureFaceTests: XCTestCase {
    typealias Pill = MeetingRecordingPillViewModel.PillState

    // MARK: Effective state

    func testMeetingFlowWinsWheneverItIsNotIdle() {
        for pill: Pill in [.recording, .paused, .transcribing, .completed, .error("x")] {
            XCTAssertEqual(IslandLayout.effectiveState(pill: pill, dictation: .recording), pill)
        }
    }

    func testDictationDrivesTheIdlePill() {
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: nil), .idle)
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: .recording), .recording)
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: .transcribing), .transcribing)
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: .pasted), .completed)
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: .copied), .completed)
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: .cancelling(secondsLeft: 3)), .completed)
        if case .error = IslandLayout.effectiveState(pill: .idle, dictation: .failed) {} else {
            XCTFail("a failed dictation shows the failed face")
        }
    }

    func testCaptureKind() {
        XCTAssertEqual(IslandLayout.captureKind(pill: .recording, dictation: nil, meetingCapturesSystem: false), .recording)
        XCTAssertEqual(IslandLayout.captureKind(pill: .recording, dictation: nil, meetingCapturesSystem: true), .meeting)
        XCTAssertEqual(IslandLayout.captureKind(pill: .idle, dictation: .recording, meetingCapturesSystem: true), .dictation)
    }

    // MARK: Dictation flow → island phase

    func testDictationPhaseFromFlowState() {
        let rec: [DictationFlowState] = [
            .checkingEntitlements(mode: .persistent), .startingService(mode: .persistent),
            .recording(mode: .persistent), .pendingStop(mode: .persistent),
        ]
        for s in rec { XCTAssertEqual(DictationFlowCoordinator.islandPhase(for: s), .recording, "\(s)") }
        XCTAssertEqual(DictationFlowCoordinator.islandPhase(for: .processing), .transcribing)
        XCTAssertEqual(DictationFlowCoordinator.islandPhase(for: .finishing(outcome: .success)), .pasted)
        XCTAssertEqual(DictationFlowCoordinator.islandPhase(for: .finishing(outcome: .pasteFailedCopied("x"))), .copied)
        XCTAssertEqual(DictationFlowCoordinator.islandPhase(for: .finishing(outcome: .noSpeech)), .failed)
        XCTAssertEqual(DictationFlowCoordinator.islandPhase(for: .finishing(outcome: .error("x"))), .failed)
        XCTAssertEqual(DictationFlowCoordinator.islandPhase(for: .cancelCountdown, cancelSecondsLeft: 2),
                       .cancelling(secondsLeft: 2))
        for s: DictationFlowState in [.idle, .ready] {
            XCTAssertNil(DictationFlowCoordinator.islandPhase(for: s), "\(s)")
        }
    }

    // MARK: Geometry (owner, 2026-09-27): bars left; timer right; dictation has no right side

    func testCancelCountdownIsAOneGlyphFace() {
        for notch in [false, true] {
            XCTAssertEqual(SplayGeometry.layout(for: .cancelling, kind: .dictation, notchAttached: notch).size,
                           SplayGeometry.layout(for: .copied, kind: .dictation, notchAttached: notch).size)
        }
    }

    func testDictationIsTheShortestAndAMeetingTheLongest() {
        for notch in [false, true] {
            let dictation = SplayGeometry.layout(for: .recording, kind: .dictation, notchAttached: notch).size.width
            let recording = SplayGeometry.layout(for: .recording, kind: .recording, notchAttached: notch).size.width
            let meeting = SplayGeometry.layout(for: .recording, kind: .meeting, notchAttached: notch).size.width
            XCTAssertLessThan(dictation, recording)
            XCTAssertLessThan(recording, meeting)
        }
    }

    func testTimerSitsRightOfTheCameraAndDictationHasOnlyAnEar() {
        XCTAssertEqual(SplayGeometry.rightContentWidth(for: .recording, kind: .recording), SplayGeometry.timerWidth)
        XCTAssertEqual(SplayGeometry.rightContentWidth(for: .recording, kind: .meeting), SplayGeometry.timerWidth)
        XCTAssertEqual(SplayGeometry.rightContentWidth(for: .recording, kind: .dictation), 0)
    }

    func testOnTheNotchNothingRunsUnderTheCamera() {
        let cameraHalf = SplayGeometry.cameraDeadZone.width / 2
        for kind in [IslandCaptureKind.recording, .meeting, .dictation] {
            for state in [SplayIslandState.recording, .transcribing, .done, .failed] {
                let layout = SplayGeometry.layout(for: state, kind: kind, notchAttached: true)
                let left = -layout.size.width / 2 + layout.centerOffset
                let right = layout.size.width / 2 + layout.centerOffset
                let leftContent = SplayGeometry.leftContentWidth(for: state, kind: kind)
                let rightContent = SplayGeometry.rightContentWidth(for: state, kind: kind)
                XCTAssertLessThanOrEqual(left + SplayGeometry.contentInset + leftContent, -cameraHalf, "\(state) \(kind)")
                if rightContent > 0 {
                    XCTAssertGreaterThanOrEqual(right - SplayGeometry.contentInset - rightContent, cameraHalf, "\(state) \(kind)")
                } else {
                    XCTAssertEqual(right, cameraHalf + SplayGeometry.trailingEar, accuracy: 0.001, "\(state) \(kind)")
                }
            }
        }
    }

    func testOffTheNotchThePillHugsItsContentCentred() {
        let layout = SplayGeometry.layout(for: .recording, kind: .dictation, notchAttached: false)
        XCTAssertEqual(layout.centerOffset, 0)
        XCTAssertEqual(
            layout.size.width,
            SplayGeometry.leftContentWidth(for: .recording, kind: .dictation) + 2 * SplayGeometry.contentInset
        )
    }

    func testTheHitRectFollowsTheDrawnPill() {
        let layout = SplayGeometry.layout(for: .recording, kind: .meeting, notchAttached: true)
        let rect = IslandLayout.pillRect(for: .recording, kind: .meeting, notchAttached: true)
        XCTAssertEqual(rect.width, layout.size.width)
        XCTAssertEqual(rect.midX, IslandLayout.panelWidth / 2 + layout.centerOffset, accuracy: 0.001)
    }
}

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
        for s: DictationFlowState in [.idle, .ready, .cancelCountdown] {
            XCTAssertNil(DictationFlowCoordinator.islandPhase(for: s), "\(s)")
        }
    }

    // MARK: Asymmetric geometry (owner, 2026-09-27)

    /// Everything lives left of the camera; the pill's length says what runs.
    func testLeftSideGrowsWithWhatIsRunning() {
        for notch in [false, true] {
            let dictation = SplayGeometry.layout(for: .recording, kind: .dictation, notchAttached: notch).size.width
            let recording = SplayGeometry.layout(for: .recording, kind: .recording, notchAttached: notch).size.width
            let meeting = SplayGeometry.layout(for: .recording, kind: .meeting, notchAttached: notch).size.width
            XCTAssertLessThan(dictation, recording)
            XCTAssertLessThan(recording, meeting)
        }
    }

    func testOnTheNotchContentClearsTheCameraAndTheRightSideIsJustAnEar() {
        for kind in [IslandCaptureKind.recording, .meeting, .dictation] {
            for state in [SplayIslandState.recording, .transcribing, .done, .failed] {
                let layout = SplayGeometry.layout(for: state, kind: kind, notchAttached: true)
                let w = layout.size.width
                // Pill edges relative to the camera's centre.
                let left = -w / 2 + layout.centerOffset
                let right = w / 2 + layout.centerOffset
                let cameraHalf = SplayGeometry.cameraDeadZone.width / 2
                let content = SplayGeometry.contentWidth(for: state, kind: kind)
                XCTAssertLessThanOrEqual(
                    left + SplayGeometry.contentInset + content, -cameraHalf,
                    "\(state) \(kind): content must end before the camera"
                )
                XCTAssertEqual(right, cameraHalf + SplayGeometry.trailingEar, accuracy: 0.001)
            }
        }
    }

    func testOffTheNotchThePillHugsItsContentCentred() {
        let layout = SplayGeometry.layout(for: .recording, kind: .dictation, notchAttached: false)
        XCTAssertEqual(layout.centerOffset, 0)
        XCTAssertEqual(
            layout.size.width,
            SplayGeometry.contentWidth(for: .recording, kind: .dictation) + 2 * SplayGeometry.contentInset
        )
    }

    func testTheHitRectFollowsTheDrawnPill() {
        let layout = SplayGeometry.layout(for: .recording, kind: .meeting, notchAttached: true)
        let rect = IslandLayout.pillRect(for: .recording, kind: .meeting, notchAttached: true)
        XCTAssertEqual(rect.width, layout.size.width)
        XCTAssertEqual(rect.midX, IslandLayout.panelWidth / 2 + layout.centerOffset, accuracy: 0.001)
    }
}

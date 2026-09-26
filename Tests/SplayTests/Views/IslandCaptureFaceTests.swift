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

    // MARK: Width

    func testActiveWidthIsNarrowOffTheNotchAndClearsTheCameraOnIt() {
        XCTAssertEqual(SplayGeometry.size(for: .recording, notchAttached: false).width, 250)
        let notched = SplayGeometry.size(for: .recording, notchAttached: true).width
        // Each side of the camera dead zone must fit the widest slot content
        // (timer up to 99:59, or the meeting's twin meter) inside the face padding.
        let side = (notched - SplayGeometry.cameraDeadZone.width) / 2 - SplayGeometry.facePadding
        XCTAssertGreaterThanOrEqual(side, SplayGeometry.widestSlotContent)
        XCTAssertEqual(IslandLayout.pillSize(for: .recording, notchAttached: true).width, notched)
    }
}

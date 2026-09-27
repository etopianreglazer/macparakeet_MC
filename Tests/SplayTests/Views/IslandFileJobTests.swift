import XCTest
@testable import Splay
@testable import SplayViewModels

/// The island shows a file transcription with the faces a recording ends
/// with, and never over a live capture. See
/// docs/plans/file-transcription-feedback.md.
@MainActor
final class IslandFileJobTests: XCTestCase {

    // MARK: - Precedence

    func testFileJobShowsWhenNothingElseRuns() {
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: nil, fileJob: .transcribing), .transcribing)
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: nil, fileJob: .done), .completed)
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: nil, fileJob: .failed), .error("file"))
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: nil, fileJob: nil), .idle)
    }

    func testLiveCapturesOutrankAFileJob() {
        XCTAssertEqual(IslandLayout.effectiveState(pill: .recording, dictation: nil, fileJob: .transcribing), .recording)
        XCTAssertEqual(IslandLayout.effectiveState(pill: .idle, dictation: .recording, fileJob: .done), .recording)
    }

    // MARK: - Presenter

    private final class Harness {
        var phases: [IslandFileJobPhase?] = []
        var pending: [(TimeInterval, @MainActor () -> Void)] = []
    }

    private func makePresenter(_ h: Harness) -> FileJobIslandPresenter {
        FileJobIslandPresenter(
            setPhase: { h.phases.append($0) },
            schedule: { delay, work in h.pending.append((delay, work)) }
        )
    }

    func testSuccessShowsSpinnerThenCheckThenClears() {
        let h = Harness()
        let p = makePresenter(h)
        p.activeChanged(true)
        p.activeChanged(false)
        p.finished(.transcribed(fileName: "a", wordCount: 1, savedTo: nil, saveFailed: false))
        XCTAssertEqual(h.phases, [.transcribing, nil, .done])
        XCTAssertEqual(h.pending.first?.0, FileJobIslandPresenter.doneSeconds)
        h.pending.removeFirst().1()
        XCTAssertEqual(h.phases.last, .some(nil))
    }

    func testFailureAndUnsavedShowTheFailureLight() {
        let h = Harness()
        let p = makePresenter(h)
        p.finished(.failed(fileName: "a", reason: "x"))
        XCTAssertEqual(h.phases.last, .failed)
        XCTAssertEqual(h.pending.last?.0, FileJobIslandPresenter.failedSeconds)
        p.finished(.transcribed(fileName: "a", wordCount: 1, savedTo: nil, saveFailed: true))
        XCTAssertEqual(h.phases.last, .failed)
    }

    func testCancelClearsAtOnce() {
        let h = Harness()
        let p = makePresenter(h)
        p.activeChanged(true)
        p.finished(.cancelled)
        XCTAssertEqual(h.phases, [.transcribing, nil])
        XCTAssertTrue(h.pending.isEmpty)
    }

    func testStaleHoldNeverClearsANewJob() {
        let h = Harness()
        let p = makePresenter(h)
        p.finished(.batch(completed: 2, failed: 0, unsaved: 0, folder: nil))
        p.activeChanged(true) // a new job starts during the check's hold
        h.pending.removeFirst().1()
        XCTAssertEqual(h.phases.last, .transcribing)
    }
}

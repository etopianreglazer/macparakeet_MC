import XCTest
@testable import Splay

/// The Transcribe File menu item says what runs and how far while a file job
/// runs (it is disabled then). See docs/plans/file-transcription-feedback.md.
@MainActor
final class MenuBarFileJobTests: XCTestCase {
    private func title(active: Bool = true, name: String = "talk.m4a", fraction: Double? = nil,
                       current: Int = 1, total: Int = 0) -> String {
        MenuBarCoordinator.transcribeFileItemTitle(
            active: active, fileName: name, fraction: fraction, batchCurrent: current, batchTotal: total
        )
    }

    func testIdleTitle() {
        XCTAssertEqual(title(active: false), "Transcribe File\u{2026}")
    }

    func testSingleFileShowsNameAndPercent() {
        XCTAssertEqual(title(), "Transcribing talk.m4a\u{2026}")
        XCTAssertEqual(title(fraction: 0.416), "Transcribing talk.m4a\u{2026} 42%")
        XCTAssertEqual(title(fraction: 1.3), "Transcribing talk.m4a\u{2026} 100%")
    }

    func testBatchShowsPosition() {
        XCTAssertEqual(title(current: 2, total: 5), "Transcribing 2 of 5\u{2026}")
        XCTAssertEqual(title(current: 6, total: 5), "Transcribing 5 of 5\u{2026}", "Never past the total")
    }

    func testLongNamesAreMiddleTruncated() {
        let long = "2026-09-27 quarterly planning meeting recording.m4a"
        let short = MenuBarCoordinator.middleTruncated(long, limit: 28)
        XCTAssertEqual(short.count, 28)
        XCTAssertTrue(short.hasPrefix("2026-09-27"))
        XCTAssertTrue(short.hasSuffix("recording.m4a"))
    }

    func testOpenPanelSaysWhereTranscriptsGo() {
        let folder = URL(fileURLWithPath: NSHomeDirectory() + "/Documents/MacParakeet-MC/Transcriptions")
        XCTAssertTrue(MenuBarCoordinator.openPanelMessage(folder: folder)
            .hasSuffix("Transcripts are saved to ~/Documents/MacParakeet-MC/Transcriptions."))
        XCTAssertFalse(MenuBarCoordinator.openPanelMessage(folder: nil).contains("saved to"))
    }
}

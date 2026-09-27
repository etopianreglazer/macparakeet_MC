import XCTest
@testable import SplayViewModels

/// Splay's file-job banner copy. See docs/plans/file-transcription-feedback.md.
final class TranscriptionCompletionNotifierTests: XCTestCase {
    private typealias N = TranscriptionCompletionNotifier
    private let folder = URL(fileURLWithPath: "/Users/x/Documents/MacParakeet-MC/Transcriptions")

    // MARK: - One file

    func testSavedFileSaysWhereAndRevealsIt() {
        let url = folder.appendingPathComponent("talk.md")
        let content = N.content(
            for: .transcribed(fileName: "talk.m4a", wordCount: 120, savedTo: url, saveFailed: false),
            settingEnabled: true
        )
        XCTAssertEqual(content?.title, "Transcribed talk.m4a")
        XCTAssertEqual(content?.body, "Saved to Transcriptions \u{00B7} 120 words")
        XCTAssertEqual(content?.revealURL, url)
    }

    func testAutoSaveOffPointsAtRecordings() {
        let content = N.content(
            for: .transcribed(fileName: "talk.m4a", wordCount: 1, savedTo: nil, saveFailed: false),
            settingEnabled: true
        )
        XCTAssertEqual(content?.body, "In Splay's Recordings \u{00B7} 1 word")
        XCTAssertNil(content?.revealURL)
    }

    func testUnsavedFileSaysSo() {
        let content = N.content(
            for: .transcribed(fileName: "talk.m4a", wordCount: 5, savedTo: nil, saveFailed: true),
            settingEnabled: true
        )
        XCTAssertEqual(content?.title, "Transcribed talk.m4a, but not saved")
    }

    func testFailureCarriesTheReason() {
        let content = N.content(for: .failed(fileName: "x.mov", reason: "Unsupported codec"), settingEnabled: true)
        XCTAssertEqual(content?.title, "Couldn't transcribe x.mov")
        XCTAssertEqual(content?.body, "Unsupported codec")
    }

    // MARK: - The setting silences successes only

    func testSettingOffSilencesSuccessesNotProblems() {
        XCTAssertNil(N.content(
            for: .transcribed(fileName: "x", wordCount: 1, savedTo: nil, saveFailed: false), settingEnabled: false))
        XCTAssertNil(N.content(
            for: .batch(completed: 3, failed: 0, unsaved: 0, folder: folder), settingEnabled: false))
        XCTAssertNotNil(N.content(for: .failed(fileName: "x", reason: "bad"), settingEnabled: false))
        XCTAssertNotNil(N.content(
            for: .transcribed(fileName: "x", wordCount: 1, savedTo: nil, saveFailed: true), settingEnabled: false))
        XCTAssertNotNil(N.content(
            for: .batch(completed: 2, failed: 1, unsaved: 0, folder: folder), settingEnabled: false))
        XCTAssertNotNil(N.content(
            for: .batch(completed: 2, failed: 0, unsaved: 2, folder: nil), settingEnabled: false))
    }

    func testCancelNeedsNoBanner() {
        XCTAssertNil(N.content(for: .cancelled, settingEnabled: true))
    }

    // MARK: - Batch

    func testCleanBatch() {
        let content = N.content(for: .batch(completed: 3, failed: 0, unsaved: 0, folder: folder), settingEnabled: true)
        XCTAssertEqual(content?.title, "Transcribed 3 files")
        XCTAssertEqual(content?.body, "Saved to Transcriptions \u{00B7} 3 transcribed")
        XCTAssertEqual(content?.revealURL, folder)
        XCTAssertEqual(N.batchTitle(completed: 1, failed: 0, unsaved: 0), "Transcribed 1 file")
    }

    func testBatchWithFailures() {
        let content = N.content(for: .batch(completed: 2, failed: 1, unsaved: 0, folder: folder), settingEnabled: true)
        XCTAssertEqual(content?.title, "Transcribed 2 of 3 files")
        XCTAssertEqual(content?.body, "Saved to Transcriptions \u{00B7} 2 transcribed \u{00B7} 1 failed")
    }

    func testBatchThatAllFailed() {
        XCTAssertEqual(N.batchTitle(completed: 0, failed: 3, unsaved: 0), "Couldn't transcribe 3 files")
    }

    func testBatchNothingSaved() {
        let content = N.content(for: .batch(completed: 3, failed: 0, unsaved: 3, folder: nil), settingEnabled: true)
        XCTAssertEqual(content?.title, "Transcribed 3 files, 3 not saved")
        XCTAssertTrue(content?.body.contains("Couldn't write to your transcripts folder") == true)
        XCTAssertNil(content?.revealURL)
    }

    // MARK: - isFailure (drives the island's failure light; matches the titles)

    func testIsFailure() {
        XCTAssertFalse(FileJobOutcome.transcribed(fileName: "x", wordCount: 1, savedTo: nil, saveFailed: false).isFailure)
        XCTAssertTrue(FileJobOutcome.transcribed(fileName: "x", wordCount: 1, savedTo: nil, saveFailed: true).isFailure)
        XCTAssertTrue(FileJobOutcome.failed(fileName: "x", reason: "r").isFailure)
        XCTAssertFalse(FileJobOutcome.cancelled.isFailure)
        XCTAssertFalse(FileJobOutcome.batch(completed: 3, failed: 0, unsaved: 0, folder: nil).isFailure)
        XCTAssertTrue(FileJobOutcome.batch(completed: 2, failed: 1, unsaved: 0, folder: nil).isFailure)
        XCTAssertTrue(FileJobOutcome.batch(completed: 3, failed: 0, unsaved: 1, folder: nil).isFailure)
        XCTAssertTrue(FileJobOutcome.batch(completed: 0, failed: 0, unsaved: 0, folder: nil).isFailure)
    }

    // MARK: - Busy

    func testBusyNamesTheRunningFile() {
        XCTAssertEqual(N.busyContent(runningFileName: "talk.m4a").body,
                       "Wait for talk.m4a to finish, or cancel it from the Splay menu.")
        XCTAssertEqual(N.busyContent(runningFileName: "").body,
                       "Wait for the current file to finish, or cancel it from the Splay menu.")
    }
}

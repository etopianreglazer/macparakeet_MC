import XCTest
@testable import Splay
@testable import SplayCore

/// The card's Recordings list shows recordings and fn dictations together,
/// newest first, so a dictation that pasted into the wrong place is one click away.
final class SplayRecordingRowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRecentsInterleaveRecordingsAndDictationsNewestFirst() {
        let recording = Transcription(createdAt: now.addingTimeInterval(-300), fileName: "Standup.m4a",
                                      durationMs: 60_000, rawTranscript: "meeting words", status: .completed)
        let dictation = Dictation(createdAt: now.addingTimeInterval(-60), durationMs: 12_000,
                                  rawTranscript: "dictated words", status: .completed)
        let older = Dictation(createdAt: now.addingTimeInterval(-900), durationMs: 5_000,
                              rawTranscript: "older words", status: .completed)

        let rows = SplayRecordingRow.recents(transcriptions: [recording], dictations: [dictation, older],
                                             limit: 5, now: now)

        XCTAssertEqual(rows.map(\.transcript), ["dictated words", "meeting words", "older words"])
        XCTAssertEqual(rows.map(\.isDictation), [true, false, true])
    }

    func testRecentsRespectTheLimit() {
        let dictations = (0..<8).map {
            Dictation(createdAt: now.addingTimeInterval(TimeInterval(-$0 * 60)), durationMs: 1_000,
                      rawTranscript: "d\($0)", status: .completed)
        }
        let rows = SplayRecordingRow.recents(transcriptions: [], dictations: dictations, limit: 5, now: now)
        XCTAssertEqual(rows.map(\.transcript), ["d0", "d1", "d2", "d3", "d4"])
    }

    func testDictationRowIsTitledByItsTextAndCopiesItVerbatim() {
        let d = Dictation(createdAt: now, durationMs: 83_000,
                          rawTranscript: "  Hello there,\nsecond line  ", status: .completed)
        let row = SplayRecordingRow.from(d, now: now)
        XCTAssertEqual(row.title, "Hello there, second line")
        XCTAssertEqual(row.transcript, "Hello there,\nsecond line")
        XCTAssertEqual(row.duration, "1:23")
    }

    func testFailedAndEmptyDictationsAreLeftOut() {
        let failed = Dictation(createdAt: now, durationMs: 1_000, rawTranscript: "x", status: .error)
        let empty = Dictation(createdAt: now, durationMs: 1_000, rawTranscript: "   ", status: .completed)
        XCTAssertTrue(SplayRecordingRow.recents(transcriptions: [], dictations: [failed, empty],
                                                limit: 5, now: now).isEmpty)
    }
}

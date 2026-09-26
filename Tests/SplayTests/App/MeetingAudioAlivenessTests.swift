import Foundation
import XCTest
@testable import Splay
@testable import SplayCore

/// The island's amber light: dead ≠ silent.
@MainActor
final class MeetingAudioAlivenessTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func alive(_ health: MeetingCaptureHealth, recording: Bool = true, at seconds: TimeInterval) -> Bool {
        MeetingRecordingFlowCoordinator.isAudioAlive(
            health,
            isActivelyRecording: recording,
            now: start.addingTimeInterval(seconds)
        )
    }

    func testFreshWritesAreAlive() {
        let health = MeetingCaptureHealth(mode: .full, startedAt: start, lastSuccessfulWriteAt: start.addingTimeInterval(9.5))
        XCTAssertTrue(alive(health, at: 10))
    }

    func testStaleWritesAfterStartupGraceAreDead() {
        let health = MeetingCaptureHealth(mode: .full, startedAt: start, lastSuccessfulWriteAt: start.addingTimeInterval(5))
        XCTAssertFalse(alive(health, at: 10))
    }

    func testDeadMicInMicAndSystemRecordingIsDeadDespiteFreshSystemWrites() {
        let health = MeetingCaptureHealth(
            mode: .full,
            startedAt: start,
            lastSuccessfulWriteAt: start.addingTimeInterval(9.9),
            microphoneInterrupted: true
        )
        XCTAssertFalse(alive(health, at: 10))
    }

    func testNotActivelyRecordingIsAlwaysAlive() {
        let health = MeetingCaptureHealth(mode: .full, startedAt: start, microphoneInterrupted: true)
        XCTAssertTrue(alive(health, recording: false, at: 10))
    }
}

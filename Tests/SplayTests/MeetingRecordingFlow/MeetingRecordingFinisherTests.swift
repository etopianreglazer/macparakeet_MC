import XCTest
@testable import SplayCore

/// The finish order for a stopped recording: transcribe → write the file →
/// delete the recovery lock. Green must mean "the .md is on disk", and Retry
/// must never duplicate the database row.
@MainActor
final class MeetingRecordingFinisherTests: XCTestCase {
    private var service: FinisherMockRecordingService!
    private var transcriber: FinisherMockTranscriptionService!
    private var repo: MockTranscriptionRepository!
    private var events: FinisherEventLog!
    private var saveError: Error?

    override func setUp() async throws {
        events = FinisherEventLog()
        service = FinisherMockRecordingService(events: events)
        transcriber = FinisherMockTranscriptionService(events: events)
        repo = MockTranscriptionRepository()
        saveError = nil
    }

    private func makeFinisher() -> MeetingRecordingFinisher {
        MeetingRecordingFinisher(
            meetingRecordingService: service,
            transcriptionService: transcriber,
            transcriptionRepo: repo,
            saveTranscriptFile: { [events, weak self] _ in
                events!.append("save")
                if let error = self?.saveError { throw error }
            }
        )
    }

    func testSuccessWritesTheFileBeforeDeletingTheLock() async {
        let outcome = await makeFinisher().finish(.transcribe(Self.recording), isRetry: false)

        guard case .completed = outcome else { return XCTFail("expected completion, got \(outcome)") }
        XCTAssertEqual(events.entries, ["transcribe", "save", "complete"])
    }

    func testTranscriptionFailureKeepsTheLockAndRetriesTranscription() async {
        transcriber.transcribeError = FinisherTestError.boom

        let outcome = await makeFinisher().finish(.transcribe(Self.recording), isRetry: false)

        guard case .failed(_, .transcribe, .transcription) = outcome else {
            return XCTFail("expected a transcription failure with .transcribe retry, got \(outcome)")
        }
        XCTAssertEqual(events.entries, ["transcribe", "finishAttempt"], "no lock delete, no file write")
    }

    func testFileWriteFailureKeepsTheLockAndRetriesOnlyTheWrite() async {
        saveError = FinisherTestError.boom

        let outcome = await makeFinisher().finish(.transcribe(Self.recording), isRetry: false)

        guard case .failed(let error, .save, .fileWrite) = outcome else {
            return XCTFail("expected a file-write failure with .save retry, got \(outcome)")
        }
        XCTAssertTrue(error is TranscriptFileWriteError)
        XCTAssertEqual(events.entries, ["transcribe", "save", "finishAttempt"], "the lock stays")
    }

    func testSaveRetryDoesNotTranscribeAgain() async {
        let transcription = Transcription(fileName: "Meeting", status: .completed, sourceType: .meeting)

        let outcome = await makeFinisher().finish(.save(transcription, Self.recording), isRetry: true)

        guard case .completed = outcome else { return XCTFail("expected completion, got \(outcome)") }
        XCTAssertEqual(events.entries, ["save", "complete"])
    }

    func testTranscribeRetryReusesTheFailedRow() async {
        let failed = Transcription(
            fileName: "Meeting",
            filePath: Self.recording.mixedAudioURL.path,
            status: .error,
            sourceType: .meeting
        )
        repo.transcriptions = [failed]

        let outcome = await makeFinisher().finish(.transcribe(Self.recording), isRetry: true)

        guard case .completed = outcome else { return XCTFail("expected completion, got \(outcome)") }
        XCTAssertEqual(events.entries, ["retranscribe:\(failed.id)", "save", "complete"])
    }

    func testFirstAttemptNeverReusesAnOldRow() async {
        repo.transcriptions = [
            Transcription(fileName: "Meeting", filePath: Self.recording.mixedAudioURL.path, status: .error, sourceType: .meeting)
        ]

        _ = await makeFinisher().finish(.transcribe(Self.recording), isRetry: false)

        XCTAssertEqual(events.entries.first, "transcribe")
    }

    private static let recording: MeetingRecordingOutput = {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("finisher-\(UUID())")
        return MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Meeting",
            folderURL: folder,
            mixedAudioURL: folder.appendingPathComponent("meeting.m4a"),
            microphoneAudioURL: folder.appendingPathComponent("microphone.m4a"),
            systemAudioURL: folder.appendingPathComponent("system.m4a"),
            durationSeconds: 5,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 0, sampleRate: 48_000),
                system: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 0, sampleRate: 48_000)
            )
        )
    }()
}

private enum FinisherTestError: Error {
    case boom
}

private final class FinisherEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [String] = []
    var entries: [String] { lock.withLock { _entries } }
    func append(_ entry: String) { lock.withLock { _entries.append(entry) } }
}

private final class FinisherMockRecordingService: MeetingRecordingServiceProtocol, @unchecked Sendable {
    let events: FinisherEventLog
    init(events: FinisherEventLog) { self.events = events }

    func completeTranscription(for recording: MeetingRecordingOutput) async { events.append("complete") }
    func finishTranscriptionAttempt(for recording: MeetingRecordingOutput) async { events.append("finishAttempt") }

    func startRecording(title: String?, sourceMode: MeetingAudioSourceMode?) async throws { fatalError("Not used") }
    func stopRecording() async throws -> MeetingRecordingOutput { fatalError("Not used") }
    func cancelRecording() async {}
    func pauseRecording() async {}
    func resumeRecording() async {}
    func setMicrophoneMuted(_ muted: Bool) async -> MeetingMicrophoneMuteState {
        MeetingMicrophoneMuteState(isMuted: muted, canMute: true)
    }
    func updateNotes(_ notes: String) async {}
    var isRecording: Bool { false }
    var isPaused: Bool { false }
    var micLevel: Float { 0 }
    var systemLevel: Float { 0 }
    var elapsedSeconds: Int { 0 }
    var captureMode: CaptureMode { .full }
    var isMicrophoneMuted: Bool { false }
    var canMuteMicrophone: Bool { false }
    var microphoneMuteState: MeetingMicrophoneMuteState { MeetingMicrophoneMuteState(isMuted: false, canMute: false) }
    var transcriptUpdates: AsyncStream<MeetingTranscriptUpdate> { AsyncStream { $0.finish() } }
}

private final class FinisherMockTranscriptionService: TranscriptionServiceProtocol, @unchecked Sendable {
    let events: FinisherEventLog
    var transcribeError: Error?
    init(events: FinisherEventLog) { self.events = events }

    func transcribeMeeting(
        recording: MeetingRecordingOutput,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription {
        events.append("transcribe")
        if let transcribeError { throw transcribeError }
        return Transcription(fileName: recording.displayName, filePath: recording.mixedAudioURL.path, status: .completed, sourceType: .meeting)
    }

    /// The protocol requirement the finisher calls (the production service
    /// implements it by re-running the existing row, keeping its id).
    func retranscribeMeeting(
        existing transcription: Transcription,
        recording: MeetingRecordingOutput,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription {
        events.append("retranscribe:\(transcription.id)")
        var updated = transcription
        updated.status = .completed
        return updated
    }

    func transcribe(
        fileURL: URL,
        source: TelemetryTranscriptionSource,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription { fatalError("Not used") }

    func transcribeTransient(
        fileURL: URL,
        source: TelemetryTranscriptionSource,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription { fatalError("Not used") }

    func retranscribeMeeting(
        existing transcription: Transcription,
        recording: MeetingRecordingOutput,
        speechEngineOverride: SpeechEngineSelection?,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription { fatalError("Not used") }

    func retranscribe(
        existing transcription: Transcription,
        fileURL: URL,
        source: TelemetryTranscriptionSource,
        speechEngineOverride: SpeechEngineSelection?,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription { fatalError("Not used") }

    func transcribeURL(
        urlString: String,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription { fatalError("Not used") }

    func transcribeURLTransient(
        urlString: String,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription { fatalError("Not used") }
}

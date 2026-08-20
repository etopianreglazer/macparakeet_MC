import XCTest
@testable import SplayCore
import os

private final class TelemetrySpy: TelemetryServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [TelemetryEventSpec] = []

    func send(_ event: TelemetryEventSpec) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func sendAndFlush(_ event: TelemetryEventSpec) async -> Bool {
        send(event)
        return true
    }

    func flush() async {}

    func clearQueue() {
        lock.lock()
        events.removeAll()
        lock.unlock()
    }

    func flushForTermination() {}

    func snapshot() -> [TelemetryEventSpec] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private struct StubMediaMetadataExtractor: MediaMetadataExtracting {
    let metadata: MediaMetadata

    func metadata(for fileURL: URL) async -> MediaMetadata {
        metadata
    }
}

private actor NonRoutedSTTTranscriber: STTTranscribing {
    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult {
        STTResult(text: "default engine")
    }
}

private struct FailingEntitlements: EntitlementsChecking {
    let error: Error
    let state: EntitlementsState?

    init(error: Error, state: EntitlementsState? = nil) {
        self.error = error
        self.state = state
    }

    func assertCanTranscribe(now: Date) async throws {
        throw error
    }

    func currentState(now: Date) async -> EntitlementsState {
        state ?? Self.state(for: error, now: now)
    }

    private static func state(for error: Error, now: Date) -> EntitlementsState {
        switch error {
        case EntitlementsError.trialExpired:
            return EntitlementsState(access: .trialExpired(endedAt: now), licenseKeyMasked: nil, lastValidatedAt: nil)
        default:
            return EntitlementsState(access: .trialExpired(endedAt: now), licenseKeyMasked: nil, lastValidatedAt: nil)
        }
    }
}

final class TranscriptionServiceTests: XCTestCase {
    var service: TranscriptionService!
    var mockAudio: MockAudioProcessor!
    var mockSTT: MockSTTClient!
    var transcriptionRepo: TranscriptionRepository!
    var llmRunRepo: LLMRunRepository!

    override func setUp() async throws {
        let dbManager = try DatabaseManager()
        mockAudio = MockAudioProcessor()
        mockSTT = MockSTTClient()
        transcriptionRepo = TranscriptionRepository(dbQueue: dbManager.dbQueue)
        llmRunRepo = LLMRunRepository(dbQueue: dbManager.dbQueue)
        Telemetry.configure(NoOpTelemetryService())

        service = TranscriptionService(
            audioProcessor: mockAudio,
            sttTranscriber: mockSTT,
            transcriptionRepo: transcriptionRepo
        )
    }

    func testTranscribeFileSucceeds() async throws {
        let expectedResult = STTResult(
            text: "This is a transcription",
            words: [
                TimestampedWord(word: "This", startMs: 0, endMs: 200, confidence: 0.99),
                TimestampedWord(word: "is", startMs: 210, endMs: 350, confidence: 0.98),
                TimestampedWord(word: "a", startMs: 360, endMs: 400, confidence: 0.97),
                TimestampedWord(word: "transcription", startMs: 410, endMs: 1000, confidence: 0.96),
            ]
        )
        await mockSTT.configure(result: expectedResult)

        let fileURL = URL(fileURLWithPath: "/tmp/test.mp3")
        let result = try await service.transcribe(fileURL: fileURL)

        XCTAssertEqual(result.fileName, "test.mp3")
        XCTAssertEqual(result.rawTranscript, "This is a transcription")
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.wordTimestamps?.count, 4)
        XCTAssertEqual(result.durationMs, 1000)

        // Verify saved to DB
        let fetched = try transcriptionRepo.fetch(id: result.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.status, .completed)
    }

    func testTranscribeFilePersistsDetectedLanguage() async throws {
        let telemetry = TelemetrySpy()
        Telemetry.configure(telemetry)
        defer { Telemetry.configure(NoOpTelemetryService()) }

        await mockSTT.configure(result: STTResult(text: "hello world", language: "KO-kr"))

        let result = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/korean.mp3"))

        XCTAssertEqual(result.language, "ko")
        XCTAssertEqual(try transcriptionRepo.fetch(id: result.id)?.language, "ko")

        let completed = try XCTUnwrap(telemetry.snapshot().reversed().first {
            if case .transcriptionCompleted = $0 { return true }
            return false
        })
        let props = try telemetryProps(for: completed)
        XCTAssertEqual(props["language"], "ko")
    }

    func testTranscribeFilePersistsEngineAttributionFromSTTResult() async throws {
        let telemetry = TelemetrySpy()
        Telemetry.configure(telemetry)
        defer { Telemetry.configure(NoOpTelemetryService()) }

        await mockSTT.configure(result: STTResult(
            text: "hello world",
            engine: .whisper,
            engineVariant: SpeechEnginePreference.defaultWhisperModelVariant
        ))

        let result = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/whisper.mp3"))

        XCTAssertEqual(result.engine, "whisper")
        XCTAssertEqual(result.engineVariant, SpeechEnginePreference.defaultWhisperModelVariant)
        let fetched = try transcriptionRepo.fetch(id: result.id)
        XCTAssertEqual(fetched?.engine, "whisper")
        XCTAssertEqual(fetched?.engineVariant, SpeechEnginePreference.defaultWhisperModelVariant)

        let operation = telemetry.snapshot().reversed().first {
            if case .transcriptionOperation = $0 { return true }
            return false
        }
        let operationEvent = try XCTUnwrap(operation)
        let props = try XCTUnwrap(operationEvent.props)
        XCTAssertEqual(props["speech_engine"], "whisper")
        XCTAssertEqual(props["engine_variant"], SpeechEnginePreference.defaultWhisperModelVariant)
    }

    func testTranscribeTransientFileDoesNotPersistCompletedRow() async throws {
        await mockSTT.configure(result: STTResult(text: "private transcript"))

        let result = try await service.transcribeTransient(fileURL: URL(fileURLWithPath: "/tmp/private.mp3"))

        XCTAssertEqual(result.rawTranscript, "private transcript")
        XCTAssertEqual(result.status, .completed)
        XCTAssertNil(try transcriptionRepo.fetch(id: result.id))
        XCTAssertTrue(try transcriptionRepo.fetchAll(limit: nil).isEmpty)
    }

    func testTranscribeTransientFileDoesNotPersistLLMRun() async throws {
        await mockSTT.configure(result: STTResult(text: "private transcript"))
        let mockLLMService = MockLLMService()
        mockLLMService.formatTranscriptResult = "Private transcript."

        let service = TranscriptionService(
            audioProcessor: mockAudio,
            sttTranscriber: mockSTT,
            transcriptionRepo: transcriptionRepo,
            llmService: mockLLMService,
            llmRunRepo: llmRunRepo,
            shouldUseAIFormatter: { true },
            aiFormatterPromptTemplate: { AIFormatter.defaultPromptTemplate }
        )

        _ = try await service.transcribeTransient(fileURL: URL(fileURLWithPath: "/tmp/private.mp3"))

        XCTAssertEqual(mockLLMService.formatTranscriptCallCount, 1)
        XCTAssertEqual(try llmRunRepo.count(), 0)
    }

    func testTranscribeTransientFileDoesNotPersistFailureRow() async throws {
        await mockSTT.configure(error: STTError.transcriptionFailed("Model error"))

        do {
            _ = try await service.transcribeTransient(fileURL: URL(fileURLWithPath: "/tmp/private.mp3"))
            XCTFail("Expected transient transcription to throw")
        } catch let error as STTError {
            guard case .transcriptionFailed = error else {
                return XCTFail("Unexpected STT error: \(error)")
            }
        }

        XCTAssertTrue(try transcriptionRepo.fetchAll(limit: nil).isEmpty)
    }

    func testTranscribeFileDurationUsesMaximumWordEnd() async throws {
        await mockSTT.configure(result: STTResult(
            text: "out of order",
            words: [
                TimestampedWord(word: "later", startMs: 3000, endMs: 5000, confidence: 0.9),
                TimestampedWord(word: "earlier", startMs: 1000, endMs: 1500, confidence: 0.9),
            ]
        ))

        let result = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/out-of-order.mp3"))

        XCTAssertEqual(result.durationMs, 5000)
        XCTAssertEqual(try transcriptionRepo.fetch(id: result.id)?.durationMs, 5000)
    }

    func testTranscribeFilePersistsEmbeddedMediaMetadataAndArtwork() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("downloaded.m4a")
        try Data("audio".utf8).write(to: fileURL)

        let artwork = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let thumbnailCache = ThumbnailCacheService(cacheDir: tempDir.appendingPathComponent("thumbs").path)
        let service = TranscriptionService(
            audioProcessor: mockAudio,
            sttTranscriber: mockSTT,
            transcriptionRepo: transcriptionRepo,
            mediaMetadataExtractor: StubMediaMetadataExtractor(metadata: MediaMetadata(
                title: "Episode Title",
                author: "Show Host",
                description: "Episode notes",
                artworkData: artwork,
                durationMs: 12_000
            )),
            thumbnailCache: thumbnailCache
        )
        await mockSTT.configure(result: STTResult(
            text: "short transcript",
            words: [
                TimestampedWord(word: "short", startMs: 0, endMs: 900, confidence: 0.95),
            ]
        ))

        let result = try await service.transcribe(fileURL: fileURL)
        let fetched = try XCTUnwrap(transcriptionRepo.fetch(id: result.id))
        let cachedThumbnail = try XCTUnwrap(thumbnailCache.cachedThumbnail(for: result.id))

        XCTAssertEqual(result.fileName, "Episode Title")
        XCTAssertEqual(result.channelName, "Show Host")
        XCTAssertEqual(result.videoDescription, "Episode notes")
        XCTAssertEqual(result.durationMs, 12_000)
        XCTAssertEqual(fetched.fileName, "Episode Title")
        XCTAssertEqual(fetched.channelName, "Show Host")
        XCTAssertEqual(fetched.videoDescription, "Episode notes")
        XCTAssertEqual(fetched.durationMs, 12_000)
        XCTAssertEqual(try Data(contentsOf: cachedThumbnail), artwork)
    }

    func testTranscribeFileError() async throws {
        await mockSTT.configure(error: STTError.transcriptionFailed("Model error"))

        let fileURL = URL(fileURLWithPath: "/tmp/test.mp3")

        do {
            _ = try await service.transcribe(fileURL: fileURL)
            XCTFail("Should have thrown")
        } catch let error as STTError {
            if case .transcriptionFailed(let reason) = error {
                XCTAssertEqual(reason, "Model error")
            } else {
                XCTFail("Expected transcriptionFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        // Verify error saved to DB
        let all = try transcriptionRepo.fetchAll(limit: nil)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].status, .error)
    }

    func testTranscribeFileEntitlementFailureEmitsPreflightOperation() async throws {
        let telemetry = TelemetrySpy()
        Telemetry.configure(telemetry)
        defer { Telemetry.configure(NoOpTelemetryService()) }
        let service = TranscriptionService(
            audioProcessor: mockAudio,
            sttTranscriber: mockSTT,
            transcriptionRepo: transcriptionRepo,
            entitlements: FailingEntitlements(error: EntitlementsError.trialExpired)
        )

        do {
            _ = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/test.mp3"))
            XCTFail("Should have thrown")
        } catch EntitlementsError.trialExpired {
            // Expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        let operation = telemetry.snapshot().reversed().first {
            if case .transcriptionOperation = $0 { return true }
            return false
        }
        let event = TelemetryEvent(
            spec: try XCTUnwrap(operation),
            appVer: "test",
            osVer: "test",
            locale: "en-US",
            chip: "test",
            session: "test"
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let props = try XCTUnwrap(json["props"] as? [String: String])

        XCTAssertEqual(json["event"] as? String, "transcription_operation")
        XCTAssertEqual(props["outcome"], "unavailable")
        XCTAssertEqual(props["source"], "file")
        XCTAssertEqual(props["stage"], "preflight")
        XCTAssertEqual(props["error_type"], "EntitlementsError.trialExpired")
        XCTAssertNil(props["processing_seconds"])
    }

    func testTranscribeFileCancellationMarksRecordCancelled() async throws {
        await mockSTT.configure(error: CancellationError())

        let fileURL = URL(fileURLWithPath: "/tmp/test.mp3")

        do {
            _ = try await service.transcribe(fileURL: fileURL)
            XCTFail("Should have thrown")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        let all = try transcriptionRepo.fetchAll(limit: nil)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].status, .cancelled)
        XCTAssertNil(all[0].errorMessage)
    }

    func testConvertCalledBeforeSTT() async throws {
        let expectedResult = STTResult(text: "Hello")
        await mockSTT.configure(result: expectedResult)

        let fileURL = URL(fileURLWithPath: "/tmp/test.mp3")
        _ = try await service.transcribe(fileURL: fileURL)

        let convertCount = await mockAudio.convertCallCount
        XCTAssertEqual(convertCount, 1)

        let lastURL = await mockAudio.lastConvertURL
        XCTAssertEqual(lastURL?.path, "/tmp/test.mp3")
    }

    func testTranscribeAppliesAIFormatterAsFinalStep() async throws {
        await mockSTT.configure(result: STTResult(text: "hello world"))
        let mockLLMService = MockLLMService()
        mockLLMService.formatTranscriptResult = "Hello, world."
        mockLLMService.formatTranscriptProvider = "lmstudio"
        mockLLMService.formatTranscriptModel = "sotto-cleanup"
        mockLLMService.formatTranscriptUsage = LLMUsage(promptTokens: 10, completionTokens: 4, totalTokens: 14)
        mockLLMService.formatTranscriptStopReason = "stop"
        mockLLMService.formatTranscriptLatencyMs = 42

        let service = TranscriptionService(
            audioProcessor: mockAudio,
            sttTranscriber: mockSTT,
            transcriptionRepo: transcriptionRepo,
            llmService: mockLLMService,
            llmRunRepo: llmRunRepo,
            shouldUseAIFormatter: { true },
            aiFormatterPromptTemplate: { AIFormatter.defaultPromptTemplate }
        )

        let result = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/test.mp3"))

        XCTAssertEqual(result.rawTranscript, "hello world")
        XCTAssertEqual(result.cleanTranscript, "Hello, world.")
        XCTAssertEqual(mockLLMService.formatTranscriptCallCount, 1)
        XCTAssertEqual(mockLLMService.lastFormattedTranscript, "hello world")

        let runs = try llmRunRepo.fetchForTranscription(id: result.id)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.feature, .formatterTranscription)
        XCTAssertEqual(runs.first?.status, .succeeded)
        XCTAssertEqual(runs.first?.provider, "lmstudio")
        XCTAssertEqual(runs.first?.model, "sotto-cleanup")
        XCTAssertEqual(runs.first?.promptTokens, 10)
        XCTAssertEqual(runs.first?.completionTokens, 4)
        XCTAssertEqual(runs.first?.totalTokens, 14)
        XCTAssertEqual(runs.first?.latencyMs, 42)
        XCTAssertEqual(runs.first?.inputChars, "hello world".count)
        XCTAssertEqual(runs.first?.outputChars, "Hello, world.".count)
        XCTAssertEqual(runs.first?.stopReason, "stop")
        XCTAssertEqual(runs.first?.defaultPromptUsed, true)
        XCTAssertEqual(runs.first?.messageCount, 2)
    }

    func testTranscribeFallsBackWhenAIFormatterFailsAndPostsWarning() async throws {
        await mockSTT.configure(result: STTResult(text: "hello world"))
        let mockLLMService = MockLLMService()
        mockLLMService.errorToThrow = LLMError.formatterTruncated

        let warningPosted = expectation(description: "AI formatter warning posted")
        var warningMessage: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .macParakeetAIFormatterWarning,
            object: nil,
            queue: nil
        ) { notification in
            guard let source = notification.userInfo?["source"] as? String, source == "transcription" else { return }
            warningMessage = notification.userInfo?["message"] as? String
            warningPosted.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let service = TranscriptionService(
            audioProcessor: mockAudio,
            sttTranscriber: mockSTT,
            transcriptionRepo: transcriptionRepo,
            llmService: mockLLMService,
            llmRunRepo: llmRunRepo,
            shouldUseAIFormatter: { true },
            aiFormatterPromptTemplate: { AIFormatter.defaultPromptTemplate }
        )

        let result = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/test.mp3"))

        XCTAssertEqual(result.rawTranscript, "hello world")
        XCTAssertNil(result.cleanTranscript)
        XCTAssertEqual(mockLLMService.formatTranscriptCallCount, 1)
        await fulfillment(of: [warningPosted], timeout: 1.0)
        XCTAssertEqual(warningMessage, "AI formatter output was incomplete. Used standard cleanup.")

        let runs = try llmRunRepo.fetchForTranscription(id: result.id)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.feature, .formatterTranscription)
        XCTAssertEqual(runs.first?.status, .failed)
        XCTAssertEqual(runs.first?.inputChars, "hello world".count)
        XCTAssertEqual(runs.first?.outputChars, 0)
        XCTAssertNotNil(runs.first?.errorType)
    }

    func testTranscribePostsAuthenticationWarningWhenAIFormatterAuthFails() async throws {
        await mockSTT.configure(result: STTResult(text: "hello world"))
        let mockLLMService = MockLLMService()
        mockLLMService.errorToThrow = LLMError.authenticationFailed(nil)

        let warningPosted = expectation(description: "AI formatter auth warning posted")
        var warningMessage: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .macParakeetAIFormatterWarning,
            object: nil,
            queue: nil
        ) { notification in
            guard let source = notification.userInfo?["source"] as? String, source == "transcription" else { return }
            warningMessage = notification.userInfo?["message"] as? String
            warningPosted.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let service = TranscriptionService(
            audioProcessor: mockAudio,
            sttTranscriber: mockSTT,
            transcriptionRepo: transcriptionRepo,
            llmService: mockLLMService,
            shouldUseAIFormatter: { true },
            aiFormatterPromptTemplate: { AIFormatter.defaultPromptTemplate }
        )

        _ = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/test.mp3"))

        await fulfillment(of: [warningPosted], timeout: 1.0)
        XCTAssertEqual(warningMessage, "Authentication failed. Check your API key. Used standard cleanup.")
    }

    func testTranscribeMeetingUsesFinalizeLaneAndMergesFreshSourceTranscriptsByAlignment() async throws {
        let telemetry = TelemetrySpy()
        Telemetry.configure(telemetry)
        defer { Telemetry.configure(NoOpTelemetryService()) }
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        let systemURL = recordingFolder.appendingPathComponent("system.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: systemURL.path, contents: Data("system".utf8)))

        await mockSTT.configureSequence(results: [
            STTResult(
                text: "Hello there",
                words: [
                    TimestampedWord(word: "Hello", startMs: 50, endMs: 260, confidence: 0.9),
                    TimestampedWord(word: "there", startMs: 300, endMs: 540, confidence: 0.9),
                ]
            ),
            STTResult(
                text: "Sounds good",
                words: [
                    TimestampedWord(word: "Sounds", startMs: 20, endMs: 280, confidence: 0.9),
                    TimestampedWord(word: "good", startMs: 320, endMs: 560, confidence: 0.9),
                ]
            ),
        ])

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Meeting Demo",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: systemURL,
            durationSeconds: 1.5,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 900, writtenFrameCount: 24_000, sampleRate: 48_000)
            )
        )

        let result = try await service.transcribeMeeting(recording: recording)
        let sttCallCount = await mockSTT.transcribeCallCount
        let jobs = await mockSTT.jobs
        let convertCallCount = await mockAudio.convertCallCount
        let convertURLs = await mockAudio.convertURLs

        XCTAssertEqual(result.fileName, "Meeting Demo")
        XCTAssertEqual(result.filePath, mixedURL.path)
        XCTAssertEqual(result.rawTranscript, "Hello there Sounds good")
        XCTAssertEqual(result.speakerCount, 2)
        XCTAssertEqual(result.speakers, [
            SpeakerInfo(id: "microphone", label: "Me"),
            SpeakerInfo(id: "system", label: "Others"),
        ])
        XCTAssertEqual(result.diarizationSegments, [
            DiarizationSegmentRecord(speakerId: "microphone", startMs: 50, endMs: 540),
            DiarizationSegmentRecord(speakerId: "system", startMs: 920, endMs: 1460),
        ])
        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["microphone", "microphone", "system", "system"])
        XCTAssertEqual(result.wordTimestamps?.map(\.startMs), [50, 300, 920, 1220])
        XCTAssertEqual(sttCallCount, 2)
        XCTAssertEqual(jobs, [.meetingFinalize, .meetingFinalize])
        XCTAssertEqual(convertCallCount, 2)
        XCTAssertEqual(convertURLs, [microphoneURL, systemURL])

        let events = telemetry.snapshot()
        let completedEvent = events.reversed().first {
            if case .transcriptionCompleted = $0 { return true }
            return false
        }
        guard case .transcriptionCompleted(
            let source,
            _,
            _,
            _,
            let speakerCount,
            let diarizationRequested,
            let diarizationApplied,
            _,
            _,
            _
        ) = try XCTUnwrap(completedEvent) else {
            return XCTFail("Expected transcription_completed telemetry")
        }
        XCTAssertEqual(source, .meeting)
        XCTAssertEqual(speakerCount, 2)
        XCTAssertFalse(diarizationRequested)
        XCTAssertFalse(diarizationApplied)
    }

    func testTranscribeMeetingUsesCapturedSpeechEngineSelection() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))

        await mockSTT.configure(result: STTResult(
            text: "안녕하세요",
            words: [
                TimestampedWord(word: "안녕하세요", startMs: 0, endMs: 700, confidence: 0.9),
            ],
            language: "ko"
        ))

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Korean Meeting",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: recordingFolder.appendingPathComponent("system.m4a"),
            durationSeconds: 1.0,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: nil
            ),
            speechEngine: SpeechEngineSelection(engine: .whisper, language: "KO")
        )

        _ = try await service.transcribeMeeting(recording: recording)

        let selections = await mockSTT.speechEngineSelections
        XCTAssertEqual(selections, [SpeechEngineSelection(engine: .whisper, language: "ko")])
    }

    func testRetranscribeMeetingCanOverrideCapturedSpeechEngineForOneRun() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))

        await mockSTT.configure(result: STTResult(
            text: "Retried with Parakeet",
            words: [
                TimestampedWord(word: "Retried", startMs: 0, endMs: 400, confidence: 0.9),
            ],
            language: "en"
        ))

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Korean Meeting",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: recordingFolder.appendingPathComponent("system.m4a"),
            durationSeconds: 1.0,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: nil
            ),
            speechEngine: SpeechEngineSelection(engine: .whisper, language: "ko")
        )
        let original = Transcription(
            fileName: "Korean Meeting",
            filePath: mixedURL.path,
            status: .completed,
            sourceType: .meeting
        )

        _ = try await service.retranscribeMeeting(
            existing: original,
            recording: recording,
            speechEngineOverride: SpeechEngineSelection(engine: .parakeet)
        )

        let selections = await mockSTT.speechEngineSelections
        XCTAssertEqual(selections, [SpeechEngineSelection(engine: .parakeet)])
        XCTAssertEqual(recording.speechEngine, SpeechEngineSelection(engine: .whisper, language: "ko"))
    }

    func testRetranscribeMeetingWithoutCapturedSpeechEngineUsesCurrentRouting() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))

        await mockSTT.configure(result: STTResult(
            text: "Legacy rerun",
            words: [
                TimestampedWord(word: "Legacy", startMs: 0, endMs: 400, confidence: 0.9),
            ]
        ))

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Legacy Meeting",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: recordingFolder.appendingPathComponent("system.m4a"),
            durationSeconds: 1.0,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: nil
            ),
            speechEngine: SpeechEngineSelection(engine: .parakeet),
            speechEngineWasCaptured: false
        )
        let original = Transcription(
            fileName: "Legacy Meeting",
            filePath: mixedURL.path,
            status: .completed,
            sourceType: .meeting
        )

        _ = try await service.retranscribeMeeting(existing: original, recording: recording)

        let selections = await mockSTT.speechEngineSelections
        XCTAssertEqual(selections, [])
    }

    func testTranscribeMeetingFailsWhenCapturedSpeechEngineCannotBeRouted() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))

        let service = TranscriptionService(
            audioProcessor: mockAudio,
            sttTranscriber: NonRoutedSTTTranscriber(),
            transcriptionRepo: transcriptionRepo
        )
        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Korean Meeting",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: recordingFolder.appendingPathComponent("system.m4a"),
            durationSeconds: 1.0,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: nil
            ),
            speechEngine: SpeechEngineSelection(engine: .whisper, language: "ko")
        )

        do {
            _ = try await service.transcribeMeeting(recording: recording)
            XCTFail("Expected pinned speech engine routing to fail for a non-routed transcriber")
        } catch let error as STTError {
            guard case .engineStartFailed(let reason) = error else {
                return XCTFail("Unexpected STT error: \(error)")
            }
            XCTAssertTrue(reason.contains("Pinned whisper speech engine"))
        }
    }

    func testTranscribeMeetingAppliesOptionalSystemDiarizationAdditively() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        let systemURL = recordingFolder.appendingPathComponent("system.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: systemURL.path, contents: Data("system".utf8)))

        await mockSTT.configureSequence(results: [
            STTResult(
                text: "Hello",
                words: [
                    TimestampedWord(word: "Hello", startMs: 0, endMs: 240, confidence: 0.9),
                ]
            ),
            STTResult(
                text: "Sounds good",
                words: [
                    TimestampedWord(word: "Sounds", startMs: 0, endMs: 240, confidence: 0.9),
                    TimestampedWord(word: "good", startMs: 260, endMs: 520, confidence: 0.9),
                ]
            ),
        ])

        let diarization = MockDiarizationService()
        await diarization.configure(result: MacParakeetDiarizationResult(
            segments: [
                SpeakerSegment(speakerId: "S1", startMs: 0, endMs: 240),
                SpeakerSegment(speakerId: "S2", startMs: 260, endMs: 520),
            ],
            speakerCount: 2,
            speakers: [
                SpeakerInfo(id: "S1", label: "Speaker 1"),
                SpeakerInfo(id: "S2", label: "Speaker 2"),
            ]
        ))

        let service = TranscriptionService(
            audioProcessor: mockAudio,
            sttTranscriber: mockSTT,
            transcriptionRepo: transcriptionRepo,
            shouldDiarize: { true },
            diarizationService: diarization
        )

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Meeting Demo",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: systemURL,
            durationSeconds: 1.5,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 900, writtenFrameCount: 24_000, sampleRate: 48_000)
            )
        )

        let result = try await service.transcribeMeeting(recording: recording)
        let diarizeCalled = await diarization.diarizeCalled

        XCTAssertTrue(diarizeCalled)
        XCTAssertEqual(result.speakerCount, 3)
        XCTAssertEqual(result.speakers, [
            SpeakerInfo(id: "microphone", label: "Me"),
            SpeakerInfo(id: "system:S1", label: "Others 1"),
            SpeakerInfo(id: "system:S2", label: "Others 2"),
        ])
        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["microphone", "system:S1", "system:S2"])
        XCTAssertEqual(result.diarizationSegments, [
            DiarizationSegmentRecord(speakerId: "microphone", startMs: 0, endMs: 240),
            DiarizationSegmentRecord(speakerId: "system:S1", startMs: 900, endMs: 1140),
            DiarizationSegmentRecord(speakerId: "system:S2", startMs: 1160, endMs: 1420),
        ])
    }

    func testTranscribeMeetingPreservesOverlappingMicrophoneAndSystemSpeech() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        let systemURL = recordingFolder.appendingPathComponent("system.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: systemURL.path, contents: Data("system".utf8)))

        await mockSTT.configureSequence(results: [
            STTResult(
                text: "Can you hear me",
                words: [
                    TimestampedWord(word: "Can", startMs: 120, endMs: 220, confidence: 0.9),
                    TimestampedWord(word: "you", startMs: 240, endMs: 320, confidence: 0.9),
                    TimestampedWord(word: "hear", startMs: 340, endMs: 450, confidence: 0.9),
                    TimestampedWord(word: "me", startMs: 470, endMs: 540, confidence: 0.9),
                ]
            ),
            STTResult(
                text: "Can you hear me",
                words: [
                    TimestampedWord(word: "Can", startMs: 0, endMs: 100, confidence: 0.9),
                    TimestampedWord(word: "you", startMs: 120, endMs: 200, confidence: 0.9),
                    TimestampedWord(word: "hear", startMs: 220, endMs: 330, confidence: 0.9),
                    TimestampedWord(word: "me", startMs: 350, endMs: 420, confidence: 0.9),
                ]
            ),
        ])

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Meeting Demo",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: systemURL,
            durationSeconds: 1.5,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000)
            )
        )

        let result = try await service.transcribeMeeting(recording: recording)

        XCTAssertEqual(result.rawTranscript, "Can Can you hear you hear me me")
        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), [
            "system", "microphone", "system", "system", "microphone", "microphone", "system", "microphone",
        ])
        XCTAssertEqual(result.speakers, [
            SpeakerInfo(id: "microphone", label: "Me"),
            SpeakerInfo(id: "system", label: "Others"),
        ])
    }

    func testTranscribeMeetingKeepsFallbackSystemSpeakerWhenDiarizationDoesNotCoverEveryWord() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let systemURL = recordingFolder.appendingPathComponent("system.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: systemURL.path, contents: Data("system".utf8)))

        await mockSTT.configureSequence(results: [
            STTResult(
                text: "Hello there",
                words: [
                    TimestampedWord(word: "Hello", startMs: 0, endMs: 180, confidence: 0.9),
                    TimestampedWord(word: "there", startMs: 200, endMs: 360, confidence: 0.9),
                ]
            ),
        ])

        let diarization = MockDiarizationService()
        await diarization.configure(result: MacParakeetDiarizationResult(
            segments: [
                SpeakerSegment(speakerId: "S1", startMs: 0, endMs: 180),
            ],
            speakerCount: 1,
            speakers: [
                SpeakerInfo(id: "S1", label: "Speaker 1"),
            ]
        ))

        let service = TranscriptionService(
            audioProcessor: mockAudio,
            sttTranscriber: mockSTT,
            transcriptionRepo: transcriptionRepo,
            shouldDiarize: { true },
            diarizationService: diarization
        )

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Meeting Demo",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: recordingFolder.appendingPathComponent("microphone.m4a"),
            systemAudioURL: systemURL,
            durationSeconds: 1.0,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: nil,
                system: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000)
            )
        )

        let result = try await service.transcribeMeeting(recording: recording)

        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["system:S1", "system"])
        XCTAssertEqual(result.speakers, [
            SpeakerInfo(id: "system", label: "Others"),
            SpeakerInfo(id: "system:S1", label: "Others 1"),
        ])
    }

    func testTranscribeMeetingPreservesSingleSourceModelText() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))

        await mockSTT.configureSequence(results: [
            STTResult(
                text: "Hello, there.",
                words: [
                    TimestampedWord(word: "Hello", startMs: 0, endMs: 180, confidence: 0.9),
                    TimestampedWord(word: "there", startMs: 220, endMs: 420, confidence: 0.9),
                ]
            ),
        ])

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Meeting Demo",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: recordingFolder.appendingPathComponent("system.m4a"),
            durationSeconds: 1.0,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: nil
            )
        )

        let result = try await service.transcribeMeeting(recording: recording)

        XCTAssertEqual(result.rawTranscript, "Hello, there.")
        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["microphone", "microphone"])
    }

    func testTranscribeMeetingPreservesSingleSourceModelTextWithoutWordTimestamps() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))

        await mockSTT.configureSequence(results: [
            STTResult(
                text: "Hello, there.",
                words: []
            ),
        ])

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Meeting Demo",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: recordingFolder.appendingPathComponent("system.m4a"),
            durationSeconds: 1.0,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: nil
            )
        )

        let result = try await service.transcribeMeeting(recording: recording)

        XCTAssertEqual(result.rawTranscript, "Hello, there.")
        XCTAssertEqual(result.wordTimestamps, [])
    }

    func testTranscribeMeetingPreservesContiguousDualSourceModelText() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        let systemURL = recordingFolder.appendingPathComponent("system.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: systemURL.path, contents: Data("system".utf8)))

        await mockSTT.configureSequence(results: [
            STTResult(
                text: "Hello, there.",
                words: [
                    TimestampedWord(word: "hello", startMs: 0, endMs: 180, confidence: 0.9),
                    TimestampedWord(word: "there", startMs: 220, endMs: 420, confidence: 0.9),
                ]
            ),
            STTResult(
                text: "Sounds good.",
                words: [
                    TimestampedWord(word: "sounds", startMs: 20, endMs: 280, confidence: 0.9),
                    TimestampedWord(word: "good", startMs: 320, endMs: 560, confidence: 0.9),
                ]
            ),
        ])

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Meeting Demo",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: systemURL,
            durationSeconds: 1.5,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 900, writtenFrameCount: 24_000, sampleRate: 48_000)
            )
        )

        let result = try await service.transcribeMeeting(recording: recording)

        XCTAssertEqual(result.rawTranscript, "Hello, there. Sounds good.")
    }

    func testTranscribeMeetingPreservesContiguousSourceTextWhenOneSourceHasNoWordTimestamps() async throws {
        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        let systemURL = recordingFolder.appendingPathComponent("system.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: systemURL.path, contents: Data("system".utf8)))

        await mockSTT.configureSequence(results: [
            STTResult(
                text: "Hello, there.",
                words: []
            ),
            STTResult(
                text: "Sounds good.",
                words: [
                    TimestampedWord(word: "sounds", startMs: 20, endMs: 280, confidence: 0.9),
                    TimestampedWord(word: "good", startMs: 320, endMs: 560, confidence: 0.9),
                ]
            ),
        ])

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Meeting Demo",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: systemURL,
            durationSeconds: 1.5,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 900, writtenFrameCount: 24_000, sampleRate: 48_000)
            )
        )

        let result = try await service.transcribeMeeting(recording: recording)

        XCTAssertEqual(result.rawTranscript, "Hello, there. Sounds good.")
        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["system", "system"])
    }

    func testTranscribeMeetingSttFailureEmitsSttStageTelemetry() async throws {
        let telemetry = TelemetrySpy()
        Telemetry.configure(telemetry)
        defer { Telemetry.configure(NoOpTelemetryService()) }

        let recordingFolder = URL(fileURLWithPath: AppPaths.tempDir)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recordingFolder) }

        let mixedURL = recordingFolder.appendingPathComponent("meeting.m4a")
        let microphoneURL = recordingFolder.appendingPathComponent("microphone.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("microphone".utf8)))

        await mockSTT.configure(error: STTError.transcriptionFailed("Model error"))

        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Meeting Demo",
            folderURL: recordingFolder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: recordingFolder.appendingPathComponent("system.m4a"),
            durationSeconds: 1.0,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 24_000, sampleRate: 48_000),
                system: nil
            )
        )

        do {
            _ = try await service.transcribeMeeting(recording: recording)
            XCTFail("Should have thrown")
        } catch let error as STTError {
            guard case .transcriptionFailed = error else {
                return XCTFail("Unexpected STT error: \(error)")
            }
        }

        let events = telemetry.snapshot()
        let failedEvent = events.reversed().first {
            if case .transcriptionFailed = $0 { return true }
            return false
        }
        guard case .transcriptionFailed(let source, let stage, let errorType, _) = try XCTUnwrap(failedEvent) else {
            return XCTFail("Expected transcription_failed telemetry")
        }
        XCTAssertEqual(source, .meeting)
        XCTAssertEqual(stage, .stt)
        XCTAssertEqual(errorType, "STTError.transcriptionFailed")
    }

    func testMeetingSourceRetranscribeUsesBatchLane() async throws {
        let expectedResult = STTResult(text: "Meeting archive retranscribe")
        await mockSTT.configure(result: expectedResult)

        let fileURL = URL(fileURLWithPath: "/tmp/meeting-archive.m4a")
        _ = try await service.transcribe(fileURL: fileURL, source: .meeting)

        let lastJob = await mockSTT.lastJob
        XCTAssertEqual(lastJob, .fileTranscription)
    }

    func testRetranscribeExistingFileFailureLeavesOriginalRowIntact() async throws {
        let original = Transcription(
            id: UUID(),
            fileName: "lecture.mp3",
            filePath: "/tmp/lecture.mp3",
            rawTranscript: "Old transcript",
            status: .completed,
            sourceType: .file
        )
        try transcriptionRepo.save(original)
        await mockSTT.configure(error: STTError.transcriptionFailed("Model error"))

        do {
            _ = try await service.retranscribe(
                existing: original,
                fileURL: URL(fileURLWithPath: "/tmp/lecture.mp3"),
                source: .file,
                onProgress: nil
            )
            XCTFail("Should have thrown")
        } catch let error as STTError {
            guard case .transcriptionFailed = error else {
                return XCTFail("Unexpected STT error: \(error)")
            }
        }

        let all = try transcriptionRepo.fetchAll(limit: nil)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, original.id)
        XCTAssertEqual(all[0].rawTranscript, "Old transcript")
        XCTAssertEqual(all[0].status, .completed)
        XCTAssertNil(all[0].errorMessage)
    }

    private func telemetryProps(for spec: TelemetryEventSpec) throws -> [String: String] {
        let event = TelemetryEvent(
            spec: spec,
            appVer: "test",
            osVer: "test",
            locale: "en-US",
            chip: "test",
            session: "test"
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["props"] as? [String: String])
    }
}

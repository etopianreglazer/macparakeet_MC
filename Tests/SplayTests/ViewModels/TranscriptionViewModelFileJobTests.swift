import XCTest
@testable import SplayCore
@testable import SplayViewModels

/// Splay's file-job feedback: one activity flip per job (no flicker between
/// batch files) and one outcome per job that says where the transcript went.
/// See docs/plans/file-transcription-feedback.md.
@MainActor
final class TranscriptionViewModelFileJobTests: XCTestCase {
    private var mockService: MockTranscriptionService!
    private var mockRepo: MockTranscriptionRepository!
    private var tempDir: URL!
    private var outDir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        mockService = MockTranscriptionService()
        mockRepo = MockTranscriptionRepository()
        suiteName = "TranscriptionViewModelFileJobTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VMFileJob-\(UUID().uuidString)")
        outDir = tempDir.appendingPathComponent("Transcriptions")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeViewModel(saveFolder: Bool = true) -> TranscriptionViewModel {
        if saveFolder {
            _ = AutoSaveService.storeFolder(outDir, scope: .transcription, defaults: defaults)
        }
        let vm = TranscriptionViewModel(defaults: defaults)
        vm.configure(transcriptionService: mockService, transcriptionRepo: mockRepo)
        return vm
    }

    private func touch(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    private struct TimedOut: Error {}

    /// Throws on timeout, so a hung job fails one test instead of trapping on
    /// a force-unwrap after it.
    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline { throw TimedOut() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testSingleFileReportsWhereTheTranscriptWasSaved() async throws {
        let vm = makeViewModel()
        var activity: [Bool] = []
        var outcome: FileJobOutcome?
        vm.onFileJobActiveChanged = { activity.append($0) }
        vm.onFileJobFinished = { outcome = $0 }

        XCTAssertTrue(vm.transcribeFiles(urls: [try touch("talk.m4a")]))
        XCTAssertTrue(vm.isFileJobActive)
        try await waitUntil { outcome != nil }

        XCTAssertEqual(activity, [true, false])
        guard case .transcribed(let name, let words, let savedTo, let saveFailed) = outcome else {
            return XCTFail("expected .transcribed, got \(String(describing: outcome))")
        }
        XCTAssertEqual(name, "talk.m4a")
        XCTAssertEqual(words, 2)
        XCTAssertFalse(saveFailed)
        let saved = try XCTUnwrap(savedTo)
        XCTAssertEqual(saved.deletingLastPathComponent().standardizedFileURL.path, outDir.standardizedFileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertFalse(try XCTUnwrap(outcome).isFailure)
    }

    func testMissingFolderIsReportedNotSwallowed() async throws {
        let vm = makeViewModel(saveFolder: false) // auto-save on (default), no folder resolves
        var outcome: FileJobOutcome?
        vm.onFileJobFinished = { outcome = $0 }

        vm.transcribeFiles(urls: [try touch("talk.m4a")])
        try await waitUntil { outcome != nil }

        XCTAssertEqual(outcome, .transcribed(fileName: "talk.m4a", wordCount: 2, savedTo: nil, saveFailed: true))
        XCTAssertTrue(try XCTUnwrap(outcome).isFailure)
    }

    func testFailureCarriesTheFileNameAndReason() async throws {
        await mockService.configure(error: NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported codec"]))
        let vm = makeViewModel()
        var outcome: FileJobOutcome?
        vm.onFileJobFinished = { outcome = $0 }

        vm.transcribeFiles(urls: [try touch("broken.mov")])
        try await waitUntil { outcome != nil }

        XCTAssertEqual(outcome, .failed(fileName: "broken.mov", reason: "Unsupported codec"))
    }

    func testBatchFlipsActivityOnceAndReportsCounts() async throws {
        await mockService.configureBatch(errors: [
            "b.mp3": NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        ])
        let vm = makeViewModel()
        var activity: [Bool] = []
        var outcomes: [FileJobOutcome] = []
        vm.onFileJobActiveChanged = { activity.append($0) }
        vm.onFileJobFinished = { outcomes.append($0) }

        vm.transcribeFiles(urls: [try touch("a.mp3"), try touch("b.mp3"), try touch("c.mp3")])
        try await waitUntil { !outcomes.isEmpty }

        XCTAssertEqual(activity, [true, false], "No flicker between batch files")
        XCTAssertEqual(outcomes.count, 1, "One outcome for the whole batch")
        guard case .batch(let completed, let failed, let unsaved, let folder) = outcomes[0] else {
            return XCTFail("expected .batch")
        }
        XCTAssertEqual(completed, 2)
        XCTAssertEqual(failed, 1)
        XCTAssertEqual(unsaved, 0)
        XCTAssertEqual(folder?.standardizedFileURL.path, outDir.standardizedFileURL.path)
    }

    func testCancelEndsASingleFileNow() async throws {
        await mockService.configureDelay(milliseconds: 2_000)
        let vm = makeViewModel()
        var outcomes: [FileJobOutcome] = []
        var activity: [Bool] = []
        vm.onFileJobFinished = { outcomes.append($0) }
        vm.onFileJobActiveChanged = { activity.append($0) }

        vm.transcribeFiles(urls: [try touch("long.wav")])
        vm.cancelFileJob()

        XCTAssertFalse(vm.isFileJobActive)
        XCTAssertEqual(outcomes, [.cancelled])
        XCTAssertEqual(activity, [true, false])
    }

    func testBusyRefusesASecondJob() throws {
        let vm = makeViewModel()
        XCTAssertTrue(vm.transcribeFiles(urls: [try touch("one.wav")]))
        XCTAssertFalse(vm.transcribeFiles(urls: [try touch("two.wav")]))
    }

    func testBatchWithNoFolderCountsUnsavedFiles() async throws {
        let vm = makeViewModel(saveFolder: false)
        var outcome: FileJobOutcome?
        vm.onFileJobFinished = { outcome = $0 }

        vm.transcribeFiles(urls: [try touch("a.mp3"), try touch("b.mp3"), try touch("c.mp3")])
        try await waitUntil { outcome != nil }

        XCTAssertEqual(outcome, .batch(completed: 3, failed: 0, unsaved: 3, folder: nil))
    }

    func testCancelEndsABatchWithOneReport() async throws {
        await mockService.configureDelay(milliseconds: 200)
        let vm = makeViewModel()
        var outcomes: [FileJobOutcome] = []
        vm.onFileJobFinished = { outcomes.append($0) }

        vm.transcribeFiles(urls: [try touch("a.mp3"), try touch("b.mp3")])
        vm.cancelFileJob()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(vm.isFileJobActive)
        XCTAssertEqual(outcomes, [.cancelled])
    }

    func testRecoveredTranscriptThatCannotBeSavedIsReported() {
        let vm = makeViewModel(saveFolder: false)
        var outcome: FileJobOutcome?
        vm.onFileJobFinished = { outcome = $0 }

        let recovered = Transcription(fileName: "Standup", rawTranscript: "two words", status: .completed,
                                      sourceType: .meeting)
        vm.presentCompletedTranscription(recovered, autoSave: true)

        XCTAssertEqual(outcome, .transcribed(fileName: "Standup", wordCount: 2, savedTo: nil, saveFailed: true))
    }
}

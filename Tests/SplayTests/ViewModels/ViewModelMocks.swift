import Foundation
@testable import SplayCore

// MARK: - MockDictationRepository

final class MockDictationRepository: DictationRepositoryProtocol, @unchecked Sendable {
    var dictations: [Dictation] = []
    var deleteCalledWith: [UUID] = []
    var deleteAllCalled = false
    var deleteHiddenCalled = false
    var savedDictations: [Dictation] = []
    var statsCallCount = 0

    func save(_ dictation: Dictation) throws {
        savedDictations.append(dictation)
        // Also insert/update in the working list
        if let idx = dictations.firstIndex(where: { $0.id == dictation.id }) {
            dictations[idx] = dictation
        } else {
            dictations.append(dictation)
        }
    }

    func fetch(id: UUID) throws -> Dictation? {
        dictations.first(where: { $0.id == id })
    }

    func fetchAll(limit: Int?) throws -> [Dictation] {
        let sorted = dictations.filter { !$0.hidden }.sorted { $0.createdAt > $1.createdAt }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }

    func search(query: String, limit: Int?) throws -> [Dictation] {
        let filtered = dictations.filter {
            !$0.hidden && (
                $0.rawTranscript.localizedCaseInsensitiveContains(query)
                || ($0.cleanTranscript?.localizedCaseInsensitiveContains(query) ?? false)
            )
        }
        let sorted = filtered.sorted { $0.createdAt > $1.createdAt }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }

    func delete(id: UUID) throws -> Bool {
        deleteCalledWith.append(id)
        dictations.removeAll { $0.id == id }
        return true
    }

    func deleteAll() throws {
        deleteAllCalled = true
        dictations.removeAll { !$0.hidden }
    }

    func clearMissingAudioPaths() throws {
        // No-op in mock
    }

    func deleteEmpty() throws -> Int {
        let before = dictations.count
        dictations.removeAll {
            !$0.hidden && $0.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return before - dictations.count
    }

    func deleteHidden() throws {
        deleteHiddenCalled = true
        dictations.removeAll { $0.hidden }
    }

    var resetLifetimeStatsCalled = false
    func resetLifetimeStats() throws {
        resetLifetimeStatsCalled = true
    }

    var setDisplayRawTranscriptCalls: [(id: UUID, value: Bool)] = []
    @discardableResult
    func setDisplayRawTranscript(id: UUID, value: Bool) throws -> Bool {
        setDisplayRawTranscriptCalls.append((id, value))
        guard let idx = dictations.firstIndex(where: { $0.id == id }) else { return false }
        // Mirror production's no-op short-circuit: when the value is
        // unchanged, return true without bumping `updatedAt` (the prod repo
        // uses this to avoid touching the row on repeat clicks). Tests that
        // assert on timestamps depend on the mock behaving identically.
        guard dictations[idx].displayRawTranscript != value else { return true }
        dictations[idx].displayRawTranscript = value
        dictations[idx].updatedAt = Date()
        return true
    }

    func stats() throws -> DictationStats {
        statsCallCount += 1
        let completed = dictations.filter { $0.status == .completed }
        let totalDuration = completed.reduce(0) { $0 + $1.durationMs }
        let totalWords = completed.reduce(0) { $0 + $1.wordCount }
        let maxDuration = completed.map(\.durationMs).max() ?? 0
        let avgDuration = completed.isEmpty ? 0 : totalDuration / completed.count

        let dates = completed.map(\.createdAt)
        let (streak, thisWeek) = DictationRepository.computeWeeklyStreak(from: dates)

        let visible = completed.filter { !$0.hidden }
        return DictationStats(
            totalCount: completed.count,
            visibleCount: visible.count,
            totalDurationMs: totalDuration,
            totalWords: totalWords,
            longestDurationMs: maxDuration,
            averageDurationMs: avgDuration,
            weeklyStreak: streak,
            dictationsThisWeek: thisWeek
        )
    }

    // Daily-rollup surface — mock returns empty/zero because no test currently
    // exercises the Stats tab through this mock. Real semantics are covered by
    // DailyDictationStatsTests against the production repository.
    func dailyStats(daysBack days: Int) throws -> [DailyDictationStat] { [] }
    func currentDailyStreak() throws -> Int { 0 }
    func longestDailyStreak() throws -> Int { 0 }
    func topApps(limit: Int) throws -> [(app: String, count: Int, words: Int)] { [] }
}

// MARK: - MockTranscriptionRepository

final class MockTranscriptionRepository: TranscriptionRepositoryProtocol, @unchecked Sendable {
    var transcriptions: [Transcription] = []
    var deleteCalledWith: [UUID] = []
    var deleteAllCalled = false
    var deleteResult = true
    var deleteError: Error?
    var updateFileNameCalls: [(id: UUID, fileName: String)] = []
    var updateChatMessagesCalls: [(id: UUID, chatMessages: [ChatMessage]?)] = []
    var updateSpeakersCalls: [(id: UUID, speakers: [SpeakerInfo]?)] = []
    var updateFilePathCalls: [(id: UUID, filePath: String?)] = []
    var updateFilePathError: Error?
    var saveError: Error?

    func save(_ transcription: Transcription) throws {
        if let saveError {
            throw saveError
        }
        if let idx = transcriptions.firstIndex(where: { $0.id == transcription.id }) {
            transcriptions[idx] = transcription
        } else {
            transcriptions.append(transcription)
        }
    }

    func fetch(id: UUID) throws -> Transcription? {
        transcriptions.first(where: { $0.id == id })
    }

    func fetchAll(limit: Int?) throws -> [Transcription] {
        let sorted = transcriptions.sorted { $0.createdAt > $1.createdAt }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }

    func fetchCompletedByVideoID(_ videoID: String) throws -> Transcription? {
        transcriptions.first { t in
            t.status == .completed
                && t.sourceURL != nil
                && (t.sourceURL?.contains(videoID) ?? false)
        }
    }

    func delete(id: UUID) throws -> Bool {
        deleteCalledWith.append(id)
        if let deleteError {
            throw deleteError
        }
        guard deleteResult else { return false }
        let before = transcriptions.count
        transcriptions.removeAll { $0.id == id }
        return transcriptions.count < before
    }

    func deleteAll() throws {
        deleteAllCalled = true
        transcriptions.removeAll()
    }

    func updateStatus(id: UUID, status: Transcription.TranscriptionStatus, errorMessage: String?) throws {
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].status = status
            transcriptions[idx].errorMessage = errorMessage
        }
    }

    func updateFileName(id: UUID, fileName: String) throws {
        updateFileNameCalls.append((id: id, fileName: fileName))
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].fileName = fileName
            transcriptions[idx].updatedAt = Date()
        }
    }

    func updateChatMessages(id: UUID, chatMessages: [ChatMessage]?) throws {
        updateChatMessagesCalls.append((id: id, chatMessages: chatMessages))
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].chatMessages = chatMessages
            transcriptions[idx].updatedAt = Date()
        }
    }

    func updateSpeakers(id: UUID, speakers: [SpeakerInfo]?) throws {
        updateSpeakersCalls.append((id: id, speakers: speakers))
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].speakers = speakers
            transcriptions[idx].updatedAt = Date()
        }
    }

    func updateFilePath(id: UUID, filePath: String?) throws {
        updateFilePathCalls.append((id: id, filePath: filePath))
        if let updateFilePathError {
            throw updateFilePathError
        }
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].filePath = filePath
            transcriptions[idx].updatedAt = Date()
        }
    }

    func clearStoredAudioPathsForURLTranscriptions() throws {
        for i in transcriptions.indices {
            if transcriptions[i].sourceURL != nil {
                transcriptions[i].filePath = nil
            }
        }
    }

    func updateFavorite(id: UUID, isFavorite: Bool) throws {
        if let idx = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[idx].isFavorite = isFavorite
            transcriptions[idx].updatedAt = Date()
        }
    }

    func fetchFavorites() throws -> [Transcription] {
        transcriptions.filter(\.isFavorite).sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - MockLaunchAtLoginService

final class MockLaunchAtLoginService: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus
    var setEnabledCalls: [Bool] = []
    var errorToThrow: Error?

    init(status: LaunchAtLoginStatus = .disabled, errorToThrow: Error? = nil) {
        self.status = status
        self.errorToThrow = errorToThrow
    }

    func currentStatus() -> LaunchAtLoginStatus {
        status
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        setEnabledCalls.append(enabled)
        if let errorToThrow {
            throw errorToThrow
        }
        status = enabled ? .enabled : .disabled
        return status
    }
}

// MARK: - MockTranscriptionService

actor MockTranscriptionService: SpeechEngineOverrideTranscriptionService {
    var transcribeResult: Transcription?
    var transcribeError: Error?
    var transcribeCallCount = 0
    var lastFileURL: URL?
    var lastSource: TelemetryTranscriptionSource?
    var lastMeetingRecording: MeetingRecordingOutput?
    var lastSpeechEngineOverride: SpeechEngineSelection?
    var transcribeProgressPhases: [TranscriptionProgress] = []
    var transcribeDelayMs: UInt64 = 0
    /// Per-file overrides for batch tests, keyed by `fileURL.lastPathComponent`.
    /// `errorsByFileName` wins over `resultsByFileName`, which wins over the
    /// shared `transcribeError`/`transcribeResult`.
    var resultsByFileName: [String: Transcription] = [:]
    var errorsByFileName: [String: Error] = [:]
    var transcribedFileNames: [String] = []

    func configure(result: Transcription) {
        self.transcribeResult = result
        self.transcribeError = nil
    }

    func configureBatch(results: [String: Transcription] = [:], errors: [String: Error] = [:]) {
        self.resultsByFileName = results
        self.errorsByFileName = errors
    }

    func configure(error: Error) {
        self.transcribeError = error
        self.transcribeResult = nil
    }

    func configureProgress(phases: [TranscriptionProgress]) {
        self.transcribeProgressPhases = phases
    }

    func configureDelay(milliseconds: UInt64) {
        self.transcribeDelayMs = milliseconds
    }

    func transcribe(
        fileURL: URL,
        source: TelemetryTranscriptionSource,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)? = nil
    ) async throws -> Transcription {
        transcribeCallCount += 1
        lastFileURL = fileURL
        lastSource = source
        let fileName = fileURL.lastPathComponent
        transcribedFileNames.append(fileName)

        for phase in transcribeProgressPhases {
            onProgress?(phase)
        }

        if transcribeDelayMs > 0 {
            try await Task.sleep(nanoseconds: transcribeDelayMs * 1_000_000)
        }

        if let error = errorsByFileName[fileName] {
            throw error
        }
        if let error = transcribeError {
            throw error
        }
        if let result = resultsByFileName[fileName] {
            return result
        }

        return transcribeResult ?? Transcription(
            fileName: fileName,
            rawTranscript: "Mock transcription",
            status: .completed
        )
    }

    func transcribeTransient(
        fileURL: URL,
        source: TelemetryTranscriptionSource,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)? = nil
    ) async throws -> Transcription {
        try await transcribe(fileURL: fileURL, source: source, onProgress: onProgress)
    }

    func transcribeMeeting(
        recording: MeetingRecordingOutput,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)? = nil
    ) async throws -> Transcription {
        transcribeCallCount += 1
        lastMeetingRecording = recording
        lastSource = .meeting

        for phase in transcribeProgressPhases {
            onProgress?(phase)
        }

        if transcribeDelayMs > 0 {
            try await Task.sleep(nanoseconds: transcribeDelayMs * 1_000_000)
        }

        if let error = transcribeError {
            throw error
        }

        return transcribeResult ?? Transcription(
            fileName: recording.displayName,
            filePath: recording.mixedAudioURL.path,
            rawTranscript: "Mock meeting transcription",
            status: .completed,
            sourceType: .meeting
        )
    }

    func retranscribe(
        existing transcription: Transcription,
        fileURL: URL,
        source: TelemetryTranscriptionSource,
        speechEngineOverride: SpeechEngineSelection?,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription {
        lastSpeechEngineOverride = speechEngineOverride
        return try await transcribe(fileURL: fileURL, source: source, onProgress: onProgress)
    }

    func retranscribeMeeting(
        existing transcription: Transcription,
        recording: MeetingRecordingOutput,
        speechEngineOverride: SpeechEngineSelection?,
        onProgress: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> Transcription {
        lastSpeechEngineOverride = speechEngineOverride
        return try await transcribeMeeting(recording: recording, onProgress: onProgress)
    }
}

// MARK: - MockCustomWordRepository

final class MockCustomWordRepository: CustomWordRepositoryProtocol, @unchecked Sendable {
    var words: [CustomWord] = []

    func save(_ word: CustomWord) throws {
        if let idx = words.firstIndex(where: { $0.id == word.id }) {
            words[idx] = word
        } else {
            words.append(word)
        }
    }

    func fetch(id: UUID) throws -> CustomWord? {
        words.first(where: { $0.id == id })
    }

    func fetchAll() throws -> [CustomWord] {
        words.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    func fetchEnabled() throws -> [CustomWord] {
        words.filter { $0.isEnabled }
            .sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    func delete(id: UUID) throws -> Bool {
        let before = words.count
        words.removeAll { $0.id == id }
        return words.count < before
    }

    func deleteAll() throws {
        words.removeAll()
    }
}

// MARK: - MockTextSnippetRepository

final class MockTextSnippetRepository: TextSnippetRepositoryProtocol, @unchecked Sendable {
    var snippets: [TextSnippet] = []
    var incrementedIDs: [Set<UUID>] = []

    func save(_ snippet: TextSnippet) throws {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
        } else {
            snippets.append(snippet)
        }
    }

    func fetch(id: UUID) throws -> TextSnippet? {
        snippets.first(where: { $0.id == id })
    }

    func fetchAll() throws -> [TextSnippet] {
        snippets.sorted { $0.trigger.localizedCaseInsensitiveCompare($1.trigger) == .orderedAscending }
    }

    func fetchEnabled() throws -> [TextSnippet] {
        snippets.filter { $0.isEnabled }
            .sorted { $0.trigger.localizedCaseInsensitiveCompare($1.trigger) == .orderedAscending }
    }

    func delete(id: UUID) throws -> Bool {
        let before = snippets.count
        snippets.removeAll { $0.id == id }
        return snippets.count < before
    }

    func deleteAll() throws {
        snippets.removeAll()
    }

    func incrementUseCount(ids: Set<UUID>) throws {
        incrementedIDs.append(ids)
        for id in ids {
            if let idx = snippets.firstIndex(where: { $0.id == id }) {
                snippets[idx].useCount += 1
            }
        }
    }
}

// MARK: - MockPermissionService

final class MockPermissionService: PermissionServiceProtocol, @unchecked Sendable {
    var microphonePermission: PermissionStatus = .granted
    var screenRecordingPermission = true
    var accessibilityPermission: Bool = true
    var requestMicResult: Bool = true
    var requestScreenRecordingResult: Bool = true
    var requestAccessibilityResult: Bool = true
    var requestMicrophonePermissionCallCount = 0
    var checkScreenRecordingPermissionCallCount = 0
    var openMicrophoneSettingsCallCount = 0
    var screenRecordingPermissionSequence: [Bool] = []

    func checkMicrophonePermission() async -> PermissionStatus {
        return microphonePermission
    }

    func requestMicrophonePermission() async -> Bool {
        requestMicrophonePermissionCallCount += 1
        microphonePermission = requestMicResult ? .granted : .denied
        return requestMicResult
    }

    func checkScreenRecordingPermission() -> Bool {
        checkScreenRecordingPermissionCallCount += 1
        if !screenRecordingPermissionSequence.isEmpty {
            let idx = min(checkScreenRecordingPermissionCallCount - 1, screenRecordingPermissionSequence.count - 1)
            screenRecordingPermission = screenRecordingPermissionSequence[idx]
        }
        return screenRecordingPermission
    }

    func requestScreenRecordingPermission() -> Bool {
        screenRecordingPermission = requestScreenRecordingResult
        return screenRecordingPermission
    }

    func openMicrophoneSettings() {
        openMicrophoneSettingsCallCount += 1
    }

    func openScreenRecordingSettings() {}

    func checkAccessibilityPermission() -> Bool {
        accessibilityPermission
    }

    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        accessibilityPermission = requestAccessibilityResult
        return accessibilityPermission
    }
}

import Foundation
import SplayCore

@MainActor
@Observable
public final class MeetingsWorkspaceViewModel {
    public enum RecordingStatus: Equatable {
        case ready
        case recording
        case paused
        case finishing
        case transcribing
        case error(String)
    }

    public enum IntelligenceStatus: Equatable {
        case setupNeeded
        case ready(displayName: String, isLocal: Bool)
        case cannotConnect(displayName: String, message: String)
    }

    public enum AttentionSeverity: Equatable, Sendable {
        case recommended
        case required
    }

    public enum AttentionAction: Equatable, Sendable {
        case recordMeeting
        case recoverMeetings
        case openAISettings
    }

    public struct AttentionItem: Identifiable, Equatable, Sendable {
        public let id: String
        public let severity: AttentionSeverity
        public let title: String
        public let detail: String
        public let actionTitle: String
        public let action: AttentionAction

        public init(
            id: String,
            severity: AttentionSeverity,
            title: String,
            detail: String,
            actionTitle: String,
            action: AttentionAction
        ) {
            self.id = id
            self.severity = severity
            self.title = title
            self.detail = detail
            self.actionTitle = actionTitle
            self.action = action
        }
    }

    public let recentMeetingsViewModel: TranscriptionLibraryViewModel
    public let meetingPillViewModel: MeetingRecordingPillViewModel
    public let settingsViewModel: SettingsViewModel
    public let llmSettingsViewModel: LLMSettingsViewModel
    public let quickPromptsViewModel: QuickPromptsViewModel
    public let promptsViewModel: PromptsViewModel

    @ObservationIgnored private var hasLoadedInitialState = false

    public init(
        recentMeetingsViewModel: TranscriptionLibraryViewModel,
        meetingPillViewModel: MeetingRecordingPillViewModel,
        settingsViewModel: SettingsViewModel,
        llmSettingsViewModel: LLMSettingsViewModel,
        quickPromptsViewModel: QuickPromptsViewModel? = nil,
        promptsViewModel: PromptsViewModel? = nil
    ) {
        self.recentMeetingsViewModel = recentMeetingsViewModel
        self.meetingPillViewModel = meetingPillViewModel
        self.settingsViewModel = settingsViewModel
        self.llmSettingsViewModel = llmSettingsViewModel
        self.quickPromptsViewModel = quickPromptsViewModel ?? QuickPromptsViewModel()
        self.promptsViewModel = promptsViewModel ?? PromptsViewModel()
    }

    public func configure(
        transcriptionRepo: TranscriptionRepositoryProtocol,
        quickPromptRepo: QuickPromptRepositoryProtocol? = nil,
        promptRepo: PromptRepositoryProtocol? = nil
    ) {
        recentMeetingsViewModel.configure(transcriptionRepo: transcriptionRepo)
        if let quickPromptRepo {
            quickPromptsViewModel.configure(repo: quickPromptRepo)
        }
        if let promptRepo {
            promptsViewModel.configure(repo: promptRepo)
        }
    }

    public func refresh() {
        hasLoadedInitialState = true
        refreshRecentMeetings()
        refreshQuickPrompts()
        refreshAutoNotes()
    }

    public func refreshIfNeeded() {
        guard !hasLoadedInitialState else { return }
        refresh()
    }

    @discardableResult
    public func refreshRecentMeetings() -> Task<Void, Never> {
        recentMeetingsViewModel.loadTranscriptions()
    }

    public func refreshQuickPrompts() {
        quickPromptsViewModel.refresh()
    }

    public var liveAskPromptVisiblePinnedCount: Int {
        quickPromptsViewModel.visiblePinned.count
    }

    public var liveAskPromptPreviewPrompts: [QuickPrompt] {
        Array(quickPromptsViewModel.visiblePinned.prefix(2))
    }

    // MARK: - After-each-meeting auto-notes

    public func refreshAutoNotes() {
        promptsViewModel.loadPrompts()
    }

    /// Visible result prompts the user can toggle as meeting auto-notes.
    /// Hidden prompts can't auto-run, so they're excluded from the card.
    /// (`promptsViewModel.prompts` is already `.result`-only.)
    public var meetingAutoNotePrompts: [Prompt] {
        promptsViewModel.prompts.filter { $0.isVisible }
    }

    /// Prompts that will actually auto-run after a meeting finishes.
    public var meetingAutoNoteActivePrompts: [Prompt] {
        meetingAutoNotePrompts.filter { $0.autoRuns(for: .meeting) }
    }

    public var meetingAutoNoteActiveCount: Int {
        meetingAutoNoteActivePrompts.count
    }

    public func isMeetingAutoNote(_ prompt: Prompt) -> Bool {
        prompt.autoRuns(for: .meeting)
    }

    public func setMeetingAutoNote(_ prompt: Prompt, enabled: Bool) {
        promptsViewModel.setAutoRun(prompt, source: .meeting, enabled: enabled)
    }

    /// Auto-notes need a configured AI provider to generate. `false` only when
    /// no provider is set up yet (the card shows a "Set up AI" prompt instead
    /// of dead toggles); a chosen-but-unreachable provider still shows toggles.
    public var isAutoNotesConfigured: Bool {
        if case .setupNeeded = intelligenceStatus { return false }
        return true
    }

    /// Display name of the configured provider, for the card's "Uses …" line.
    public var autoNotesProviderName: String? {
        switch intelligenceStatus {
        case .ready(let displayName, _), .cannotConnect(let displayName, _):
            return displayName
        case .setupNeeded:
            return nil
        }
    }

    public var recordingStatus: RecordingStatus {
        switch meetingPillViewModel.state {
        case .idle, .completed:
            return .ready
        case .recording:
            return .recording
        case .paused:
            return .paused
        case .completing:
            return .finishing
        case .transcribing:
            return .transcribing
        case .error(let message):
            return .error(message)
        }
    }

    public var hasActiveRecording: Bool {
        switch recordingStatus {
        case .recording, .paused, .finishing, .transcribing:
            return true
        case .ready, .error:
            return false
        }
    }

    public var intelligenceStatus: IntelligenceStatus {
        switch llmSettingsViewModel.setupStatus {
        case .setUpNeeded:
            return .setupNeeded
        case .ready(let displayName):
            return .ready(
                displayName: displayName,
                isLocal: llmSettingsViewModel.isLocalConfiguration
            )
        case .cannotConnect(let displayName, let message):
            return .cannotConnect(displayName: displayName, message: message)
        }
    }

    public var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []

        if settingsViewModel.pendingMeetingRecoveryCount > 0 {
            let count = settingsViewModel.pendingMeetingRecoveryCount
            items.append(AttentionItem(
                id: "meeting-recovery",
                severity: .required,
                title: "Interrupted recording",
                detail: "\(count) partial recording\(count == 1 ? "" : "s") can be recovered.",
                actionTitle: "Recover",
                action: .recoverMeetings
            ))
        }

        if case .error(let message) = recordingStatus {
            items.append(AttentionItem(
                id: "recording-error",
                severity: .required,
                title: "Recording stopped",
                detail: message,
                actionTitle: "Record Again",
                action: .recordMeeting
            ))
        }

        if case .cannotConnect(let displayName, let message) = intelligenceStatus {
            items.append(AttentionItem(
                id: "ai-unavailable",
                severity: .recommended,
                title: "\(displayName) unavailable",
                detail: message,
                actionTitle: "Open AI Settings",
                action: .openAISettings
            ))
        }

        return items
    }
}

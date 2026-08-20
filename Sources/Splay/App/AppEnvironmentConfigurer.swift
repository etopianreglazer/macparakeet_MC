import AppKit
import Foundation
import SplayCore
import SplayViewModels

@MainActor
final class AppEnvironmentConfigurer {
    private final class CoordinatorRefs {
        weak var dictation: DictationFlowCoordinator?
        weak var meeting: MeetingRecordingFlowCoordinator?
        weak var island: IslandController?
    }

    struct Runtime {
        let dictationFlowCoordinator: DictationFlowCoordinator
        let meetingRecordingFlowCoordinator: MeetingRecordingFlowCoordinator
        let hotkeyCoordinator: AppHotkeyCoordinator
        /// The ambient island panel (fork: `islandReplacesDictationPill`). Nil
        /// when the flag is off. Long-lived; retained by `AppDelegate`. Pure
        /// indicator — anything it needs to say is a card (`SplayCardController`).
        let islandController: IslandController?
    }

    struct Callbacks {
        let onMenuBarIconUpdate: () -> Void
        let onPresentEntitlementsAlert: (Error) -> Void
        let onOpenMainWindow: () -> Void
        /// The island mark click and the menu-bar "Open Splay" item present the
        /// menu card (the second surface), opened to its recents tab.
        let onOpenRecentCard: () -> Void
        /// Clicking the failed island clears the held failure and presents a
        /// card carrying the failure message — the error text's one visible home.
        let onOpenErrorCard: (String) -> Void
        let onToggleMeetingRecordingFromHotkey: () -> Void
        let onTriggerFileTranscriptionFromHotkey: () -> Void
        let onHotkeyBecameAvailable: () -> Void
        let onHotkeyUnavailable: () -> Void
        let onHotkeyConflict: (HotkeyTrigger, [HotkeyTrigger]) -> Void
        let onRecoverPendingMeetingRecordings: () -> Void
        let isHotkeyRecordingActive: () -> Bool
        /// True while the onboarding window is showing. Used to gate the real
        /// dictation flow so a hotkey press during onboarding (e.g. the "Learn
        /// the Hotkey" rehearsal, or a returning user whose taps are armed)
        /// can never start a real, model-less dictation.
        let isOnboardingVisible: () -> Bool
    }

    private let transcriptionViewModel: TranscriptionViewModel
    private let historyViewModel: DictationHistoryViewModel
    private let settingsViewModel: SettingsViewModel
    private let customWordsViewModel: CustomWordsViewModel
    private let textSnippetsViewModel: TextSnippetsViewModel
    private let vocabularyBackupViewModel: VocabularyBackupViewModel
    private let libraryViewModel: TranscriptionLibraryViewModel
    private let meetingsWorkspaceViewModel: MeetingsWorkspaceViewModel
    private let llmSettingsViewModel: LLMSettingsViewModel
    private let chatViewModel: TranscriptChatViewModel
    private let promptResultsViewModel: PromptResultsViewModel
    private let promptsViewModel: PromptsViewModel
    private let transformsViewModel: TransformsViewModel
    private let mainWindowState: MainWindowState
    private let meetingPillViewModel: MeetingRecordingPillViewModel
    private weak var liveMeetingCoordinator: MeetingRecordingFlowCoordinator?
    /// Created by AppDelegate before slow bootstrap so the idle cue is immediate.
    var earlyIslandController: IslandController?

    init(
        transcriptionViewModel: TranscriptionViewModel,
        historyViewModel: DictationHistoryViewModel,
        settingsViewModel: SettingsViewModel,
        customWordsViewModel: CustomWordsViewModel,
        textSnippetsViewModel: TextSnippetsViewModel,
        vocabularyBackupViewModel: VocabularyBackupViewModel,
        libraryViewModel: TranscriptionLibraryViewModel,
        meetingsWorkspaceViewModel: MeetingsWorkspaceViewModel,
        llmSettingsViewModel: LLMSettingsViewModel,
        chatViewModel: TranscriptChatViewModel,
        promptResultsViewModel: PromptResultsViewModel,
        promptsViewModel: PromptsViewModel,
        transformsViewModel: TransformsViewModel,
        mainWindowState: MainWindowState,
        meetingPillViewModel: MeetingRecordingPillViewModel
    ) {
        self.transcriptionViewModel = transcriptionViewModel
        self.historyViewModel = historyViewModel
        self.settingsViewModel = settingsViewModel
        self.customWordsViewModel = customWordsViewModel
        self.textSnippetsViewModel = textSnippetsViewModel
        self.vocabularyBackupViewModel = vocabularyBackupViewModel
        self.libraryViewModel = libraryViewModel
        self.meetingsWorkspaceViewModel = meetingsWorkspaceViewModel
        self.llmSettingsViewModel = llmSettingsViewModel
        self.chatViewModel = chatViewModel
        self.promptResultsViewModel = promptResultsViewModel
        self.promptsViewModel = promptsViewModel
        self.transformsViewModel = transformsViewModel
        self.mainWindowState = mainWindowState
        self.meetingPillViewModel = meetingPillViewModel
    }

    func configure(environment env: AppEnvironment, callbacks: Callbacks) -> Runtime {
        Task {
            // Only bootstrap trial if onboarding is already completed (returning user).
            // For new users, trial starts at onboarding completion, not during setup.
            let onboardingDone = UserDefaults.standard.string(forKey: OnboardingViewModel.onboardingCompletedKey) != nil
            if onboardingDone {
                await env.entitlementsService.bootstrapTrialIfNeeded()
            }
            await env.entitlementsService.refreshValidationIfNeeded()
        }

        let hasLLMConfig = (try? env.llmConfigStore.loadConfig()) != nil

        transcriptionViewModel.configure(
            transcriptionService: env.transcriptionService,
            transcriptionRepo: env.transcriptionRepo,
            llmService: hasLLMConfig ? env.llmService : nil,
            promptResultRepo: env.promptResultRepo,
            promptResultsViewModel: promptResultsViewModel
        )
        historyViewModel.configure(dictationRepo: env.dictationRepo)
        libraryViewModel.configure(transcriptionRepo: env.transcriptionRepo)
        meetingsWorkspaceViewModel.configure(
            transcriptionRepo: env.transcriptionRepo,
            quickPromptRepo: env.quickPromptRepo,
            promptRepo: env.promptRepo
        )
        settingsViewModel.configure(
            permissionService: env.permissionService,
            dictationRepo: env.dictationRepo,
            transcriptionRepo: env.transcriptionRepo,
            transformHistoryRepo: env.transformHistoryRepo,
            entitlementsService: env.entitlementsService,
            launchAtLoginService: env.launchAtLoginService,
            checkoutURL: env.checkoutURL,
            customWordRepo: env.customWordRepo,
            snippetRepo: env.snippetRepo,
            sttClient: env.sttScheduler,
            speechEngineSwitcher: env.sttScheduler,
            speechEngineSwitchAvailabilityProvider: env.sttScheduler,
            meetingRecoveryService: env.meetingRecordingRecoveryService,
            sharedMicStream: env.sharedMicStream
        )
        settingsViewModel.onRecoverPendingMeetingRecordings = callbacks.onRecoverPendingMeetingRecordings
        customWordsViewModel.configure(repo: env.customWordRepo)
        textSnippetsViewModel.configure(repo: env.snippetRepo)
        let vocabularyBackupService = VocabularyImportExportService(
            customWordRepo: env.customWordRepo,
            snippetRepo: env.snippetRepo,
            dbQueue: env.databaseManager.dbQueue
        )
        vocabularyBackupViewModel.configure(service: vocabularyBackupService) { [weak self] in
            self?.customWordsViewModel.loadWords()
            self?.textSnippetsViewModel.loadSnippets()
            self?.settingsViewModel.refreshStats()
        }
        promptsViewModel.configure(repo: env.promptRepo)
        transformsViewModel.configure(
            repo: env.promptRepo,
            historyRepo: env.transformHistoryRepo,
            clipboardService: env.clipboardService,
            hasLLMProvider: hasLLMConfig
        )
        llmSettingsViewModel.configure(
            configStore: env.llmConfigStore,
            llmClient: env.llmClient
        )

        settingsViewModel.onDictationStateChanged = { [weak self] in
            self?.historyViewModel.loadDictations()
        }
        settingsViewModel.onTransformHistoryChanged = { [weak self] in
            Task {
                await self?.transformsViewModel.loadHistory()
            }
        }

        llmSettingsViewModel.onConfigurationChanged = { [weak self] in
            self?.refreshLLMAvailability(in: env)
        }

        chatViewModel.configure(
            llmService: hasLLMConfig ? env.llmService : nil,
            transcriptText: "",
            transcriptionRepo: env.transcriptionRepo,
            configStore: env.llmConfigStore,
            llmClient: env.llmClient,
            conversationRepo: env.chatConversationRepo
        )

        promptResultsViewModel.configure(
            llmService: hasLLMConfig ? env.llmService : nil,
            promptRepo: env.promptRepo,
            promptResultRepo: env.promptResultRepo,
            // Without this, `fetchUserNotes` short-circuits to `nil`, which
            // would silently render `{{userNotes}}` as an empty string in any
            // user-defined prompt that references it, and feed `nil` userNotes
            // into the chat path that ADR-020's 2026-05-02 amendment relies on.
            transcriptionRepo: env.transcriptionRepo,
            configStore: env.llmConfigStore,
            llmClient: env.llmClient
        )

        chatViewModel.onConversationsChanged = { [weak self] transcriptionID, hasConversations in
            self?.transcriptionViewModel.updateConversationStatus(
                id: transcriptionID,
                hasConversations: hasConversations
            )
        }

        chatViewModel.onModelChanged = { [weak self] in
            self?.promptResultsViewModel.refreshModelInfo()
        }

        promptResultsViewModel.onModelChanged = { [weak self] in
            self?.chatViewModel.refreshModelInfo()
        }

        promptResultsViewModel.onPromptResultsChanged = { [weak self] transcriptionID, hasPromptResults in
            guard self?.transcriptionViewModel.currentTranscription?.id == transcriptionID else { return }
            self?.transcriptionViewModel.hasPromptResultTabs = hasPromptResults
        }

        promptResultsViewModel.onGenerationCompleted = { [weak self] generationID, promptResultID in
            self?.transcriptionViewModel.handleGenerationCompleted(generationID, promptResultID: promptResultID)
        }

        promptResultsViewModel.onGenerationFailed = { [weak self] generationID, replacingPromptResultID in
            self?.transcriptionViewModel.handleGenerationFailed(
                generationID,
                replacingPromptResultID: replacingPromptResultID
            )
        }

        promptResultsViewModel.onDeletedPromptResult = { [weak self] promptResultID in
            self?.transcriptionViewModel.handlePromptResultDeleted(promptResultID)
        }

        promptResultsViewModel.shouldMarkPromptResultUnread = { [weak self] promptResultID in
            guard let self else { return true }
            if case .result(let id) = self.transcriptionViewModel.selectedTab,
               id == promptResultID {
                return false
            }
            return true
        }

        transcriptionViewModel.onTranscribingChanged = { _ in
            callbacks.onMenuBarIconUpdate()
        }

        transcriptionViewModel.onTranscriptionCompleted = { content in
            // Invoked synchronously from the ViewModel's @MainActor completion
            // funnel, so the chime/banner fire immediately (no run-loop hop).
            MainActor.assumeIsolated {
                TranscriptionCompletionPresenter.present(content)
            }
        }

        let coordinatorRefs = CoordinatorRefs()
        let mediaPauseCoordinator = DictationMediaPauseCoordinator(
            settingsViewModel: settingsViewModel,
            mediaController: env.systemMediaController,
            isMeetingRecordingActive: {
                coordinatorRefs.meeting?.isMeetingRecordingActive == true
            }
        )

        let dictationCoordinator = DictationFlowCoordinator(
            dictationService: env.dictationService,
            clipboardService: env.clipboardService,
            entitlementsService: env.entitlementsService,
            dictationRepo: env.dictationRepo,
            settingsViewModel: settingsViewModel,
            sttRuntime: env.sttRuntime,
            runtimePreferences: env.runtimePreferences,
            permissionService: env.permissionService,
            mediaPauseCoordinator: mediaPauseCoordinator,
            shouldSuppressIdlePill: {
                coordinatorRefs.meeting?.isMeetingRecordingActive == true
            },
            // Gate every dictation start (hotkey *and* idle-pill click) while
            // onboarding is up: the model isn't downloaded until a later step,
            // and the "Learn the Hotkey" step runs its own no-STT rehearsal.
            isStartSuppressed: { callbacks.isOnboardingVisible() },
            onMenuBarIconUpdate: { _ in callbacks.onMenuBarIconUpdate() },
            onHistoryReload: { [weak self] in self?.historyViewModel.loadDictations() },
            onPresentEntitlementsAlert: callbacks.onPresentEntitlementsAlert
        )
        coordinatorRefs.dictation = dictationCoordinator

        let meetingCoordinator = MeetingRecordingFlowCoordinator(
            meetingRecordingService: env.meetingRecordingService,
            transcriptionService: env.transcriptionService,
            permissionService: env.permissionService,
            transcriptionRepo: env.transcriptionRepo,
            conversationRepo: env.chatConversationRepo,
            quickPromptRepo: env.quickPromptRepo,
            configStore: env.llmConfigStore,
            sttManager: env.sttScheduler,
            meetingAudioSourceModeProvider: { env.runtimePreferences.meetingAudioSourceMode },
            llmService: hasLLMConfig ? env.llmService : nil,
            pillViewModel: meetingPillViewModel,
            onMenuBarIconUpdate: { _ in callbacks.onMenuBarIconUpdate() },
            onTranscriptionReady: { [weak self] transcription in
                guard let self else { return }
                self.transcriptionViewModel.presentCompletedTranscription(transcription, autoSave: true)
                self.libraryViewModel.loadTranscriptions()
                self.meetingsWorkspaceViewModel.refreshRecentMeetings()
                self.mainWindowState.navigateToTranscription(from: .library)
                callbacks.onOpenMainWindow()
            },
            onRecordingBegan: {
                coordinatorRefs.dictation?.hideIdlePill()
                coordinatorRefs.island?.resetHover()
            },
            onFlowReturnedToIdle: {
                callbacks.onMenuBarIconUpdate()
                guard coordinatorRefs.dictation?.isDictationActive != true else { return }
                coordinatorRefs.dictation?.showIdlePill()
            }
        )
        coordinatorRefs.meeting = meetingCoordinator
        liveMeetingCoordinator = meetingCoordinator

        let hotkeyCoordinator = AppHotkeyCoordinator(
            settingsViewModel: settingsViewModel,
            onStartDictation: { mode in
                coordinatorRefs.dictation?.startDictation(mode: mode, trigger: .hotkey)
            },
            onStopDictation: {
                coordinatorRefs.dictation?.stopDictation()
            },
            onCancelDictation: {
                coordinatorRefs.dictation?.cancelDictation(reason: .escape)
            },
            onDiscardRecording: { showReadyPill in
                coordinatorRefs.dictation?.discardProvisionalRecording(showReadyPill: showReadyPill)
            },
            onReadyForSecondTap: {
                coordinatorRefs.dictation?.showReadyPill()
            },
            onEscapeWhileIdle: {
                coordinatorRefs.dictation?.dismissOverlayIfError()
            },
            onToggleMeetingRecording: callbacks.onToggleMeetingRecordingFromHotkey,
            onFnToggleRecording: { sourceMode in
                coordinatorRefs.meeting?.toggleRecording(trigger: .hotkey, sourceModeOverride: sourceMode)
            },
            onTriggerFileTranscription: callbacks.onTriggerFileTranscriptionFromHotkey,
            onDictationHotkeyManagersChanged: { managers in
                coordinatorRefs.dictation?.hotkeyManagers = managers
            },
            onAnyHotkeyEnabled: callbacks.onHotkeyBecameAvailable,
            onHotkeyUnavailable: callbacks.onHotkeyUnavailable,
            onHotkeyConflict: callbacks.onHotkeyConflict,
            dictationRecordingModeProvider: {
                coordinatorRefs.dictation?.hotkeyRecordingMode
            }
        )

        if callbacks.isHotkeyRecordingActive() {
            hotkeyCoordinator.suspend()
        }
        hotkeyCoordinator.setupAllHotkeys()
        // No-op while `islandReplacesDictationPill` is on; the island owns the
        // idle surface in the fork.
        dictationCoordinator.showIdlePill()

        // The ambient island. One long-lived bottom-center panel that morphs
        // through the capture lifecycle (observing `meetingPillViewModel`) AND
        // into the expanded "Spotlight card" — clicking the nub grows it into the
        // card with the same animation as the hover. See docs/fork-product-model.md.
        let island: IslandController?
        if AppFeatures.islandReplacesDictationPill {
            let controller = earlyIslandController ?? IslandController(
                pillViewModel: meetingPillViewModel,
                idleVisible: settingsViewModel.showIdlePill
            )
            controller.onStop = {
                coordinatorRefs.meeting?.toggleRecording(trigger: .manual)
            }
            // The status dot / idle-bar click mirrors fn (mic-only by default).
            controller.onRecord = { mode in
                guard !callbacks.isOnboardingVisible() else { return }
                coordinatorRefs.meeting?.toggleRecording(trigger: .manual, sourceModeOverride: mode)
            }
            // The mark (and the done pill) opens the menu card (the second surface)
            // — except when the island is holding a failed-recording state, where
            // the click clears it back to idle AND opens a card carrying the
            // failure's actual text (the island's light is wordless; the card is
            // where the app says *why* — a failure must never be a silent vanish).
            controller.onOpenCard = {
                if let meeting = coordinatorRefs.meeting, meeting.isAwaitingFailureDismissal {
                    let message = meeting.heldFailureMessage
                        ?? "The last recording failed. Check the selected microphone and try again."
                    meeting.dismissFailure()
                    callbacks.onOpenErrorCard(message)
                } else {
                    callbacks.onOpenRecentCard()
                }
            }
            controller.show()
            coordinatorRefs.island = controller
            island = controller
        } else {
            island = nil
        }

        // Feed the island's talk-reactive recording glow the fast (~30 fps) live
        // audio level through its own isolated channel — the recording fast-poll
        // pushes here (see MeetingRecordingFlowCoordinator.onLiveAudioLevel →
        // IslandController.updateLiveAudioLevel → IslandChromeModel.liveLevel), so
        // the wash tracks your voice in real time instead of the 1 s pill cadence.
        meetingCoordinator.onLiveAudioLevel = { [weak island] level in
            island?.updateLiveAudioLevel(level)
        }

        // Dead ≠ silent: the coordinator's 1 s writer-health poll pushes whether
        // frames are actually arriving; while recording with a dead input the
        // island holds a motionless warning amber instead of failing (the old
        // 10 s stall guillotine is gone — silence never kills a recording).
        meetingCoordinator.onAudioAlive = { [weak island] alive in
            island?.updateAudioAlive(alive)
        }

        return Runtime(
            dictationFlowCoordinator: dictationCoordinator,
            meetingRecordingFlowCoordinator: meetingCoordinator,
            hotkeyCoordinator: hotkeyCoordinator,
            islandController: island
        )
    }

    func refreshLLMAvailability(in env: AppEnvironment) {
        let hasConfig = (try? env.llmConfigStore.loadConfig()) != nil
        let service: LLMService? = hasConfig ? env.llmService : nil
        transcriptionViewModel.updateLLMAvailability(hasConfig, llmService: service)
        chatViewModel.updateLLMService(service)
        promptResultsViewModel.updateLLMService(service)
        transformsViewModel.setHasLLMProvider(hasConfig)
        liveMeetingCoordinator?.updateLLMService(service)
    }
}

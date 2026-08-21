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
        /// True while the onboarding window is showing. Used to gate the real
        /// dictation flow so a hotkey press during onboarding (e.g. the "Learn
        /// the Hotkey" rehearsal, or a returning user whose taps are armed)
        /// can never start a real, model-less dictation.
        let isOnboardingVisible: () -> Bool
    }

    private let transcriptionViewModel: TranscriptionViewModel
    private let settingsViewModel: SettingsViewModel
    private let libraryViewModel: TranscriptionLibraryViewModel
    private let meetingPillViewModel: MeetingRecordingPillViewModel
    /// Created by AppDelegate before slow bootstrap so the idle cue is immediate.
    var earlyIslandController: IslandController?

    init(
        transcriptionViewModel: TranscriptionViewModel,
        settingsViewModel: SettingsViewModel,
        libraryViewModel: TranscriptionLibraryViewModel,
        meetingPillViewModel: MeetingRecordingPillViewModel
    ) {
        self.transcriptionViewModel = transcriptionViewModel
        self.settingsViewModel = settingsViewModel
        self.libraryViewModel = libraryViewModel
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

        transcriptionViewModel.configure(
            transcriptionService: env.transcriptionService,
            transcriptionRepo: env.transcriptionRepo
        )
        libraryViewModel.configure(transcriptionRepo: env.transcriptionRepo)
        settingsViewModel.configure(
            permissionService: env.permissionService,
            dictationRepo: env.dictationRepo,
            transcriptionRepo: env.transcriptionRepo,
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
            onPresentEntitlementsAlert: callbacks.onPresentEntitlementsAlert
        )
        coordinatorRefs.dictation = dictationCoordinator

        let meetingCoordinator = MeetingRecordingFlowCoordinator(
            meetingRecordingService: env.meetingRecordingService,
            transcriptionService: env.transcriptionService,
            permissionService: env.permissionService,
            transcriptionRepo: env.transcriptionRepo,
            sttManager: env.sttScheduler,
            meetingAudioSourceModeProvider: { env.runtimePreferences.meetingAudioSourceMode },
            pillViewModel: meetingPillViewModel,
            onMenuBarIconUpdate: { _ in callbacks.onMenuBarIconUpdate() },
            onTranscriptionReady: { [weak self] transcription in
                guard let self else { return }
                // Two-surface design: the finished meeting is saved and surfaces
                // in the recents card — no window is opened to display it.
                self.transcriptionViewModel.presentCompletedTranscription(transcription, autoSave: true)
                self.libraryViewModel.loadTranscriptions()
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
}

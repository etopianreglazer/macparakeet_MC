import AppKit
import SplayCore
import SplayViewModels

enum MeetingRecordingQuitState {
    case starting
    case recording
    case finishing
}

@MainActor
final class MeetingRecordingFlowCoordinator {
    var isMeetingRecordingActive: Bool {
        switch stateMachine.state {
        case .idle, .finishing:
            return false
        case .checkingPermissions, .starting, .recording, .stopping, .transcribing:
            return true
        }
    }

    var quitState: MeetingRecordingQuitState? {
        switch stateMachine.state {
        case .idle, .finishing:
            return nil
        case .checkingPermissions, .starting:
            return .starting
        case .recording:
            return .recording
        case .stopping, .transcribing:
            return .finishing
        }
    }

    private let meetingRecordingService: MeetingRecordingServiceProtocol
    private let transcriptionService: TranscriptionServiceProtocol
    private let permissionService: PermissionServiceProtocol
    private let transcriptionRepo: TranscriptionRepositoryProtocol
    private let sttManager: (any STTRuntimeManaging)?
    private let meetingAudioSourceModeProvider: @MainActor @Sendable () -> MeetingAudioSourceMode
    private let onMenuBarIconUpdate: (BreathWaveIcon.MenuBarState) -> Void
    private let onTranscriptionReady: (Transcription) -> Void
    private let onRecordingBegan: () -> Void
    private let onFlowReturnedToIdle: () -> Void
    /// Writes the finished transcript file. Throws when auto-save is on but the
    /// file could not be written; runs *before* the recovery lock is deleted and
    /// the island shows green, so green always means "the .md is on disk".
    private let saveTranscriptFile: @MainActor (Transcription) throws -> Void

    private var stateMachine = MeetingRecordingFlowStateMachine()
    private var pillController: MeetingRecordingPillController?
    /// Pushes the fast (~30 fps) live audio level to the ambient island's isolated
    /// glow channel while recording (wired to `IslandController.updateLiveAudioLevel`
    /// in `AppEnvironmentConfigurer`). Kept separate from the 1 s `pillViewModel`
    /// poll so the island's talk-reactive wash tracks your voice without relayout-
    /// churning the Transcribe tile that reads `pillViewModel.micLevel`.
    var onLiveAudioLevel: ((Float) -> Void)?
    /// Pushes "is audio actually arriving" (from the 1 s writer-health poll) to
    /// the island so a dead input shows as a motionless amber waiting light
    /// while recording — dead ≠ silent; the recording itself is never failed
    /// for silence. Wired to `IslandController.updateAudioAlive` in
    /// `AppEnvironmentConfigurer`.
    var onAudioAlive: ((Bool) -> Void)?
    /// Long-lived view model shared with the Transcribe-tab tile so the tile
    /// can render live recording state. Owned by `AppEnvironmentConfigurer`,
    /// passed in via init. Reset to `.idle` (not nilled) on flow teardown.
    private let pillViewModel: MeetingRecordingPillViewModel
    private var panelController: MeetingRecordingPanelController?
    private var panelViewModel: MeetingRecordingPanelViewModel?
    private var actionTask: Task<Void, Never>?
    private var pauseToggleTask: Task<Void, Never>?
    private var microphoneMuteToggleTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?
    private var pillPollingTask: Task<Void, Never>?
    private var pillGlowPollingTask: Task<Void, Never>?
    private var transcriptObservationTask: Task<Void, Never>?
    private var speechWarmUpObservationTask: Task<Void, Never>?
    private var lastPushedAudioAlive = true
    /// The full text of the failure the island is currently holding (see
    /// `isAwaitingFailureDismissal`), so the click that clears it can show the
    /// *why* in a card instead of discarding the message.
    private(set) var heldFailureMessage: String?
    /// What Retry would redo for the held failure: the recording is stopped and
    /// its audio + recovery lock are on disk. Nil when there is nothing to retry
    /// (start/capture failures, or stop itself failed).
    private var pendingRetry: MeetingRecordingFinisher.Step?
    private var activeFlowSettlementWaiters: [CheckedContinuation<Void, Never>] = []
    private var completedTranscription: Transcription?
    private var currentMeetingOperationContext: ObservabilityOperationContext?
    private var currentMeetingTrigger: TelemetryMeetingRecordingTrigger?
    private var pendingAudioSourceMode: MeetingAudioSourceMode?
    /// Per-gesture audio-source override (fork single/double-tap Fn). Consumed by
    /// the `.checkPermissions` effect; nil falls back to the user's Settings default.
    private var pendingAudioSourceModeOverride: MeetingAudioSourceMode?

    init(
        meetingRecordingService: MeetingRecordingServiceProtocol,
        transcriptionService: TranscriptionServiceProtocol,
        permissionService: PermissionServiceProtocol,
        transcriptionRepo: TranscriptionRepositoryProtocol,
        sttManager: (any STTRuntimeManaging)? = nil,
        meetingAudioSourceModeProvider: @escaping @MainActor @Sendable () -> MeetingAudioSourceMode = { .microphoneAndSystem },
        pillViewModel: MeetingRecordingPillViewModel,
        onMenuBarIconUpdate: @escaping (BreathWaveIcon.MenuBarState) -> Void,
        onTranscriptionReady: @escaping (Transcription) -> Void,
        onRecordingBegan: @escaping () -> Void = {},
        onFlowReturnedToIdle: @escaping () -> Void = {},
        saveTranscriptFile: @escaping @MainActor (Transcription) throws -> Void = { transcription in
            try AutoSaveService().save(transcription, scope: .meeting)
        }
    ) {
        self.meetingRecordingService = meetingRecordingService
        self.transcriptionService = transcriptionService
        self.permissionService = permissionService
        self.transcriptionRepo = transcriptionRepo
        self.sttManager = sttManager
        self.meetingAudioSourceModeProvider = meetingAudioSourceModeProvider
        self.pillViewModel = pillViewModel
        self.onMenuBarIconUpdate = onMenuBarIconUpdate
        self.onTranscriptionReady = onTranscriptionReady
        self.onRecordingBegan = onRecordingBegan
        self.onFlowReturnedToIdle = onFlowReturnedToIdle
        self.saveTranscriptFile = saveTranscriptFile
    }

    /// Trigger source for the *next* `.startRequested` event. Reset to nil
    /// after the start telemetry fires so subsequent toggles don't carry a
    /// stale trigger.
    private var pendingTrigger: TelemetryMeetingRecordingTrigger?

    /// Pre-set title for the *next* `.startRecording` effect. Paired with
    /// `pendingTrigger`: the `.startRecording` handler snapshots and clears
    /// both before the async hop. Manual / hotkey starts set only the trigger,
    /// so the service falls back to its date-based default title.
    private var pendingTitle: String?

    /// Pause / resume the in-flight recording. The state flip happens AFTER
    /// the service confirms — an optimistic flip before the await would race
    /// with the 150ms polling reconciler (which reads `captureMode` from the
    /// actor and could see `.full` while the spawned pause Task is still
    /// queued, then flip the pill back to `.recording`).
    ///
    /// Stale toggles are cancelled so a rapid pause/resume/pause sequence
    /// settles in the latest user intent rather than the order Tasks happen
    /// to be scheduled.
    func togglePause() {
        guard pillViewModel.canTogglePause else { return }
        let wantPause = !pillViewModel.isPaused
        pauseToggleTask?.cancel()
        pauseToggleTask = Task { @MainActor [meetingRecordingService, weak self] in
            if wantPause {
                await meetingRecordingService.pauseRecording()
            } else {
                await meetingRecordingService.resumeRecording()
            }
            guard !Task.isCancelled, let self else { return }
            // Only flip if the pill is still in a togglable state. A stop or
            // capture-failure that landed during the await may have moved
            // the pill to `.transcribing` / `.error`; we must not stomp it.
            guard self.pillViewModel.canTogglePause else { return }
            self.pillViewModel.state = wantPause ? .paused : .recording
            self.pillController?.refreshState()
            self.panelViewModel?.isPaused = wantPause
        }
    }

    func toggleMicrophoneMute() {
        guard panelViewModel?.canToggleMicrophoneMute == true else { return }
        let wantMuted = !(panelViewModel?.isMicrophoneMuted ?? false)
        microphoneMuteToggleTask?.cancel()
        microphoneMuteToggleTask = Task { @MainActor [meetingRecordingService, weak self] in
            let microphoneMuteState = await meetingRecordingService.setMicrophoneMuted(wantMuted)
            guard !Task.isCancelled, let self else { return }
            self.panelViewModel?.isMicrophoneMuted = microphoneMuteState.isMuted
            self.panelViewModel?.canToggleMicrophoneMute = microphoneMuteState.canMute
        }
    }

    @discardableResult
    func startRecording(
        title: String? = nil,
        trigger: TelemetryMeetingRecordingTrigger = .manual,
        sourceModeOverride: MeetingAudioSourceMode? = nil
    ) -> Int? {
        guard stateMachine.state == .idle else { return nil }
        pendingTrigger = pendingTrigger ?? trigger
        pendingTitle = title
        pendingAudioSourceModeOverride = sourceModeOverride
        currentMeetingOperationContext = ObservabilityOperationContext()
        sendEvent(.startRequested)
        return stateMachine.generation
    }

    func toggleRecording(
        trigger: TelemetryMeetingRecordingTrigger = .manual,
        sourceModeOverride: MeetingAudioSourceMode? = nil
    ) {
        switch stateMachine.state {
        case .idle:
            startRecording(trigger: trigger, sourceModeOverride: sourceModeOverride)
        case .recording, .starting, .stopping:
            sendEvent(.stopRequested)
        case .checkingPermissions, .transcribing, .finishing:
            break
        }
    }

    /// True while the island is holding a failed-recording state that does not
    /// auto-dismiss (`.captureFailed` and `.transcriptionFailed` in the state
    /// machine). The island's click routes here instead of opening the recents
    /// card: a non-retryable failure is cleared on click; a retryable one stays
    /// held until the user picks Retry or Dismiss on the card.
    var isAwaitingFailureDismissal: Bool {
        if case .finishing(outcome: .error) = stateMachine.state { return true }
        return false
    }

    /// Clear a held failed-recording state (user acknowledged it), returning the
    /// island to idle so the next recording can start.
    func dismissFailure() {
        guard isAwaitingFailureDismissal else { return }
        heldFailureMessage = nil
        pendingRetry = nil
        sendEvent(.dismissRequested)
    }

    /// True when the held failure is a stopped recording whose final step can be
    /// run again (the error card then offers Retry next to OK).
    var canRetryFailure: Bool {
        isAwaitingFailureDismissal && pendingRetry != nil
    }

    /// True when the held failure is a transcript that exists but whose file
    /// write failed (the card says "not saved"); false for a failed transcription.
    var heldFailureIsFileWrite: Bool {
        if case .save = pendingRetry { return true }
        return false
    }

    /// Run the failed final step again for the held recording.
    func retryFailure() {
        guard canRetryFailure else { return }
        heldFailureMessage = nil
        sendEvent(.retryRequested)
    }

    /// The final step for a stopped recording (`MeetingRecordingFinisher`:
    /// transcribe → write the file → delete the lock), mapped onto the flow.
    /// A failure holds a Retry-able error; the lock stays in place.
    private func finishStoppedRecording(
        _ step: MeetingRecordingFinisher.Step,
        isRetry: Bool,
        gen: Int,
        operationContext: ObservabilityOperationContext,
        liveWordCount: Int,
        liveTranscriptLagged: Bool
    ) async {
        let finisher = MeetingRecordingFinisher(
            meetingRecordingService: meetingRecordingService,
            transcriptionService: transcriptionService,
            transcriptionRepo: transcriptionRepo,
            saveTranscriptFile: saveTranscriptFile
        )
        let outcome = await Observability.withOperationContext(operationContext) {
            await finisher.finish(step, isRetry: isRetry)
        }
        let output: MeetingRecordingOutput = switch step {
        case .transcribe(let recording): recording
        case .save(_, let recording): recording
        }
        switch outcome {
        case .completed(let transcription):
            sendMeetingOperation(
                outcome: .success,
                output: output,
                stage: .completeTranscription,
                liveWordCount: liveWordCount,
                liveTranscriptLagged: liveTranscriptLagged
            )
            currentMeetingOperationContext = nil
            currentMeetingTrigger = nil
            completedTranscription = transcription
            sendEvent(.transcriptionCompleted(generation: gen, transcriptionID: transcription.id))
        case .failed(let error, let retry, let stage):
            pendingRetry = retry
            reportTranscriptionFailure(
                error,
                gen: gen,
                output: output,
                stage: stage == .transcription ? .transcription : .completeTranscription,
                liveWordCount: liveWordCount,
                liveTranscriptLagged: liveTranscriptLagged
            )
        }
    }

    private func reportTranscriptionFailure(
        _ error: Error,
        gen: Int,
        output: MeetingRecordingOutput?,
        stage: TelemetryMeetingOperationStage,
        liveWordCount: Int,
        liveTranscriptLagged: Bool
    ) {
        Telemetry.send(.meetingRecordingFailed(
            errorType: TelemetryErrorClassifier.classify(error),
            errorDetail: TelemetryErrorClassifier.errorDetail(error)
        ))
        sendMeetingOperation(
            outcome: .failure,
            output: output,
            stage: stage,
            liveWordCount: liveWordCount,
            liveTranscriptLagged: liveTranscriptLagged,
            errorType: TelemetryErrorClassifier.classify(error)
        )
        currentMeetingOperationContext = nil
        currentMeetingTrigger = nil
        sendEvent(.transcriptionFailed(generation: gen, message: error.localizedDescription))
    }

    func stopRecordingAndWaitForCompletion() async {
        switch stateMachine.state {
        case .checkingPermissions, .starting:
            sendEvent(.cancelRequested)
        default:
            sendEvent(.stopRequested)
        }
        await waitForActiveFlowToSettle()
        if let actionTask {
            await actionTask.value
        }
    }

    func discardRecordingAndWaitForCompletion() async {
        sendEvent(.cancelRequested)
        await waitForActiveFlowToSettle()
        if let actionTask {
            await actionTask.value
        }
    }

    /// Discard the pending start context (trigger + title) when the start
    /// sequence exits without ever reaching the `.startRecording` effect —
    /// today, only the permissions-denied path. The `.startRecording`
    /// effect handler clears these inline because it needs to snapshot
    /// them first to fire telemetry; this helper is for the paths that
    /// bail out earlier.
    private func clearPendingStartContext(failureReason: String) {
        sendMeetingOperation(
            outcome: .unavailable,
            trigger: pendingTrigger,
            stage: .permissions,
            errorType: failureReason
        )
        pendingTrigger = nil
        pendingTitle = nil
        pendingAudioSourceMode = nil
        pendingAudioSourceModeOverride = nil
        currentMeetingOperationContext = nil
        currentMeetingTrigger = nil
    }

    private func waitForActiveFlowToSettle() async {
        while isMeetingRecordingActive {
            await withCheckedContinuation { continuation in
                activeFlowSettlementWaiters.append(continuation)
            }
        }
    }

    private func sendEvent(_ event: MeetingRecordingFlowEvent) {
        let effects = stateMachine.handle(event)
        executeEffects(effects)
        resumeActiveFlowSettlementWaitersIfNeeded()
    }

    private func resumeActiveFlowSettlementWaitersIfNeeded() {
        guard !isMeetingRecordingActive, !activeFlowSettlementWaiters.isEmpty else { return }
        let waiters = activeFlowSettlementWaiters
        activeFlowSettlementWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func executeEffects(_ effects: [MeetingRecordingFlowEffect]) {
        for effect in effects {
            executeEffect(effect)
        }
    }

    private func executeEffect(_ effect: MeetingRecordingFlowEffect) {
        switch effect {
        case .checkPermissions:
            let gen = stateMachine.generation
            actionTask = Task { @MainActor in
                let sourceMode = self.pendingAudioSourceModeOverride ?? meetingAudioSourceModeProvider()
                self.pendingAudioSourceModeOverride = nil
                self.pendingAudioSourceMode = sourceMode
                let microphoneGranted: Bool
                let microphonePrompted: Bool
                if sourceMode.capturesMicrophone {
                    let microphoneStatus = await permissionService.checkMicrophonePermission()
                    switch microphoneStatus {
                    case .granted:
                        microphoneGranted = true
                        microphonePrompted = false
                    case .denied:
                        microphoneGranted = false
                        microphonePrompted = false
                    case .notDetermined:
                        Telemetry.send(.permissionPrompted(permission: .microphone))
                        microphonePrompted = true
                        microphoneGranted = await permissionService.requestMicrophonePermission()
                    }
                } else {
                    microphoneGranted = true
                    microphonePrompted = false
                }

                if !microphoneGranted {
                    if microphonePrompted {
                        Telemetry.send(.permissionDenied(permission: .microphone))
                    }
                    self.clearPendingStartContext(failureReason: "permission_denied")
                    self.sendEvent(.permissionsDenied(generation: gen, reason: .microphone))
                    return
                }
                if microphonePrompted {
                    Telemetry.send(.permissionGranted(permission: .microphone))
                }

                // Mic-only recordings never touch ScreenCaptureKit, so skip the
                // screen-recording permission entirely (single-tap Fn capture).
                if sourceMode.capturesSystemAudio {
                    let existingScreenGrant = permissionService.checkScreenRecordingPermission()
                    if !existingScreenGrant {
                        Telemetry.send(.permissionPrompted(permission: .screenRecording))
                    }
                    let screenGranted = existingScreenGrant || permissionService.requestScreenRecordingPermission()
                    if !screenGranted {
                        Telemetry.send(.permissionDenied(permission: .screenRecording))
                        self.clearPendingStartContext(failureReason: "permission_denied")
                        self.sendEvent(.permissionsDenied(generation: gen, reason: .screenRecording))
                        return
                    }
                    if !existingScreenGrant {
                        Telemetry.send(.permissionGranted(permission: .screenRecording))
                    }
                }
                self.sendEvent(.permissionsGranted(generation: gen))
            }

        case .showRecordingPill:
            let vm = pillViewModel
            vm.onStop = { [weak self] in self?.toggleRecording() }
            vm.onPauseToggle = { [weak self] in self?.togglePause() }
            vm.elapsedSeconds = 0
            vm.micLevel = 0
            vm.systemLevel = 0
            vm.state = .recording
            let panelVM = panelViewModel ?? MeetingRecordingPanelViewModel()
            panelVM.state = .recording
            panelVM.elapsedSeconds = 0
            panelVM.micLevel = 0
            panelVM.systemLevel = 0
            panelVM.isPaused = false
            panelVM.isMicrophoneMuted = false
            panelVM.canToggleMicrophoneMute = (pendingAudioSourceMode ?? meetingAudioSourceModeProvider()).capturesMicrophone
            panelVM.updateLiveTranscriptStatus(.startingAudio)
            panelVM.updatePreviewLines([], isTranscriptionLagging: false)
            panelVM.onStop = { [weak self] in self?.toggleRecording() }
            panelVM.onPauseToggle = { [weak self] in self?.togglePause() }
            panelVM.onMicrophoneMuteToggle = { [weak self] in self?.toggleMicrophoneMute() }
            panelVM.onClose = { [weak self] in self?.hideMeetingPanel() }
            // Wire the notepad's debounced persistence target through the
            // recording service. The service serializes lock-file writes and
            // carries the latest notes into MeetingRecordingOutput.userNotes,
            // where TranscriptionService persists them onto the Transcription
            // (ADR-020 §8, §10). The "Memo-Steered Notes" built-in prompt that
            // originally consumed these notes was reverted on 2026-05-02; the
            // notes themselves and the {{userNotes}} template variable remain
            // available for custom prompts.
            panelVM.notesViewModel.bindPersist { [weak self] notes in
                await self?.meetingRecordingService.updateNotes(notes)
            }
            panelViewModel = panelVM

            // Fork: when the ambient island is active it owns the floating
            // recording UI (driven off this same `vm`), so the right-center
            // sacred-geometry meeting pill is suppressed to avoid two pills.
            // The shared `vm` and all polling below are unchanged — the island
            // reads state/elapsed from it.
            if !AppFeatures.islandReplacesDictationPill {
                if pillController == nil {
                    pillController = MeetingRecordingPillController(viewModel: vm)
                }
                pillController?.onClick = { [weak self] in
                    self?.showMeetingPanel()
                }
                pillController?.onStopRecording = { [weak self] in
                    self?.sendEvent(.stopRequested)
                }
                pillController?.onOpenApp = { [weak self] in
                    NSApp.activate(ignoringOtherApps: true)
                    self?.showMeetingPanel()
                }
                pillController?.onCancelRecording = { [weak self] in
                    self?.confirmAndCancelRecording()
                }
                pillController?.onPauseToggle = { [weak self] in
                    self?.togglePause()
                }
            }
            if panelController == nil {
                let controller = MeetingRecordingPanelController(viewModel: panelVM)
                controller.onCloseRequested = { [weak self] in
                    self?.hideMeetingPanel()
                }
                panelController = controller
            }
            pillController?.show()
            startSpeechWarmUpObservation()
            startPillPolling()
            startPillGlowPolling()
            startTranscriptObservation()

        case .startRecording:
            let gen = stateMachine.generation
            // Snapshot + clear before the async hop so a subsequent toggle
            // can't smuggle a stale trigger / title into this start.
            let trigger = pendingTrigger
            let title = pendingTitle
            let sourceMode = pendingAudioSourceMode ?? meetingAudioSourceModeProvider()
            pendingTrigger = nil
            pendingTitle = nil
            pendingAudioSourceMode = nil
            let operationContext = currentMeetingOperationContext ?? ObservabilityOperationContext()
            currentMeetingOperationContext = operationContext
            currentMeetingTrigger = trigger
            actionTask = Task { @MainActor in
                do {
                    try await meetingRecordingService.startRecording(title: title, sourceMode: sourceMode)
                    let isSpeechModelReady = await self.sttManager?.isReady() ?? true
                    switch self.panelViewModel?.liveTranscriptStatus {
                    case .some(.startingAudio) where isSpeechModelReady:
                        self.panelViewModel?.updateLiveTranscriptStatus(.listening)
                    case .some(.startingAudio):
                        self.panelViewModel?.updateLiveTranscriptStatus(.preparingSpeechModel(message: nil))
                    case .some(.preparingSpeechModel) where isSpeechModelReady:
                        self.panelViewModel?.updateLiveTranscriptStatus(.listening)
                    case .some(.listening), .some(.live), .some(.previewUnavailable), .none:
                        break
                    case .some(.preparingSpeechModel):
                        break
                    }
                    Telemetry.send(.meetingRecordingStarted(trigger: trigger))
                    self.onRecordingBegan()
                    self.sendEvent(.recordingStarted(generation: gen))
                } catch {
                    Telemetry.send(.meetingRecordingFailed(
                        errorType: TelemetryErrorClassifier.classify(error),
                        errorDetail: TelemetryErrorClassifier.errorDetail(error)
                    ))
                    self.sendMeetingOperation(
                        outcome: .failure,
                        trigger: trigger,
                        stage: .startRecording,
                        errorType: TelemetryErrorClassifier.classify(error)
                    )
                    self.currentMeetingOperationContext = nil
                    self.currentMeetingTrigger = nil
                    self.sendEvent(.startFailed(generation: gen, message: error.localizedDescription))
                }
            }

        case .showTranscribingState:
            stopPillPolling()
            stopTranscriptObservation()
            stopSpeechWarmUpObservation()
            pillViewModel.micLevel = 0
            pillViewModel.systemLevel = 0
            pillViewModel.state = .completing
            pillController?.refreshState()
            pillViewModel.onCompletionAnimationFinished = { [weak self] in
                guard let self, self.pillViewModel.state == .completing else { return }
                // Flower collapsed — show merkaba spinner (or checkmark if already done)
                if self.completedTranscription != nil {
                    self.pillViewModel.state = .completed
                    // Auto-dismiss was skipped during collapse — start it now
                    self.autoDismissTask?.cancel()
                    let gen = self.stateMachine.generation
                    self.autoDismissTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        self?.sendEvent(.autoDismissExpired(generation: gen))
                    }
                } else {
                    self.pillViewModel.state = .transcribing
                }
                self.pillController?.refreshState()
            }
            // Fork: the sacred-geometry pill is what normally drives the collapse
            // animation's completion callback (advancing .completing → spinner /
            // checkmark). With the island active that pill is suppressed, so
            // nothing would fire it and the island would stick on "Wrapping up…".
            // Advance it on a short timer that stands in for the collapse beat.
            if AppFeatures.islandReplacesDictationPill {
                let advance = pillViewModel.onCompletionAnimationFinished
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(360))
                    advance?()
                }
            }
            panelViewModel?.state = .transcribing
            panelViewModel?.micLevel = 0
            panelViewModel?.systemLevel = 0
            hideMeetingPanel()

        case .stopRecordingAndTranscribe:
            let gen = stateMachine.generation
            let liveWordCount = panelViewModel?.wordCount ?? 0
            let liveTranscriptLagged = panelViewModel?.isTranscriptionLagging ?? false
            let notesVM = panelViewModel?.notesViewModel
            let operationContext = currentMeetingOperationContext ?? ObservabilityOperationContext()
            currentMeetingOperationContext = operationContext
            pendingRetry = nil
            actionTask = Task { @MainActor in
                let output: MeetingRecordingOutput
                do {
                    output = try await Observability.withOperationContext(operationContext) {
                        // Flush any keystrokes typed in the last < 250 ms so
                        // they make it onto the lock file and into the saved
                        // Transcription.userNotes (ADR-020 §8).
                        await notesVM?.commit()
                        let output = try await meetingRecordingService.stopRecording()
                        Telemetry.send(.meetingRecordingCompleted(
                            durationSeconds: output.durationSeconds,
                            liveWordCount: liveWordCount,
                            liveTranscriptLagged: liveTranscriptLagged
                        ))
                        return output
                    }
                } catch {
                    // Nothing stopped cleanly, so there is nothing to retry in
                    // this session; the recovery lock (if any) is picked up on
                    // the next launch.
                    self.reportTranscriptionFailure(
                        error,
                        gen: gen,
                        output: nil,
                        stage: .stopRecording,
                        liveWordCount: liveWordCount,
                        liveTranscriptLagged: liveTranscriptLagged
                    )
                    return
                }
                await self.finishStoppedRecording(
                    .transcribe(output),
                    isRetry: false,
                    gen: gen,
                    operationContext: operationContext,
                    liveWordCount: liveWordCount,
                    liveTranscriptLagged: liveTranscriptLagged
                )
            }

        case .retryTranscription:
            guard let retry = pendingRetry else { return }
            pendingRetry = nil
            let gen = stateMachine.generation
            let operationContext = currentMeetingOperationContext ?? ObservabilityOperationContext()
            currentMeetingOperationContext = operationContext
            AudioCaptureDiagnostics.append("meeting_recording_retry_requested")
            actionTask = Task { @MainActor in
                await self.finishStoppedRecording(
                    retry,
                    isRetry: true,
                    gen: gen,
                    operationContext: operationContext,
                    liveWordCount: 0,
                    liveTranscriptLagged: false
                )
            }

        case .finalizeFailedCapture:
            // `failCapture` has already stopped the OS streams. Finalize the
            // writer so the partial audio and its recovery lock are usable,
            // but intentionally do not invoke transcription or publish a
            // normal completion. The visible error makes the interruption
            // explicit and Library/recovery can handle the retained files.
            actionTask = Task { @MainActor [meetingRecordingService] in
                do {
                    _ = try await meetingRecordingService.stopRecording()
                } catch {
                    // There may be no usable audio at all. The user-facing
                    // error is already displayed; this simply prevents a
                    // failed writer from keeping the next recording blocked.
                }
            }

        case .showCompleted:
            stopPillPolling()
            stopTranscriptObservation()
            stopSpeechWarmUpObservation()
            // If flower is still collapsing, the callback will check completedTranscription
            // If spinner is showing, transition to checkmark now
            if pillViewModel.state == .transcribing {
                pillViewModel.state = .completed
                pillController?.refreshState()
            }
            panelViewModel?.state = .hidden

        case .cancelRecording:
            let durationSeconds = Double(panelViewModel?.elapsedSeconds ?? 0)
            let notesVM = panelViewModel?.notesViewModel
            let cancelledTrigger = currentMeetingTrigger ?? pendingTrigger
            pendingTrigger = nil
            pendingTitle = nil
            pendingAudioSourceMode = nil
            actionTask?.cancel()
            actionTask = Task { @MainActor in
                // Stop the in-flight debounce so it can't fire against a
                // session folder that cancelRecording is about to delete.
                // The notes themselves are intentionally discarded with
                // the rest of the cancelled recording — symmetric with
                // .stopRecordingAndTranscribe's commit() call.
                await notesVM?.commit()
                await meetingRecordingService.cancelRecording()
                Telemetry.send(.meetingRecordingCancelled(durationSeconds: durationSeconds))
                self.sendMeetingOperation(
                    outcome: .cancelled,
                    trigger: cancelledTrigger,
                    stage: .cancel,
                    durationSeconds: durationSeconds
                )
                self.currentMeetingOperationContext = nil
                self.currentMeetingTrigger = nil
            }

        case .showError(let message):
            // Hold the full text: the island's failed light is wordless, so the
            // click that dismisses it opens a card carrying this message.
            heldFailureMessage = message
            // Real-time audible cue so a recording failure is never silent —
            // the user is often away from the screen (walking-around dictation)
            // when a cold Bluetooth mic yields nothing. Separate from the
            // (off-by-default) start sound; gated only by the macOS
            // "play sound effects" setting inside SoundManager.
            SoundManager.shared.play(.errorSoft)
            stopPillPolling()
            stopTranscriptObservation()
            stopSpeechWarmUpObservation()
            panelViewModel?.state = .error(message)
            pillViewModel.state = .error(
                panelViewModel?.compactErrorRecoveryMessage
                    ?? "Meeting interrupted. Open Library to retry transcription or export captured audio."
            )
            pillController?.refreshState()
            hideMeetingPanel()

        case .hidePill:
            stopPillPolling()
            stopTranscriptObservation()
            stopSpeechWarmUpObservation()
            pauseToggleTask?.cancel()
            pauseToggleTask = nil
            microphoneMuteToggleTask?.cancel()
            microphoneMuteToggleTask = nil
            pillController?.hide()
            pillController = nil
            // Pill view model is long-lived (also drives the Transcribe-tab
            // tile), so we reset its state instead of nilling it. Callbacks
            // on the VM are owned by the flow coordinator and re-bound on
            // the next `.showRecordingPill` action.
            pillViewModel.onStop = nil
            pillViewModel.onPauseToggle = nil
            pillViewModel.onCompletionAnimationFinished = nil
            pillViewModel.elapsedSeconds = 0
            pillViewModel.micLevel = 0
            pillViewModel.systemLevel = 0
            pillViewModel.state = .idle
            panelController?.close()
            panelController = nil
            panelViewModel = nil
            completedTranscription = nil
            onFlowReturnedToIdle()

        case .updateMenuBar(let state):
            let iconState: BreathWaveIcon.MenuBarState = switch state {
            case .idle: .idle
            case .recording: .recording
            case .processing: .processing
            }
            onMenuBarIconUpdate(iconState)

        case .navigateToTranscription(let id):
            guard completedTranscription?.id == id, let transcription = completedTranscription else { return }
            onTranscriptionReady(transcription)

        case .presentPermissionAlert(let reason):
            onFlowReturnedToIdle()
            presentPermissionAlert(for: reason)

        case .startAutoDismissTimer(let seconds):
            // Skip auto-dismiss when flower collapse animation is still playing
            if pillViewModel.state == .completing {
                break
            }
            // Give checkmark time to animate in and hold before dismissing
            let adjustedSeconds = pillViewModel.state == .completed ? 2.0 : seconds
            autoDismissTask?.cancel()
            let gen = stateMachine.generation
            autoDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(adjustedSeconds))
                guard !Task.isCancelled else { return }
                self.sendEvent(.autoDismissExpired(generation: gen))
            }

        case .cancelAutoDismissTimer:
            autoDismissTask?.cancel()
            autoDismissTask = nil
        }
    }

    private func confirmAndCancelRecording() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard Recording?"
        alert.informativeText = "This will stop the meeting recording and delete all captured audio. This cannot be undone."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Keep Recording")
        alert.buttons.first?.hasDestructiveAction = true

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            sendEvent(.cancelRequested)
        }
    }

    private func presentPermissionAlert(for reason: MeetingRecordingPermissionFailure) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        switch reason {
        case .microphone:
            alert.messageText = "Microphone Access Required"
            alert.informativeText = "Meeting recording needs microphone access to capture your voice."
        case .screenRecording:
            alert.messageText = "Screen Recording Access Required"
            alert.informativeText = "Meeting recording needs Screen & System Audio Recording access to capture system audio."
        }
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openSystemSettings(for: reason)
        }
    }

    private func startPillPolling() {
        pillPollingTask?.cancel()
        pillPollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let micLevel = Self.displayLevel(await meetingRecordingService.micLevel)
                let systemLevel = Self.displayLevel(await meetingRecordingService.systemLevel)
                let elapsedSeconds = await meetingRecordingService.elapsedSeconds
                let captureMode = await meetingRecordingService.captureMode
                let captureHealth = await meetingRecordingService.captureHealth
                let microphoneMuteState = await meetingRecordingService.microphoneMuteState

                guard !Task.isCancelled else { break }
                if pillViewModel.micLevel != micLevel {
                    pillViewModel.micLevel = micLevel
                }
                if pillViewModel.systemLevel != systemLevel {
                    pillViewModel.systemLevel = systemLevel
                }
                if pillViewModel.elapsedSeconds != elapsedSeconds {
                    pillViewModel.elapsedSeconds = elapsedSeconds
                }
                if let panelViewModel {
                    if panelViewModel.elapsedSeconds != elapsedSeconds {
                        panelViewModel.elapsedSeconds = elapsedSeconds
                    }
                    // While actively recording the panel orbs are driven by the
                    // fast (~30 fps) glow loop; this 1 s loop only settles them
                    // (→ 0) when paused/stopped so they don't freeze on the last
                    // live frame. Writing levels here every second while recording
                    // would also visibly fight the fast loop's smoother updates.
                    if captureMode != .full {
                        if panelViewModel.micLevel != micLevel {
                            panelViewModel.micLevel = micLevel
                        }
                        if panelViewModel.systemLevel != systemLevel {
                            panelViewModel.systemLevel = systemLevel
                        }
                    }
                    if panelViewModel.isMicrophoneMuted != microphoneMuteState.isMuted {
                        panelViewModel.isMicrophoneMuted = microphoneMuteState.isMuted
                    }
                    if panelViewModel.canToggleMicrophoneMute != microphoneMuteState.canMute {
                        panelViewModel.canToggleMicrophoneMute = microphoneMuteState.canMute
                    }
                }
                // Pause/resume reconciliation (issue #235). The user-facing
                // toggle does an optimistic flip; this poll is the
                // authoritative source if the optimistic flip diverged from
                // the service (e.g., capture failed before the service saw
                // the pause call). Only flip pillViewModel.state between
                // .recording and .paused — never override .completing /
                // .transcribing / .completed / .error from here.
                let serviceIsPaused = (captureMode == .paused)
                if pillViewModel.state == .recording, serviceIsPaused {
                    pillViewModel.state = .paused
                } else if pillViewModel.state == .paused, !serviceIsPaused, captureMode == .full {
                    pillViewModel.state = .recording
                }
                panelViewModel?.isPaused = serviceIsPaused
                if captureMode == .stopped,
                   stateMachine.state == .recording,
                   pillViewModel.state == .recording || pillViewModel.state == .paused {
                    failActiveCapture(message: "Meeting recording stopped unexpectedly. Captured audio was kept for recovery; it was not transcribed as a completed meeting.")
                    break
                }

                // Dead ≠ silent (Talkify's doctrine, adopted 2026-08-17): a mic
                // that stops delivering buffers is *shown* — the island's light
                // holds a motionless warning amber — never killed. The old 10 s
                // "stall" guillotine lived here; it raced cold-Bluetooth mics
                // (AirPods take ~10 s of HFP warm-up before the first buffer)
                // and deleted the very session it claimed to protect. Recovery
                // is automatic: the moment frames flow again the light goes red.
                updateAudioAliveness(
                    captureHealth,
                    isActivelyRecording: captureMode == .full
                        && stateMachine.state == .recording
                        && pillViewModel.state == .recording
                )

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Startup grace before silence can read as "dead": a healthy engine lands
    /// its first buffer well under a second, so a 2 s grace never ambers a
    /// normal start, while a cold Bluetooth route goes amber quickly enough to
    /// explain itself live.
    private static let audioAliveStartupGrace: TimeInterval = 2
    /// How stale the last successful append may be before the audio counts as
    /// dead. The poll runs at 1 Hz, so 2 s tolerates one missed tick.
    private static let audioAliveStaleAfter: TimeInterval = 2

    /// Derive "is audio actually arriving" from writer health and push changes
    /// to the island's amber waiting light. Purely visual — never fails the
    /// recording; silence is not a failure (see the poll comment above).
    private func updateAudioAliveness(_ health: MeetingCaptureHealth, isActivelyRecording: Bool, now: Date = Date()) {
        let alive: Bool
        if !isActivelyRecording {
            // Paused / stopping / transcribing: settle back to the normal light.
            alive = true
        } else if let startedAt = health.startedAt,
                  now.timeIntervalSince(startedAt) < Self.audioAliveStartupGrace {
            alive = true
        } else if let lastWrite = health.lastSuccessfulWriteAt,
                  now.timeIntervalSince(lastWrite) < Self.audioAliveStaleAfter {
            alive = true
        } else if health.startedAt == nil {
            // No session baseline to judge against — don't amber on unknowns.
            alive = true
        } else {
            alive = false
        }
        guard alive != lastPushedAudioAlive else { return }
        lastPushedAudioAlive = alive
        AudioCaptureDiagnostics.append("meeting_audio_alive=\(alive)")
        onAudioAlive?(alive)
    }

    private func failActiveCapture(message: String) {
        pillViewModel.micLevel = 0
        pillViewModel.systemLevel = 0
        panelViewModel?.micLevel = 0
        panelViewModel?.systemLevel = 0
        sendEvent(.captureFailed(generation: stateMachine.generation, message: message))
    }

    private static func displayLevel(_ level: Float) -> Float {
        let clamped = min(1, max(0, level))
        return (clamped * 20).rounded() / 20
    }

    /// Fast (~30 fps) audio channel for the live, near-real-time visualizers.
    /// Deliberately separate from `startPillPolling` (1 s): that loop writes the
    /// `@Observable` props (elapsed, state, mute) that fan out to the *whole*
    /// panel/tile body, so speeding it up would re-trigger the per-tick relayout
    /// this PR fixed. This loop only touches surfaces where a level change is
    /// cheap — the pill rosette's `CALayer` opacity (no `@Observable` at all) and
    /// the panel's `DualAudioOrbView`, whose read is isolated in the `LiveAudioOrb`
    /// leaf so only the 20pt orb re-renders. Runs only while actively recording
    /// (paused/processing states rest dim).
    private func startPillGlowPolling() {
        pillGlowPollingTask?.cancel()
        pillGlowPollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if pillViewModel.state == .recording {
                    let mic = await meetingRecordingService.micLevel
                    let system = await meetingRecordingService.systemLevel
                    guard !Task.isCancelled else { break }
                    // Floating pill rosette: straight to CALayer opacity.
                    pillController?.updateLiveAudioLevel(max(mic, system))
                    // Ambient island: the same fast level via its isolated glow
                    // channel, so the recording wash tracks your voice in real time.
                    onLiveAudioLevel?(max(mic, system))
                    // Panel orbs: quantized + change-gated, so a write (and the
                    // leaf re-render it triggers) fires only on a visible step.
                    if let panelViewModel {
                        let micQ = Self.displayLevel(mic)
                        let systemQ = Self.displayLevel(system)
                        if panelViewModel.micLevel != micQ {
                            panelViewModel.micLevel = micQ
                        }
                        if panelViewModel.systemLevel != systemQ {
                            panelViewModel.systemLevel = systemQ
                        }
                    }
                } else {
                    // Not actively recording: settle the island glow to silence.
                    onLiveAudioLevel?(0)
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopPillGlowPolling() {
        pillGlowPollingTask?.cancel()
        pillGlowPollingTask = nil
    }

    private func stopPillPolling() {
        pillPollingTask?.cancel()
        pillPollingTask = nil
        stopPillGlowPolling()
        // The health poll is what maintains the amber waiting light; once it
        // stops, settle the island back to alive so amber can't stick around.
        if !lastPushedAudioAlive {
            lastPushedAudioAlive = true
            onAudioAlive?(true)
        }
    }

    private func startTranscriptObservation() {
        transcriptObservationTask?.cancel()
        transcriptObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await meetingRecordingService.transcriptUpdates
            for await update in stream {
                guard !Task.isCancelled else { break }
                let previewLines = await Task.detached(priority: .utility) {
                    Self.makePreviewLines(from: update)
                }.value
                guard !Task.isCancelled else { break }
                panelViewModel?.updatePreviewLines(
                    previewLines,
                    isTranscriptionLagging: update.isTranscriptionLagging
                )
            }
        }
    }

    private func stopTranscriptObservation() {
        transcriptObservationTask?.cancel()
        transcriptObservationTask = nil
    }

    private func startSpeechWarmUpObservation() {
        guard let sttManager else { return }

        speechWarmUpObservationTask?.cancel()
        speechWarmUpObservationTask = Task { @MainActor [weak self, sttManager] in
            let (observerId, stream) = await sttManager.observeWarmUpProgress()
            defer {
                Task {
                    await sttManager.removeWarmUpObserver(id: observerId)
                }
            }

            await sttManager.backgroundWarmUp()

            for await state in stream {
                guard !Task.isCancelled else { break }
                self?.handleSpeechWarmUpState(state)
            }
        }
    }

    private func stopSpeechWarmUpObservation() {
        speechWarmUpObservationTask?.cancel()
        speechWarmUpObservationTask = nil
    }

    private func handleSpeechWarmUpState(_ state: STTWarmUpState) {
        guard let panelViewModel, panelViewModel.previewLines.isEmpty else { return }

        switch state {
        case .idle:
            break
        case .working(let message, _):
            panelViewModel.updateLiveTranscriptStatus(.preparingSpeechModel(message: message))
        case .ready:
            if stateMachine.state != .starting {
                panelViewModel.updateLiveTranscriptStatus(.listening)
            }
        case .failed:
            panelViewModel.updateLiveTranscriptStatus(.previewUnavailable)
        }
    }

    nonisolated private static func makePreviewLines(from update: MeetingTranscriptUpdate) -> [MeetingRecordingPreviewLine] {
        let speakerLabels = Dictionary(uniqueKeysWithValues: update.speakers.map { ($0.id, $0.label) })
        let segments = TranscriptSegmenter.groupIntoSegments(words: update.words)
        return segments.map { segment in
            let source = segment.speakerId.flatMap(AudioSource.init(rawValue:))
            return MeetingRecordingPreviewLine(
                id: "\(segment.startMs)-\(segment.speakerId ?? "unknown")",
                timestamp: format(milliseconds: segment.startMs),
                speakerLabel: speakerLabels[segment.speakerId ?? ""] ?? source?.displayLabel ?? "Speaker",
                text: segment.text,
                source: source
            )
        }
    }

    nonisolated private static func format(milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func openSystemSettings(for reason: MeetingRecordingPermissionFailure) {
        switch reason {
        case .microphone:
            permissionService.openMicrophoneSettings()
        case .screenRecording:
            permissionService.openScreenRecordingSettings()
        }
    }

    private func showMeetingPanel() {
        switch stateMachine.state {
        case .starting, .recording:
            break
        case .idle, .checkingPermissions, .stopping, .transcribing, .finishing:
            return
        }
        panelController?.show()
    }

    private func hideMeetingPanel() {
        panelController?.hide()
    }

    private func sendMeetingOperation(
        outcome: ObservabilityOutcome,
        trigger: TelemetryMeetingRecordingTrigger? = nil,
        output: MeetingRecordingOutput? = nil,
        stage: TelemetryMeetingOperationStage? = nil,
        durationSeconds: Double? = nil,
        liveWordCount: Int? = nil,
        liveTranscriptLagged: Bool? = nil,
        errorType: String? = nil
    ) {
        guard let operationContext = currentMeetingOperationContext else { return }
        let notes = output?.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        Telemetry.send(.meetingOperation(
            operationID: operationContext.operationID,
            operationContext: operationContext,
            outcome: outcome,
            trigger: trigger ?? currentMeetingTrigger,
            stage: stage,
            durationSeconds: output?.durationSeconds ?? durationSeconds,
            liveWordCount: liveWordCount,
            liveTranscriptLagged: liveTranscriptLagged,
            microphoneTrackPresent: output.map { $0.sourceAlignment.microphone != nil },
            systemTrackPresent: output.map { $0.sourceAlignment.system != nil },
            notesUsed: notes.map { !$0.isEmpty },
            notesLengthBucket: output.map { Observability.textLengthBucket($0.userNotes) },
            errorType: errorType
        ))
    }
}

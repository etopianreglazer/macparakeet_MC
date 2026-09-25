import Foundation

public enum MeetingRecordingPermissionFailure: Equatable, Sendable {
    case microphone
    case screenRecording
}

public enum MeetingRecordingFlowState: Equatable, Sendable {
    case idle
    case checkingPermissions
    case starting
    case recording
    case stopping
    case transcribing
    case finishing(outcome: MeetingRecordingFlowFinishOutcome)
}

public enum MeetingRecordingFlowFinishOutcome: Equatable, Sendable {
    case completed(UUID)
    case error(String)
}

public enum MeetingRecordingFlowEvent: Equatable, Sendable {
    case startRequested
    case permissionsGranted(generation: Int)
    case permissionsDenied(generation: Int, reason: MeetingRecordingPermissionFailure)
    case recordingStarted(generation: Int)
    case startFailed(generation: Int, message: String)
    case stopRequested
    case cancelRequested
    /// Emitted by the recording health loop when capture stops or stalls.
    /// This is deliberately distinct from a user-requested stop: incomplete
    /// audio is retained for recovery, but must never appear as a normal,
    /// completed transcription.
    case captureFailed(generation: Int, message: String)
    case transcriptionCompleted(generation: Int, transcriptionID: UUID)
    case transcriptionFailed(generation: Int, message: String)
    /// User chose Retry on a held failure whose recording is still on disk.
    /// The coordinator only sends this when it holds something to retry.
    case retryRequested
    case dismissRequested
    case autoDismissExpired(generation: Int)
}

public enum MeetingRecordingFlowEffect: Equatable, Sendable {
    case checkPermissions
    case showRecordingPill
    case startRecording
    case showTranscribingState
    case stopRecordingAndTranscribe
    /// Re-run the failed final step (transcribe and/or write the file) for the
    /// recording that is already stopped and on disk.
    case retryTranscription
    case finalizeFailedCapture
    case showCompleted
    case showError(String)
    case cancelRecording
    case hidePill
    case updateMenuBar(DictationFlowMenuBarState)
    case navigateToTranscription(UUID)
    case presentPermissionAlert(MeetingRecordingPermissionFailure)
    case startAutoDismissTimer(seconds: Double)
    case cancelAutoDismissTimer
}

public struct MeetingRecordingFlowStateMachine: Equatable, Sendable {
    public private(set) var state: MeetingRecordingFlowState = .idle
    public private(set) var generation: Int = 0

    public init() {}

    public mutating func handle(_ event: MeetingRecordingFlowEvent) -> [MeetingRecordingFlowEffect] {
        switch (state, event) {
        case (.idle, .startRequested):
            generation += 1
            state = .checkingPermissions
            return [.checkPermissions]

        case (.checkingPermissions, .permissionsGranted(let gen)):
            guard gen == generation else { return [] }
            state = .starting
            return [.showRecordingPill, .startRecording, .updateMenuBar(.recording)]

        case (.checkingPermissions, .permissionsDenied(let gen, let reason)):
            guard gen == generation else { return [] }
            state = .idle
            return [.updateMenuBar(.idle), .presentPermissionAlert(reason)]

        case (.checkingPermissions, .cancelRequested):
            state = .idle
            return [.cancelRecording, .hidePill, .updateMenuBar(.idle)]

        case (.starting, .recordingStarted(let gen)):
            guard gen == generation else { return [] }
            state = .recording
            return []

        case (.starting, .startFailed(let gen, let message)):
            guard gen == generation else { return [] }
            state = .finishing(outcome: .error(message))
            return [.showError(message), .updateMenuBar(.idle), .startAutoDismissTimer(seconds: 5)]

        case (.starting, .stopRequested):
            state = .stopping
            return []

        case (.stopping, .recordingStarted(let gen)):
            guard gen == generation else { return [] }
            state = .transcribing
            return [.showTranscribingState, .updateMenuBar(.processing), .stopRecordingAndTranscribe]

        case (.stopping, .startFailed(let gen, let message)):
            guard gen == generation else { return [] }
            state = .finishing(outcome: .error(message))
            return [.showError(message), .updateMenuBar(.idle), .startAutoDismissTimer(seconds: 5)]

        case (.recording, .cancelRequested):
            state = .idle
            return [.cancelRecording, .hidePill, .updateMenuBar(.idle)]

        case (.starting, .cancelRequested):
            state = .idle
            return [.cancelRecording, .hidePill, .updateMenuBar(.idle)]

        case (.recording, .stopRequested):
            state = .transcribing
            return [.showTranscribingState, .updateMenuBar(.processing), .stopRecordingAndTranscribe]

        case (.recording, .captureFailed(let gen, let message)):
            guard gen == generation else { return [] }
            state = .finishing(outcome: .error(message))
            // Fork: a capture failure means nothing was saved (zero-buffer cold
            // Bluetooth mic → `noAudioCaptured`). Like a transcription failure
            // (below), this must NOT auto-dismiss — if it
            // vanished after 8s the user, often away from the screen dictating,
            // would return to an idle island with no sign the recording died.
            // We hold the error until the user dismisses it (clicking the failed
            // island → `.dismissRequested`); `.finishing` is inactive for
            // settle/quit, so holding is safe and simply blocks a new start until
            // acknowledged. A failure sound (in `.showError`) is the real-time cue.
            return [.showError(message), .updateMenuBar(.idle), .finalizeFailedCapture]

        case (.transcribing, .transcriptionCompleted(let gen, let transcriptionID)):
            guard gen == generation else { return [] }
            state = .finishing(outcome: .completed(transcriptionID))
            return [
                .showCompleted,
                .updateMenuBar(.idle),
                .navigateToTranscription(transcriptionID),
                .startAutoDismissTimer(seconds: 1),
            ]

        case (.transcribing, .transcriptionFailed(let gen, let message)):
            guard gen == generation else { return [] }
            state = .finishing(outcome: .error(message))
            // Fork: held, like `.captureFailed`. The audio is safe on disk, but
            // Splay has no Library to retry from — the held card offers Retry.
            return [.showError(message), .updateMenuBar(.idle)]

        case (.finishing(outcome: .error), .retryRequested):
            // Same generation: the retry finishes the *same* recording, so its
            // completion/failure events must match.
            state = .transcribing
            return [
                .cancelAutoDismissTimer,
                .showTranscribingState,
                .updateMenuBar(.processing),
                .retryTranscription,
            ]

        case (.finishing, .dismissRequested):
            state = .idle
            return [.cancelAutoDismissTimer, .hidePill]

        case (.finishing, .autoDismissExpired(let gen)):
            guard gen == generation else { return [] }
            state = .idle
            return [.hidePill]

        case (.recording, .dismissRequested),
             (.starting, .dismissRequested),
             (.stopping, .dismissRequested),
             (.transcribing, .dismissRequested),
             (.checkingPermissions, .dismissRequested):
            return []

        default:
            return []
        }
    }
}

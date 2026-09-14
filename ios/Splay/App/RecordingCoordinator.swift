import ActivityKit
import AVFAudio
import Foundation
import OSLog
import SplayCore
import UIKit

/// The one object the intents talk to. Owns the recording lifecycle on the
/// phone and the Live Activity that is its only visible presence.
///
/// Flow: `start` → mic permission → Live Activity (Apple requires it for a
/// background-started recording) → `MeetingRecordingService.startRecording`
/// (mic only, VAD live chunking on). `stop` → finishing phase → stop → transcribe
/// the tail → save `.md` + paired audio via `AutoSaveService` → clipboard →
/// saved phase → the activity ends itself after three seconds.
@MainActor
final class RecordingCoordinator {
    static let shared = RecordingCoordinator()

    private let logger = Logger(subsystem: "com.macparakeet.ios", category: "RecordingCoordinator")
    private var environment: SplayEnvironment?
    private var activity: ActivityHandle?
    private var state = SplayActivityAttributes.ContentState.placeholder
    private var stopTask: Task<String?, Never>?
    private var healthTask: Task<Void, Never>?
    /// The stopped session, kept so Retry can transcribe it again.
    private var lastOutput: MeetingRecordingOutput?

    private(set) var lastTranscript: String?

    /// Mirrors the Mac (`MeetingRecordingFlowCoordinator`): a healthy engine
    /// lands its first buffer well under a second, so a 2 s grace never ambers a
    /// normal start; the poll runs at 1 Hz, so 2 s stale tolerates one missed tick.
    private static let audioAliveStartupGrace: TimeInterval = 2
    private static let audioAliveStaleAfter: TimeInterval = 2

    private init() {}

    func attach(_ environment: SplayEnvironment) {
        self.environment = environment
        // A previous process may have died mid-recording and left its activity
        // on the island. Nothing can drive it any more; end it.
        Task { await ActivityHandle.endAllLingering() }
    }

    var isRecording: Bool {
        activity != nil && (state.phase == .recording || state.phase == .paused || state.phase == .inputDead)
    }

    // MARK: - Actions (the three the island allows, plus the toggle)

    func toggle() async {
        if isRecording {
            _ = await stopAndAwaitTranscript()
        } else {
            await start()
        }
    }

    func start() async {
        guard let environment, !isRecording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            logger.error("record_permission_denied")
            return
        }
        // A Failed activity may still be showing; it is ours and must not be
        // orphaned when the new one replaces it.
        if let stale = activity {
            await stale.end(state, dismissAfter: 0)
            activity = nil
        }
        lastOutput = nil
        let sessionID = UUID()
        state = SplayActivityAttributes.ContentState(
            phase: .recording, runningSince: Date(), accumulatedSeconds: 0, finalSeconds: nil, wordCount: nil, canRetry: false
        )
        // The Live Activity must exist before (and for as long as) the recording
        // runs when it was started from a Control; iOS ends the recording otherwise.
        do {
            activity = ActivityHandle(try Activity.request(
                attributes: SplayActivityAttributes(sessionID: sessionID),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            ))
        } catch {
            logger.error("live_activity_request_failed \(error.localizedDescription, privacy: .public)")
            return
        }
        do {
            try await environment.meetingRecordingService.startRecording(sourceMode: .microphoneOnly)
            AudioCaptureDiagnostics.append("ios_recording_started session=\(sessionID.uuidString)")
            startHealthWatch()
        } catch {
            logger.error("start_recording_failed \(error.localizedDescription, privacy: .public)")
            AudioCaptureDiagnostics.append("ios_recording_start_failed \(AudioCaptureDiagnostics.errorFields(error))")
            await fail(retryable: false)
        }
    }

    /// Pause is offered while recording and while the input reads dead (the
    /// island shows the same control in both phases).
    func pause() async {
        guard let environment, state.phase == .recording || state.phase == .inputDead else { return }
        await environment.meetingRecordingService.pauseRecording()
        state.accumulatedSeconds = state.elapsed()
        state.runningSince = nil
        state.phase = .paused
        await push()
    }

    func resume() async {
        guard let environment, state.phase == .paused else { return }
        await environment.meetingRecordingService.resumeRecording()
        state.runningSince = Date()
        state.phase = .recording
        await push()
    }

    /// Stop, transcribe, save, copy. Returns the transcript (nil on failure).
    /// Re-entrant: a second call while stopping awaits the first.
    func stopAndAwaitTranscript() async -> String? {
        if let stopTask { return await stopTask.value }
        guard let environment, isRecording else { return lastTranscript }
        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.finish(environment: environment)
        }
        stopTask = task
        let result = await task.value
        stopTask = nil
        return result
    }

    /// Runs the stopped session through the model again. Only reachable when
    /// `stopRecording` succeeded (the island shows Retry only then).
    func retryTranscription() async {
        guard let environment, state.phase == .failed, let output = lastOutput else { return }
        state.phase = .finishing
        await push()
        do {
            let transcript = try await transcribeAndDeliver(output: output, environment: environment)
            await saved(transcript)
        } catch {
            logger.error("retry_transcription_failed \(error.localizedDescription, privacy: .public)")
            AudioCaptureDiagnostics.append("ios_retry_transcription_failed \(AudioCaptureDiagnostics.errorFields(error))")
            await environment.meetingRecordingService.finishTranscriptionAttempt(for: output)
            await fail(retryable: true)
        }
    }

    // MARK: - Finish

    private func finish(environment: SplayEnvironment) async -> String? {
        stopHealthWatch()
        let finalSeconds = state.elapsed()
        state.runningSince = nil
        state.accumulatedSeconds = finalSeconds
        state.finalSeconds = finalSeconds
        state.phase = .finishing
        await push()

        let output: MeetingRecordingOutput
        do {
            output = try await environment.meetingRecordingService.stopRecording()
            lastOutput = output
        } catch {
            // No usable audio (or the writer failed): nothing to retry.
            logger.error("stop_recording_failed \(error.localizedDescription, privacy: .public)")
            AudioCaptureDiagnostics.append("ios_stop_failed \(AudioCaptureDiagnostics.errorFields(error))")
            await fail(retryable: false)
            return nil
        }
        do {
            let transcript = try await transcribeAndDeliver(output: output, environment: environment)
            await saved(transcript)
            return transcript
        } catch {
            logger.error("transcribe_failed \(error.localizedDescription, privacy: .public)")
            AudioCaptureDiagnostics.append("ios_transcribe_failed \(AudioCaptureDiagnostics.errorFields(error))")
            // Failure path per MeetingRecordingServiceProtocol: release the
            // speech-engine lease but leave the recovery lock for Retry.
            await environment.meetingRecordingService.finishTranscriptionAttempt(for: output)
            await fail(retryable: true)
            return nil
        }
    }

    /// Tail-chunk transcription, `.md` + paired audio into the Meetings folder,
    /// and the clipboard. Verbatim: `TranscriptionService` runs the deterministic
    /// pipeline only (`processingMode: .raw`).
    private func transcribeAndDeliver(output: MeetingRecordingOutput, environment: SplayEnvironment) async throws -> String {
        let transcription = try await environment.transcriptionService.transcribeMeeting(recording: output)
        await environment.meetingRecordingService.completeTranscription(for: output)
        environment.autoSaveService.saveIfEnabled(transcription, scope: .meeting)
        let text = transcription.cleanTranscript ?? transcription.rawTranscript ?? ""
        UIPasteboard.general.string = text
        lastTranscript = text
        state.wordCount = text.split(whereSeparator: \.isWhitespace).count
        AudioCaptureDiagnostics.append("ios_recording_saved session=\(output.sessionID.uuidString) words=\(state.wordCount ?? 0)")
        return text
    }

    private func saved(_ transcript: String) async {
        state.phase = .saved
        state.canRetry = false
        await push()
        // HIG: end the activity as soon as the task is over; a short dwell so the
        // green check is seen, then the island returns to hardware.
        await activity?.end(state, dismissAfter: 3)
        activity = nil
    }

    /// `retryable` is true only when a stopped session exists to transcribe
    /// again; then the activity stays up carrying the Retry control. Otherwise
    /// the failure is shown briefly and the activity ends. Nothing is deleted
    /// either way: the session folder and its audio stay for recovery on this
    /// phone or by import on the Mac.
    private func fail(retryable: Bool) async {
        stopHealthWatch()
        state.runningSince = nil
        state.phase = .failed
        state.canRetry = retryable && lastOutput != nil
        if state.canRetry {
            await push()
        } else {
            await activity?.end(state, dismissAfter: 3)
            activity = nil
        }
    }

    // MARK: - Health (dead input, hard capture failure)

    /// Same doctrine as the Mac. *Dead ≠ silent*: a mic that stops delivering
    /// buffers while the session runs is **shown** (amber, "No input"), never
    /// killed, and recovers on its own the moment frames flow again. A capture
    /// pipeline that has actually stopped (`mode == .stopped` while we believe we
    /// are recording) is a hard failure: finalize what was captured and fail.
    private func startHealthWatch() {
        stopHealthWatch()
        healthTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let environment = self.environment, self.isRecording else { return }
                let health = await environment.meetingRecordingService.captureHealth

                if health.mode == .stopped {
                    AudioCaptureDiagnostics.append("ios_capture_stopped_unexpectedly")
                    self.stopHealthWatch()
                    await self.finalizeFailedCapture(environment: environment)
                    return
                }

                let actively = self.state.phase == .recording || self.state.phase == .inputDead
                let alive = Self.audioAlive(health, activelyRecording: actively && health.mode == .full)
                if !alive, self.state.phase == .recording {
                    AudioCaptureDiagnostics.append("ios_audio_alive=false")
                    self.state.phase = .inputDead
                    await self.push()
                } else if alive, self.state.phase == .inputDead {
                    AudioCaptureDiagnostics.append("ios_audio_alive=true")
                    self.state.phase = .recording
                    await self.push()
                }
            }
        }
    }

    private static func audioAlive(_ health: MeetingCaptureHealth, activelyRecording: Bool, now: Date = Date()) -> Bool {
        if !activelyRecording { return true }
        if let startedAt = health.startedAt, now.timeIntervalSince(startedAt) < audioAliveStartupGrace { return true }
        if let lastWrite = health.lastSuccessfulWriteAt, now.timeIntervalSince(lastWrite) < audioAliveStaleAfter { return true }
        if health.startedAt == nil { return true }   // no baseline: don't amber on unknowns
        return false
    }

    /// The OS pipeline died under us. Finalize the writer so the partial audio
    /// and its recovery lock are usable, release the lease, and show Failed with
    /// Retry (which transcribes whatever was captured).
    private func finalizeFailedCapture(environment: SplayEnvironment) async {
        state.runningSince = nil
        state.finalSeconds = state.elapsed()
        do {
            let output = try await environment.meetingRecordingService.stopRecording()
            lastOutput = output
            await environment.meetingRecordingService.finishTranscriptionAttempt(for: output)
            await fail(retryable: true)
        } catch {
            AudioCaptureDiagnostics.append("ios_capture_finalize_failed \(AudioCaptureDiagnostics.errorFields(error))")
            await fail(retryable: false)
        }
    }

    private func stopHealthWatch() {
        healthTask?.cancel()
        healthTask = nil
    }

    private func push() async {
        await activity?.update(state)
    }
}

/// `Activity` is a non-Sendable class with nonisolated async methods, so a
/// `@MainActor` owner cannot call them directly under strict concurrency. The
/// handle owns the activity and is the only thing that touches it.
private final class ActivityHandle: @unchecked Sendable {
    private let activity: Activity<SplayActivityAttributes>

    init(_ activity: Activity<SplayActivityAttributes>) {
        self.activity = activity
    }

    nonisolated func update(_ state: SplayActivityAttributes.ContentState) async {
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    nonisolated func end(_ state: SplayActivityAttributes.ContentState, dismissAfter seconds: TimeInterval) async {
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: seconds <= 0 ? .immediate : .after(Date().addingTimeInterval(seconds))
        )
    }

    /// End every activity of ours the system still holds (from a process that
    /// died mid-recording). Called once at launch.
    nonisolated static func endAllLingering() async {
        for activity in Activity<SplayActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

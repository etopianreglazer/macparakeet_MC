import Foundation

/// The final step for a *stopped* recording, in the only safe order:
/// transcribe → write the transcript file → delete the recovery lock.
///
/// Green on the island must mean "the .md is on disk": Splay has no Library,
/// so a transcript that exists only in the database is invisible, and a lock
/// deleted before the write means relaunch recovery can no longer offer it
/// (upstream MacParakeet #818 / #698). Any failure leaves the lock in place
/// and returns what Retry should redo.
@MainActor
public struct MeetingRecordingFinisher {
    /// What is left to do for a stopped recording.
    public enum Step: Sendable {
        /// Transcribe (again) and write the file.
        case transcribe(MeetingRecordingOutput)
        /// Already transcribed and in the database; only the file write failed.
        /// Retry writes again — re-transcribing would duplicate the row.
        case save(Transcription, MeetingRecordingOutput)
    }

    public enum Outcome {
        case completed(Transcription)
        /// `retry` is what Retry should run; `stage` says where it failed.
        case failed(Error, retry: Step, stage: Stage)
    }

    public enum Stage: Equatable, Sendable {
        case transcription
        case fileWrite
    }

    private let meetingRecordingService: MeetingRecordingServiceProtocol
    private let transcriptionService: TranscriptionServiceProtocol
    private let transcriptionRepo: TranscriptionRepositoryProtocol
    private let saveTranscriptFile: @MainActor (Transcription) throws -> Void

    public init(
        meetingRecordingService: MeetingRecordingServiceProtocol,
        transcriptionService: TranscriptionServiceProtocol,
        transcriptionRepo: TranscriptionRepositoryProtocol,
        saveTranscriptFile: @escaping @MainActor (Transcription) throws -> Void
    ) {
        self.meetingRecordingService = meetingRecordingService
        self.transcriptionService = transcriptionService
        self.transcriptionRepo = transcriptionRepo
        self.saveTranscriptFile = saveTranscriptFile
    }

    /// `isRetry`: a failed first attempt already left a row (status `.error`)
    /// for this recording; a retry re-transcribes *that* row in place so
    /// Recents never lists the same recording twice.
    public func finish(_ step: Step, isRetry: Bool) async -> Outcome {
        let output: MeetingRecordingOutput
        let transcription: Transcription
        switch step {
        case .save(let saved, let recording):
            output = recording
            transcription = saved
        case .transcribe(let recording):
            output = recording
            do {
                if isRetry, let failedRow = failedRow(for: recording) {
                    transcription = try await transcriptionService.retranscribeMeeting(
                        existing: failedRow,
                        recording: recording,
                        onProgress: nil
                    )
                } else {
                    transcription = try await transcriptionService.transcribeMeeting(
                        recording: recording,
                        onProgress: nil
                    )
                }
            } catch {
                await meetingRecordingService.finishTranscriptionAttempt(for: recording)
                return .failed(error, retry: .transcribe(recording), stage: .transcription)
            }
        }

        do {
            try saveTranscriptFile(transcription)
        } catch {
            AudioCaptureDiagnostics.append(
                "meeting_transcript_file_write_failed \(AudioCaptureDiagnostics.errorFields(error))"
            )
            await meetingRecordingService.finishTranscriptionAttempt(for: output)
            return .failed(
                TranscriptFileWriteError(underlying: error),
                retry: .save(transcription, output),
                stage: .fileWrite
            )
        }

        await meetingRecordingService.completeTranscription(for: output)
        return .completed(transcription)
    }

    /// The newest non-completed row a failed attempt left for this recording.
    private func failedRow(for output: MeetingRecordingOutput) -> Transcription? {
        let rows = (try? transcriptionRepo.fetchByFilePath(output.mixedAudioURL.path, sourceType: .meeting)) ?? []
        return rows
            .filter { $0.status != .completed }
            .max { $0.createdAt < $1.createdAt }
    }
}

/// The transcript was made but its file could not be written. The message says
/// so plainly: the recording is safe and Retry writes the file again.
public struct TranscriptFileWriteError: LocalizedError {
    public let underlying: Error

    public var errorDescription: String? {
        "Transcribed, but the file couldn't be saved: \(underlying.localizedDescription)"
    }
}

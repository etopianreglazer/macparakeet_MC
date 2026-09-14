import Foundation
import SplayCore

/// Service container for the phone. The same objects the Mac's `AppEnvironment`
/// builds, minus everything that is a Mac surface (card, panel, hotkeys, system
/// audio, paste-by-CGEvent). One instance per process, owned by `SplayApp`.
@MainActor
final class SplayEnvironment {
    let databaseManager: DatabaseManager
    let transcriptionRepo: TranscriptionRepository
    let customWordRepo: CustomWordRepository
    let snippetRepo: TextSnippetRepository
    let sttRuntime: STTRuntime
    let sttScheduler: STTScheduler
    let sharedMicStream: SharedMicrophoneStream
    let audioProcessor: AudioProcessor
    let meetingRecordingService: MeetingRecordingService
    let transcriptionService: TranscriptionService
    let autoSaveService: AutoSaveService
    let runtimePreferences: AppRuntimePreferencesProtocol

    init() throws {
        try AppPaths.ensureDirectories()
        // The on-disk store (Application Support/MacParakeet-MC/macparakeet.db);
        // the no-argument initializer is the in-memory one for tests.
        databaseManager = try DatabaseManager(path: AppPaths.databasePath)
        transcriptionRepo = TranscriptionRepository(dbQueue: databaseManager.dbQueue)
        customWordRepo = CustomWordRepository(dbQueue: databaseManager.dbQueue)
        snippetRepo = TextSnippetRepository(dbQueue: databaseManager.dbQueue)

        let runtimePreferences = UserDefaultsAppRuntimePreferences()
        self.runtimePreferences = runtimePreferences

        // One STT control plane per process (ADR-016). Parakeet v3 by default;
        // WhisperKit stays linked but unused in v1.
        sttRuntime = STTRuntime(
            modelVersion: SpeechEnginePreference.parakeetModelVariant().asrModelVersion,
            speechEngine: SpeechEnginePreference.current(),
            whisperModelVariant: SpeechEnginePreference.whisperModelVariant()
        )
        sttScheduler = STTScheduler(runtime: sttRuntime)

        // No device-attempt chain on iOS: AVAudioSession owns routing, and the
        // platform activates the session itself (see MicrophoneEnginePlatform).
        sharedMicStream = SharedMicrophoneStream(platform: AVAudioEngineMicrophonePlatform())
        audioProcessor = AudioProcessor(sharedMicStream: sharedMicStream)

        meetingRecordingService = MeetingRecordingService(
            micProcessingMode: .raw,
            audioCaptureService: MeetingAudioCaptureService(
                micProcessingMode: .raw,
                sourceModeProvider: { .microphoneOnly },
                sharedMicStream: sharedMicStream
            ),
            sttTranscriber: sttScheduler,
            isVadLiveChunkingEnabled: { true }
        )
        transcriptionService = TranscriptionService(
            audioProcessor: audioProcessor,
            sttTranscriber: sttScheduler,
            transcriptionRepo: transcriptionRepo,
            customWordRepo: customWordRepo,
            snippetRepo: snippetRepo,
            processingMode: { .raw },
            shouldDiarize: { false }
        )
        autoSaveService = AutoSaveService()
        // Documents/MacParakeet-MC/Meetings inside the sandbox — visible in the
        // Files app because Info.plist opts into document sharing.
        AutoSaveService.ensureFolderConfigured(scope: .meeting)
    }

    /// Kick the model load (and, on first run, the ~600 MB download) so the
    /// first Action Button press does not pay for it.
    func warmUpSpeech() {
        Task.detached(priority: .utility) { [sttScheduler] in
            await sttScheduler.backgroundWarmUp()
        }
    }
}

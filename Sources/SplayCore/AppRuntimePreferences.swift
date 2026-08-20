import Foundation

public protocol AppRuntimePreferencesProtocol: Sendable {
    var processingMode: Dictation.ProcessingMode { get }
    var voiceReturnTrigger: String? { get }
    var shouldSaveAudioRecordings: Bool { get }
    var shouldSaveDictationHistory: Bool { get }
    var shouldSaveTranscriptionAudio: Bool { get }
    var shouldDiarize: Bool { get }
    var aiFormatterEnabled: Bool { get }
    var aiFormatterPrompt: String { get }
    var selectedMicrophoneDeviceUID: String? { get }
    var meetingAudioSourceMode: MeetingAudioSourceMode { get }
    var pauseMediaDuringDictation: Bool { get }
    var shouldKeepDictationOnClipboard: Bool { get }
    var hasCompletedFirstDictation: Bool { get }
    /// Flip the one-shot "first dictation completed" flag. Returns `true` only
    /// the first time it transitions (so callers can fire a one-shot side
    /// effect like the activation telemetry event); `false` on every
    /// subsequent call.
    @discardableResult
    func markFirstDictationCompleted() -> Bool
}

public enum MeetingAudioSourceMode: String, CaseIterable, Hashable, Sendable, Equatable {
    case microphoneAndSystem = "microphone_and_system"
    case systemOnly = "system_only"
    /// Mic only — no system audio, so ScreenCaptureKit (and its screen-recording
    /// permission) is never engaged. Used by single-tap Fn capture in the fork.
    case microphoneOnly = "microphone_only"

    public var capturesMicrophone: Bool {
        self != .systemOnly
    }

    public var capturesSystemAudio: Bool {
        self != .microphoneOnly
    }

    public var displayTitle: String {
        switch self {
        case .microphoneAndSystem:
            return "Microphone + System Audio"
        case .systemOnly:
            return "System Audio Only"
        case .microphoneOnly:
            return "Microphone Only"
        }
    }

    public var detail: String {
        switch self {
        case .microphoneAndSystem:
            return "Capture your microphone and computer audio. Weak mic bleed is suppressed live."
        case .systemOnly:
            return "Capture computer audio for meetings. Your microphone is still used for dictation."
        case .microphoneOnly:
            return "Capture only your microphone. No screen-recording permission needed."
        }
    }

    public static func current(defaults: UserDefaults = .standard) -> MeetingAudioSourceMode {
        guard let raw = defaults.string(forKey: UserDefaultsAppRuntimePreferences.meetingAudioSourceModeKey),
              let mode = MeetingAudioSourceMode(rawValue: raw) else {
            return .microphoneAndSystem
        }
        return mode
    }
}

public final class UserDefaultsAppRuntimePreferences: AppRuntimePreferencesProtocol, @unchecked Sendable {
    public static let showIdlePillKey = "showIdlePill"
    public static let silenceAutoStopKey = "silenceAutoStop"
    public static let silenceDelayKey = "silenceDelay"
    public static let voiceReturnEnabledKey = "voiceReturnEnabled"
    public static let voiceReturnTriggerKey = "voiceReturnTrigger"
    public static let processingModeKey = "processingMode"
    public static let saveDictationHistoryKey = "saveDictationHistory"
    public static let saveAudioRecordingsKey = "saveAudioRecordings"
    public static let saveTranscriptionAudioKey = "saveTranscriptionAudio"
    public static let speakerDiarizationKey = "speakerDiarization"
    public static let aiFormatterEnabledKey = "aiFormatterEnabled"
    public static let aiFormatterPromptKey = "aiFormatterPrompt"
    public static let selectedMicrophoneDeviceUIDKey = "selectedMicrophoneDeviceUID"
    public static let meetingAudioSourceModeKey = "meetingAudioSourceMode"
    public static let pauseMediaDuringDictationKey = "pauseMediaDuringDictation"
    public static let keepDictationOnClipboardKey = "keepDictationOnClipboard"
    public static let hasCompletedFirstDictationKey = "hasCompletedFirstDictation"
    /// Play a chime (and, when backgrounded, post a banner) when a file/URL
    /// transcription or a batch finishes. Default on; opt-out in Settings.
    public static let notifyOnTranscriptionCompleteKey = "notifyOnTranscriptionComplete"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var processingMode: Dictation.ProcessingMode {
        let raw = defaults.string(forKey: Self.processingModeKey)
        return Dictation.ProcessingMode(rawValue: raw ?? Dictation.ProcessingMode.raw.rawValue) ?? .raw
    }

    public var voiceReturnTrigger: String? {
        guard defaults.bool(forKey: Self.voiceReturnEnabledKey) else { return nil }
        let trigger = (defaults.string(forKey: Self.voiceReturnTriggerKey) ?? "press return")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trigger.isEmpty ? nil : trigger
    }

    public var shouldSaveAudioRecordings: Bool {
        defaults.object(forKey: Self.saveAudioRecordingsKey) as? Bool ?? true
    }

    public var shouldSaveDictationHistory: Bool {
        defaults.object(forKey: Self.saveDictationHistoryKey) as? Bool ?? true
    }

    public var shouldSaveTranscriptionAudio: Bool {
        defaults.object(forKey: Self.saveTranscriptionAudioKey) as? Bool ?? true
    }

    public var shouldDiarize: Bool {
        defaults.object(forKey: Self.speakerDiarizationKey) as? Bool ?? false
    }

    public var aiFormatterEnabled: Bool {
        defaults.object(forKey: Self.aiFormatterEnabledKey) as? Bool ?? false
    }

    public var aiFormatterPrompt: String {
        let prompt = defaults.string(forKey: Self.aiFormatterPromptKey) ?? ""
        return AIFormatter.normalizedPromptTemplate(prompt)
    }

    public var selectedMicrophoneDeviceUID: String? {
        AudioDeviceManager.normalizedUID(defaults.string(forKey: Self.selectedMicrophoneDeviceUIDKey))
    }

    public var meetingAudioSourceMode: MeetingAudioSourceMode {
        MeetingAudioSourceMode.current(defaults: defaults)
    }

    public var pauseMediaDuringDictation: Bool {
        defaults.object(forKey: Self.pauseMediaDuringDictationKey) as? Bool ?? false
    }

    public var shouldKeepDictationOnClipboard: Bool {
        defaults.bool(forKey: Self.keepDictationOnClipboardKey)
    }

    public var hasCompletedFirstDictation: Bool {
        defaults.bool(forKey: Self.hasCompletedFirstDictationKey)
    }

    @discardableResult
    public func markFirstDictationCompleted() -> Bool {
        guard !hasCompletedFirstDictation else { return false }
        defaults.set(true, forKey: Self.hasCompletedFirstDictationKey)
        return true
    }
}

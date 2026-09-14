import AppIntents
import Foundation

// App Intents shared by the app and the widget extension. Their `perform()`
// bodies run in the *app* process (that is what `LiveActivityIntent` and
// `AudioRecordingIntent` guarantee), so the real work is compiled only under
// SPLAY_APP; the widget target just needs the types to exist for
// `Button(intent:)` and the Control.
//
// Rules from the HIG and the plan: Record, Pause, Resume are the only actions.
// Stop is the Action Button pressed again (the toggle intent), never a button
// in the island.

/// Action Button / Control: press to start, press again to stop.
struct ToggleRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Record with Splay"
    static let description = IntentDescription("Starts a recording, or stops the one in progress.")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    func perform() async throws -> some IntentResult {
#if SPLAY_APP
        await RecordingCoordinator.shared.toggle()
#endif
        return .result()
    }
}

struct StartRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Splay recording"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
#if SPLAY_APP
        await RecordingCoordinator.shared.start()
#endif
        return .result()
    }
}

/// Stops and transcribes. Returns the verbatim transcript so a Shortcut can
/// route it (paste, share, append to a note) — the clipboard is written regardless.
struct StopRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Splay recording"
    static let description = IntentDescription("Stops, transcribes on this phone, copies the text and returns it.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
#if SPLAY_APP
        let text = await RecordingCoordinator.shared.stopAndAwaitTranscript()
        return .result(value: text ?? "")
#else
        return .result(value: "")
#endif
    }
}

struct PauseRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Splay recording"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
#if SPLAY_APP
        await RecordingCoordinator.shared.pause()
#endif
        return .result()
    }
}

struct ResumeRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Splay recording"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
#if SPLAY_APP
        await RecordingCoordinator.shared.resume()
#endif
        return .result()
    }
}

struct RetryTranscriptionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Retry Splay transcription"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
#if SPLAY_APP
        await RecordingCoordinator.shared.retryTranscription()
#endif
        return .result()
    }
}

/// Surfaces the toggle in Spotlight / Siri / the Shortcuts app without setup.
struct SplayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: ["Record with \(.applicationName)", "Start \(.applicationName)", "Stop \(.applicationName)"],
            shortTitle: "Record",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: ["Stop \(.applicationName) and copy"],
            shortTitle: "Stop and copy",
            systemImageName: "doc.on.doc"
        )
    }
}

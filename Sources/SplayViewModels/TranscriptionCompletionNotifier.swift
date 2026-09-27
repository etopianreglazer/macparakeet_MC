import Foundation

/// Pure decision + copy for the "transcription finished" signal (a chime, plus
/// a banner when the app is backgrounded). Kept free of AppKit and
/// UserNotifications so it is fully unit-testable; the app layer turns a
/// non-`nil` `Content` into a `SoundManager` chime and an optional banner.
///
/// One Settings toggle (`notifyOnTranscriptionComplete`, default on) governs
/// both surfaces — when it is off these factory methods return `nil` and the
/// app layer does nothing.
public enum TranscriptionCompletionNotifier {
    public struct Content: Equatable, Sendable {
        public let title: String
        public let body: String
        /// What a click on the banner reveals in Finder (a transcript, or the
        /// folder a batch went to); nil = nothing to reveal.
        public let revealURL: URL?

        public init(title: String, body: String, revealURL: URL? = nil) {
            self.title = title
            self.body = body
            self.revealURL = revealURL
        }
    }

    /// Splay's banner for a finished file job. Successes follow the
    /// notification setting; failures always show — they are the only place
    /// the reason is ever said. A cancel needs no banner (you just did it).
    public static func content(for outcome: FileJobOutcome, settingEnabled: Bool) -> Content? {
        switch outcome {
        case .transcribed(let fileName, let wordCount, let savedTo, let saveFailed):
            if saveFailed {
                return Content(
                    title: "Transcribed \(fileName), but not saved",
                    body: "Couldn't write to your transcripts folder. The text is in Splay's Recordings."
                )
            }
            guard settingEnabled else { return nil }
            guard let savedTo else {
                return Content(title: "Transcribed \(fileName)", body: "In Splay's Recordings \u{00B7} \(wordsLabel(wordCount))")
            }
            return Content(
                title: "Transcribed \(fileName)",
                body: "Saved to \(savedTo.deletingLastPathComponent().lastPathComponent) \u{00B7} \(wordsLabel(wordCount))",
                revealURL: savedTo
            )
        case .failed(let fileName, let reason):
            return Content(title: "Couldn't transcribe \(fileName)", body: reason)
        case .batch(let completed, let failed, let unsaved, let folder):
            guard settingEnabled || failed > 0 || unsaved > 0 else { return nil }
            var parts = ["\(completed) transcribed"]
            if failed > 0 { parts.append("\(failed) failed") }
            if unsaved > 0 { parts.append("\(unsaved) not saved") }
            let body = folder.map { "Saved to \($0.lastPathComponent) \u{00B7} " + parts.joined(separator: " \u{00B7} ") }
                ?? parts.joined(separator: " \u{00B7} ")
            return Content(
                title: failed > 0 ? "Transcribed \(filesLabel(completed)), some failed" : "Transcribed \(filesLabel(completed))",
                body: body,
                revealURL: folder
            )
        case .cancelled:
            return nil
        }
    }

    /// A file offered while a job runs is refused; say so instead of a no-op.
    public static func busyContent(runningFileName: String) -> Content {
        let name = runningFileName.isEmpty ? "the current file" : runningFileName
        return Content(
            title: "Still transcribing",
            body: "Wait for \(name) to finish, or cancel it from the Splay menu."
        )
    }

    /// Signal content for a single completed transcription, or `nil` when the
    /// user has turned completion notifications off.
    public static func singleContent(
        settingEnabled: Bool,
        transcriptName: String,
        wordCount: Int
    ) -> Content? {
        guard settingEnabled else { return nil }
        return Content(
            title: transcriptName,
            body: "Transcription complete \u{00B7} \(wordsLabel(wordCount))"
        )
    }

    /// Signal content for a finished batch, or `nil` when notifications are off.
    /// A batch always signals once, on drain — never per intermediate file.
    public static func batchContent(
        settingEnabled: Bool,
        completed: Int,
        failed: Int
    ) -> Content? {
        guard settingEnabled else { return nil }
        if failed == 0 {
            return Content(
                title: "Transcriptions complete",
                body: "\(filesLabel(completed)) transcribed"
            )
        }
        return Content(
            title: "Transcriptions finished with errors",
            body: "\(completed) transcribed \u{00B7} \(failed) failed"
        )
    }

    static func wordsLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "word" : "words")"
    }

    static func filesLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "file" : "files")"
    }
}

/// How a file job (one file, or a whole batch) ended — what Splay's island and
/// banner report.
public enum FileJobOutcome: Equatable, Sendable {
    /// One file transcribed. `savedTo` is the written transcript (nil when
    /// auto-save is off); `saveFailed` = auto-save is on but the write failed.
    case transcribed(fileName: String, wordCount: Int, savedTo: URL?, saveFailed: Bool)
    case failed(fileName: String, reason: String)
    /// A batch drained. `folder` is where its transcripts went (nil if none written).
    case batch(completed: Int, failed: Int, unsaved: Int, folder: URL?)
    case cancelled

    /// Whether the island should show the failure light rather than the check.
    public var isFailure: Bool {
        switch self {
        case .transcribed(_, _, _, let saveFailed): return saveFailed
        case .failed: return true
        case .batch(let completed, let failed, let unsaved, _): return completed == 0 || failed > 0 || unsaved > 0
        case .cancelled: return false
        }
    }
}

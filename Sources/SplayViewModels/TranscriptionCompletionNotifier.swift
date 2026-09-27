import Foundation

/// Pure decision + copy for Splay's file-job banner. Kept free of AppKit and
/// UserNotifications so it is fully unit-testable; the app layer
/// (`TranscriptionCompletionPresenter`) plays the sound and posts the banner —
/// also while Splay is frontmost.
///
/// The `notifyOnTranscriptionComplete` setting (default on) silences only
/// *successes*. Failures, unsaved transcripts, and the "still transcribing"
/// refusal always produce content: they are the only place the reason is said.
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
            // The title agrees with the island (`outcome.isFailure`).
            guard settingEnabled || outcome.isFailure else { return nil }
            var parts = ["\(completed) transcribed"]
            if failed > 0 { parts.append("\(failed) failed") }
            if unsaved > 0 { parts.append("\(unsaved) not saved") }
            var body = parts.joined(separator: " \u{00B7} ")
            if let folder {
                body = "Saved to \(folder.lastPathComponent) \u{00B7} " + body
            } else if unsaved > 0 {
                body += ". Couldn't write to your transcripts folder; the text is in Splay's Recordings."
            }
            return Content(title: batchTitle(completed: completed, failed: failed, unsaved: unsaved),
                           body: body, revealURL: folder)
        case .cancelled:
            return nil
        }
    }

    static func batchTitle(completed: Int, failed: Int, unsaved: Int) -> String {
        if completed == 0 { return "Couldn't transcribe \(filesLabel(failed))" }
        if failed > 0 { return "Transcribed \(completed) of \(completed + failed) files" }
        if unsaved > 0 { return "Transcribed \(filesLabel(completed)), \(unsaved) not saved" }
        return "Transcribed \(filesLabel(completed))"
    }

    /// A file offered while a job runs is refused; say so instead of a no-op.
    public static func busyContent(runningFileName: String) -> Content {
        let name = runningFileName.isEmpty ? "the current file" : runningFileName
        return Content(
            title: "Still transcribing",
            body: "Wait for \(name) to finish, or cancel it from the Splay menu."
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

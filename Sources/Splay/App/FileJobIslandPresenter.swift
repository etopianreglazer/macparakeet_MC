import Foundation
import SplayViewModels

/// Turns a file job's activity and outcome (`TranscriptionViewModel`) into the
/// island's file-job phase: the amber spinner while it runs, then the green
/// check (or the failure light) for a moment, then nothing. The island itself
/// decides precedence — a meeting or dictation always outranks a file job.
/// See docs/plans/file-transcription-feedback.md.
@MainActor
final class FileJobIslandPresenter {
    /// How long the check stays up — the same as a finished recording.
    static let doneSeconds: TimeInterval = 2
    /// The failure light stays a little longer; the banner carries the reason.
    static let failedSeconds: TimeInterval = 3

    private let setPhase: (IslandFileJobPhase?) -> Void
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    /// Bumped on every change, so a stale hold timer never clears a newer job.
    private var generation = 0

    init(
        setPhase: @escaping (IslandFileJobPhase?) -> Void,
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
        }
    ) {
        self.setPhase = setPhase
        self.schedule = schedule
    }

    func activeChanged(_ active: Bool) {
        generation += 1
        // Going inactive clears the spinner; the outcome (which follows in the
        // same turn) puts up the check or the failure light.
        setPhase(active ? .transcribing : nil)
    }

    func finished(_ outcome: FileJobOutcome) {
        generation += 1
        if outcome == .cancelled {
            setPhase(nil)
            return
        }
        let failed = outcome.isFailure
        setPhase(failed ? .failed : .done)
        let token = generation
        schedule(failed ? Self.failedSeconds : Self.doneSeconds) { [weak self] in
            guard let self, self.generation == token else { return }
            self.setPhase(nil)
        }
    }
}

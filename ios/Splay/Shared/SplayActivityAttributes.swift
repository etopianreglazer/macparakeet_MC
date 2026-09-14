import ActivityKit
import Foundation

/// The Live Activity's contract between the app (which drives it) and the
/// widget extension (which draws it). Compiled into both targets.
///
/// Design: the "Splay Island for iPhone" mock, v5 (a claude.ai artifact; its
/// decisions are recorded in docs/plans/splay-ios-utility-layer.md) — one row,
/// one word, one control; HIG sizes; no light. The state carries only what the
/// island shows. Per the HIG the activity is updated only when something
/// changes, so the elapsed time is derived from `runningSince` +
/// `accumulatedSeconds` on the widget side with a timer text, not pushed every
/// second.
struct SplayActivityAttributes: ActivityAttributes {
    /// Which recording session this activity belongs to.
    let sessionID: UUID

    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            /// Red dot, bars. Elapsed runs from `runningSince`.
            case recording
            /// Amber pause, flat bars. Elapsed frozen at `accumulatedSeconds`.
            case paused
            /// Amber dot, flat bars, elapsed still running. Engine stopped delivering audio.
            case inputDead
            /// Splay mark, amber bars. Tail chunk on the Neural Engine.
            case finishing
            /// Green check, copy symbol. Ends itself after ~3 s.
            case saved
            /// Coral bang, waveform. Audio kept; Retry shown only when `canRetry`.
            case failed

            /// The one word the expanded row and the Lock Screen show.
            var title: String {
                switch self {
                case .recording: "Recording"
                case .paused: "Paused"
                case .inputDead: "No input"
                case .finishing: "Finishing"
                case .saved: "Saved"
                case .failed: "Failed"
                }
            }
        }

        var phase: Phase
        /// Wall-clock start of the *current* running stretch (re-based on resume so
        /// a timer text can count from it). Nil while not counting.
        var runningSince: Date?
        /// Seconds accumulated before `runningSince` (previous stretches).
        var accumulatedSeconds: TimeInterval
        /// Final duration once saved/failed, for the Saved row.
        var finalSeconds: TimeInterval?
        var wordCount: Int?
        /// True only when a stopped session exists to transcribe again.
        var canRetry: Bool

        /// The coordinator's value before any recording exists. Not a phase the
        /// island ever shows; `RecordingCoordinator.isRecording` also requires a
        /// live activity, so this never reads as recording.
        static let placeholder = ContentState(
            phase: .recording, runningSince: nil, accumulatedSeconds: 0, finalSeconds: nil, wordCount: nil, canRetry: false
        )
    }
}

extension SplayActivityAttributes.ContentState {
    /// Elapsed seconds at `now` (frozen when `runningSince` is nil).
    func elapsed(at now: Date = Date()) -> TimeInterval {
        accumulatedSeconds + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// The instant a timer text should count from so that it reads `elapsed`.
    var timerOrigin: Date? {
        runningSince.map { $0.addingTimeInterval(-accumulatedSeconds) }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

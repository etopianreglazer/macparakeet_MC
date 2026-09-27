import Foundation

/// Shared timing values used across the dictation flow.
/// Keeping these in Core gives state/effects and UI a single source of truth.
public enum DictationFlowTiming {
    /// How long the no-speech terminal state should remain visible before dismiss.
    public static let noSpeechDismissSeconds: Double = 2.5
    /// Escape during a dictation → "3 · 2 · 1" on the island, then the audio is
    /// discarded. A fn tap inside the window keeps it (transcribe + paste);
    /// Escape again discards at once. Upstream counted down from 5.
    public static let cancelCountdownSeconds = 3
}

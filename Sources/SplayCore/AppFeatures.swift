import Foundation

/// Compile-time feature gates. Flip a single literal to expose or hide a feature
/// without touching every call site. Release builds should set these to the
/// shipping configuration before tagging a version.
public enum AppFeatures {
    /// Meeting Recording (ADR-014). When `false`, all meeting recording entry
    /// points are hidden: Transcribe tile, menu-bar "Start Recording", global
    /// meeting hotkey, settings card, library filter, onboarding step, and the
    /// screen recording permission row. Data model, services, and tests remain
    /// intact.
    public static let meetingRecordingEnabled: Bool = true

    /// VAD-guided meeting live chunking
    /// (upstream MacParakeet plan "2026-05-meeting-vad-guided-live-chunking"). When
    /// `false`, meeting live-preview chunks use the fixed 5s / 1s-overlap
    /// `AudioChunker` path. When `true`, launch-time prep tries to cache the
    /// Silero VAD model, and cached-model Parakeet sessions cut live-preview
    /// chunks at speech boundaries. Each source independently falls back to
    /// fixed chunking when VAD is unavailable or errors repeatedly. The final
    /// saved transcript (post-stop full-file STT) is unaffected either way.
    ///
    /// Enabled for the VAD release candidate after Phase 0/corpus replay showed
    /// clean inline performance and Phase 4.5 made model prep universal. Keep
    /// `vad_model_prep` allowlisted and deployed before shipping flag-on builds.
    public static let meetingVadLiveChunkingEnabled: Bool = true

    /// MacParakeet-MC fork (island redesign). When `true`, the global Fn key is a
    /// single/double-tap recording key (single = mic only, double = mic + system),
    /// paste-style dictation is no longer driven by Fn, and the old dictation idle
    /// pill is suppressed (the island's own idle/hover pill replaces it). See
    /// docs/fork-product-model.md and docs/plans/fn-rework.md.
    public static let islandReplacesDictationPill: Bool = true
}

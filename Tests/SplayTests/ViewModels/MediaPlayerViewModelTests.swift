import AVFoundation
import XCTest
@testable import SplayCore
@testable import SplayViewModels

final class MediaPlayerViewModelTests: XCTestCase {

    // MARK: - Playback Mode Detection

    func testDetectPlaybackModeForLocalVideo() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mp4")
        try Data([0x00]).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let t = Transcription(fileName: "video.mp4", filePath: tempFile.path)
        XCTAssertEqual(MediaPlayerViewModel.detectPlaybackMode(for: t), .video)
    }

    func testDetectPlaybackModeForLocalAudio() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mp3")
        try Data([0x00]).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let t = Transcription(fileName: "audio.mp3", filePath: tempFile.path)
        XCTAssertEqual(MediaPlayerViewModel.detectPlaybackMode(for: t), .audio)
    }

    func testDetectPlaybackModeForMissingFile() {
        let t = Transcription(fileName: "deleted.mp3", filePath: "/nonexistent/path/file.mp3")
        XCTAssertEqual(MediaPlayerViewModel.detectPlaybackMode(for: t), .none)
    }

    func testDetectPlaybackModeForNoPath() {
        let t = Transcription(fileName: "orphan.mp3")
        XCTAssertEqual(MediaPlayerViewModel.detectPlaybackMode(for: t), .none)
    }

    func testDetectPlaybackModeVideoExtensions() throws {
        let videoExts = ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
        for ext in videoExts {
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString).\(ext)")
            try Data([0x00]).write(to: tempFile)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let t = Transcription(fileName: "file.\(ext)", filePath: tempFile.path)
            XCTAssertEqual(
                MediaPlayerViewModel.detectPlaybackMode(for: t), .video,
                "Expected .video for .\(ext)"
            )
        }
    }

    func testDetectPlaybackModeAudioExtensions() throws {
        let audioExts = ["mp3", "wav", "m4a", "flac", "ogg", "aac"]
        for ext in audioExts {
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("test-\(UUID().uuidString).\(ext)")
            try Data([0x00]).write(to: tempFile)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let t = Transcription(fileName: "file.\(ext)", filePath: tempFile.path)
            XCTAssertEqual(
                MediaPlayerViewModel.detectPlaybackMode(for: t), .audio,
                "Expected .audio for .\(ext)"
            )
        }
    }

    // MARK: - Initial State

    @MainActor
    func testInitialState() {
        let vm = MediaPlayerViewModel()
        XCTAssertNil(vm.player)
        XCTAssertFalse(vm.isPlaying)
        XCTAssertEqual(vm.currentTimeMs, 0)
        XCTAssertEqual(vm.durationMs, 0)
        XCTAssertEqual(vm.playerState, .idle)
        XCTAssertEqual(vm.playbackMode, .none)
    }

    @MainActor
    func testCleanupResetsState() {
        let vm = MediaPlayerViewModel()
        vm.currentTimeMs = 5000
        vm.durationMs = 60000
        vm.isPlaying = true
        vm.playerState = .ready
        vm.playbackMode = .video

        vm.cleanup()

        XCTAssertNil(vm.player)
        XCTAssertFalse(vm.isPlaying)
        XCTAssertEqual(vm.currentTimeMs, 0)
        XCTAssertEqual(vm.durationMs, 0)
        XCTAssertEqual(vm.playerState, .idle)
    }

    @MainActor
    func testLoadNoMediaSetsPlaybackModeNone() async {
        let vm = MediaPlayerViewModel()
        let t = Transcription(fileName: "orphan.mp3")
        await vm.load(for: t)
        XCTAssertEqual(vm.playbackMode, .none)
        XCTAssertEqual(vm.playerState, .idle)
    }

    // MARK: - Playback Rate

    @MainActor
    func testPlaybackRateLabelsUseCompactMediaPlayerFormat() {
        XCTAssertEqual(PlaybackRate.label(for: 0.5), "0.5x")
        XCTAssertEqual(PlaybackRate.label(for: 1.0), "1x")
        XCTAssertEqual(PlaybackRate.label(for: 1.25), "1.25x")
        XCTAssertEqual(PlaybackRate.label(for: 1.5), "1.5x")
        XCTAssertEqual(PlaybackRate.label(for: 2.0), "2x")
    }

    @MainActor
    func testPlaybackRateOptionsUseStandardMediaPlayerPresets() {
        XCTAssertEqual(PlaybackRate.options, [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
    }

    @MainActor
    func testPlaybackRatePersistsAcrossViewModelInstances() {
        let defaults = isolatedPlaybackDefaults()
        let vm = MediaPlayerViewModel(playbackRateDefaults: defaults)

        vm.setPlaybackRate(1.5)

        let reloaded = MediaPlayerViewModel(playbackRateDefaults: defaults)
        XCTAssertEqual(reloaded.playbackRate, 1.5, accuracy: 0.001)
        XCTAssertEqual(reloaded.playbackRateLabel, "1.5x")
    }

    @MainActor
    func testTogglePlayPauseUsesSelectedPlaybackRate() {
        let vm = MediaPlayerViewModel(playbackRateDefaults: isolatedPlaybackDefaults())
        let player = AVPlayer()
        vm.player = player
        vm.setPlaybackRate(1.5)

        vm.togglePlayPause()

        XCTAssertEqual(player.defaultRate, 1.5, accuracy: 0.001)
        XCTAssertEqual(player.rate, 1.5, accuracy: 0.001)
    }

    @MainActor
    func testChangingPlaybackRateUpdatesActivePlayerRate() {
        let vm = MediaPlayerViewModel(playbackRateDefaults: isolatedPlaybackDefaults())
        let player = AVPlayer()
        vm.player = player
        player.rate = 1.0

        vm.setPlaybackRate(1.25)

        XCTAssertEqual(player.defaultRate, 1.25, accuracy: 0.001)
        XCTAssertEqual(player.rate, 1.25, accuracy: 0.001)
    }

    @MainActor
    func testChangingPlaybackRateDoesNotResumePausedPlayerWhenIsPlayingIsStale() {
        let vm = MediaPlayerViewModel(playbackRateDefaults: isolatedPlaybackDefaults())
        let player = AVPlayer()
        vm.player = player
        vm.isPlaying = true
        player.pause()

        vm.setPlaybackRate(1.5)

        XCTAssertEqual(player.defaultRate, 1.5, accuracy: 0.001)
        XCTAssertEqual(player.rate, 0.0, accuracy: 0.001)
    }

    @MainActor
    func testCleanupPreservesPlaybackRatePreference() {
        let vm = MediaPlayerViewModel(playbackRateDefaults: isolatedPlaybackDefaults())
        vm.setPlaybackRate(1.5)
        vm.player = AVPlayer()
        vm.playerState = .ready

        vm.cleanup()

        XCTAssertEqual(vm.playbackRate, 1.5, accuracy: 0.001)
        XCTAssertEqual(vm.playbackRateLabel, "1.5x")
    }
}

private func isolatedPlaybackDefaults() -> UserDefaults {
    let suiteName = "com.macparakeet.tests.playback-rate.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

import AVFoundation
import CoreMedia
import Foundation
import os

/// `AudioFileConverting` implemented with AVFoundation only: no FFmpeg, no
/// subprocess. It is the converter on iOS (where `Process` does not exist) and
/// the fallback on macOS when the bundled FFmpeg is unavailable.
///
/// Output contracts mirror the FFmpeg path so callers cannot tell them apart:
/// - `convert(fileURL:)` → 16 kHz mono Float32 WAV in `$TMPDIR/macparakeet/`.
/// - `mixToM4A` with one input → 16 kHz mono AAC 32 kb/s (Apple's encoder
///   refuses FFmpeg's 64 kb/s at that rate).
/// - `mixToM4A` with two inputs (microphone, system) → 48 kHz **stereo** AAC
///   128 kb/s, channel 1 = microphone, channel 2 = system, each delayed by its
///   `MeetingSourceAlignment` start offset, duration = the longer track.
/// - `mixToM4A` with more inputs → 16 kHz mono AAC, inputs averaged.
///
/// Container support is whatever AVFoundation decodes on the platform (wav,
/// m4a/aac, mp3, flac, aiff, caf, and the audio track of mp4/mov/m4v). ogg,
/// opus, mkv and webm stay FFmpeg-only; asking for them throws
/// `unsupportedFormat` rather than failing half-way.
///
/// See docs/plans/splay-ios-utility-layer.md (slice 2).
public final class AVFoundationAudioFileConverter: AudioFileConverting, Sendable {
    public static let supportedExtensions: Set<String> = [
        "wav", "m4a", "aac", "mp3", "flac", "aiff", "aif", "caf", "mp4", "mov", "m4v"
    ]

    public static func isSupported(extension ext: String) -> Bool {
        supportedExtensions.contains(ext.lowercased())
    }

    private static let logger = Logger(subsystem: "com.macparakeet.core", category: "AVFoundationAudioFileConverter")

    public init() {}

    // MARK: - AudioFileConverting

    public func convert(fileURL: URL) async throws -> URL {
        let ext = fileURL.pathExtension.lowercased()
        guard Self.isSupported(extension: ext) else {
            throw AudioProcessorError.unsupportedFormat(ext)
        }
        let outputURL = try Self.ensureTempDir().appendingPathComponent("\(UUID().uuidString).wav")
        do {
            try await Task.detached(priority: .userInitiated) {
                try await Self.decodeToWAV(inputURL: fileURL, outputURL: outputURL)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        return outputURL
    }

    public func mixToM4A(
        inputURLs: [URL],
        outputURL: URL,
        sourceAlignment: MeetingSourceAlignment?
    ) async throws {
        guard !inputURLs.isEmpty else {
            throw AudioProcessorError.conversionFailed("No audio files to mix")
        }
        let plan: MixPlan
        if inputURLs.count == 2 {
            plan = MixPlan(
                sampleRate: 48_000,
                channels: 2,
                bitRate: 128_000,
                delaysMs: [
                    max(0, sourceAlignment?.microphone?.startOffsetMs ?? 0),
                    max(0, sourceAlignment?.system?.startOffsetMs ?? 0)
                ]
            )
        } else {
            // Apple's AAC encoder caps the bit rate by sample rate; 64 kb/s (the
            // FFmpeg figure) is refused at 16 kHz mono, 32 kb/s is transparent for speech.
            plan = MixPlan(sampleRate: 16_000, channels: 1, bitRate: 32_000, delaysMs: Array(repeating: 0, count: inputURLs.count))
        }
        do {
            try await Task.detached(priority: .userInitiated) {
                try await Self.mix(inputURLs: inputURLs, outputURL: outputURL, plan: plan)
            }.value
        } catch {
            // Contract shared with the FFmpeg path: no partial output left behind.
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    // MARK: - Decode

    private struct MixPlan: Sendable {
        let sampleRate: Double
        let channels: AVAudioChannelCount
        let bitRate: Int
        let delaysMs: [Int]
    }

    /// Reads the first audio track of `inputURL` as non-interleaved Float32 at the
    /// requested rate/channel count. AVAssetReader does the resampling and downmix.
    private final class PCMSource {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let format: AVAudioFormat
        private var carry: [Float] = []
        private var carryOffset = 0
        private var pendingSilence: Int
        private(set) var exhausted = false

        init(url: URL, sampleRate: Double, channels: AVAudioChannelCount, leadingSilenceFrames: Int) async throws {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else {
                throw AudioProcessorError.conversionFailed("No audio track in \(url.lastPathComponent)")
            }
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
                throw AudioProcessorError.conversionFailed("Unsupported PCM format \(sampleRate) Hz × \(channels)")
            }
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: true
            ]
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw AudioProcessorError.conversionFailed("AVAssetReader cannot read \(url.lastPathComponent)")
            }
            reader.add(output)
            guard reader.startReading() else {
                throw AudioProcessorError.conversionFailed(reader.error?.localizedDescription ?? "AVAssetReader failed to start")
            }
            self.reader = reader
            self.output = output
            self.format = format
            self.pendingSilence = leadingSilenceFrames
        }

        /// Next decoded chunk as one PCM buffer (mono or interleaved-by-plane), or nil at end.
        func nextBuffer() throws -> AVAudioPCMBuffer? {
            guard let sample = output.copyNextSampleBuffer() else {
                if reader.status == .failed {
                    throw AudioProcessorError.conversionFailed(reader.error?.localizedDescription ?? "AVAssetReader failed")
                }
                exhausted = true
                return nil
            }
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0 else { return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) }
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
                throw AudioProcessorError.conversionFailed("Failed to allocate PCM buffer")
            }
            pcm.frameLength = AVAudioFrameCount(frames)
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sample, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList
            )
            guard status == noErr else {
                throw AudioProcessorError.conversionFailed("CMSampleBufferCopyPCMDataIntoAudioBufferList failed: \(status)")
            }
            return pcm
        }

        /// Mono read of exactly `count` frames (zero-padded after the end).
        /// Returns nil once the source is exhausted *and* nothing is buffered.
        func readMono(_ count: Int) throws -> [Float]? {
            var out = [Float](repeating: 0, count: count)
            var filled = 0
            while filled < count {
                if pendingSilence > 0 {
                    let n = min(pendingSilence, count - filled)
                    filled += n
                    pendingSilence -= n
                    continue
                }
                if carryOffset < carry.count {
                    let n = min(carry.count - carryOffset, count - filled)
                    out.replaceSubrange(filled..<(filled + n), with: carry[carryOffset..<(carryOffset + n)])
                    filled += n
                    carryOffset += n
                    continue
                }
                guard let pcm = try nextBuffer() else { break }
                guard let channel = pcm.floatChannelData?[0] else { break }
                carry = Array(UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
                carryOffset = 0
            }
            if filled == 0 && exhausted { return nil }
            return out
        }
    }

    private static func decodeToWAV(inputURL: URL, outputURL: URL) async throws {
        let source = try await PCMSource(url: inputURL, sampleRate: 16_000, channels: 1, leadingSilenceFrames: 0)
        let file = try AVAudioFile(forWriting: outputURL, settings: source.format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var written: AVAudioFrameCount = 0
        while let pcm = try source.nextBuffer() {
            guard pcm.frameLength > 0 else { continue }
            try file.write(from: pcm)
            written += pcm.frameLength
        }
        guard written > 0 else {
            throw AudioProcessorError.conversionFailed("No audio decoded from \(inputURL.lastPathComponent)")
        }
    }

    // MARK: - Mix

    private static func mix(inputURLs: [URL], outputURL: URL, plan: MixPlan) async throws {
        var sources: [PCMSource] = []
        for (index, url) in inputURLs.enumerated() {
            let silence = Int(Double(plan.delaysMs[index]) / 1000 * plan.sampleRate)
            sources.append(try await PCMSource(url: url, sampleRate: plan.sampleRate, channels: 1, leadingSilenceFrames: silence))
        }
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: plan.sampleRate, channels: plan.channels, interleaved: false) else {
            throw AudioProcessorError.conversionFailed("Unsupported output format")
        }

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: plan.sampleRate,
            AVNumberOfChannelsKey: plan.channels,
            AVEncoderBitRateKey: plan.bitRate
        ]
        if plan.channels == 2 {
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
            settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw AudioProcessorError.conversionFailed("AVAssetWriter cannot add audio input")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw AudioProcessorError.conversionFailed(writer.error?.localizedDescription ?? "AVAssetWriter failed to start")
        }
        writer.startSession(atSourceTime: .zero)

        let factory = PCMBufferToSampleBuffer()
        let chunk = 4096
        var written: Int64 = 0
        let stereoSplit = plan.channels == 2 && sources.count == 2
        let scale: Float = stereoSplit ? 1 : 1 / Float(sources.count)

        while true {
            var planes: [[Float]] = []
            var anyData = false
            for source in sources {
                if let mono = try source.readMono(chunk) {
                    planes.append(mono)
                    anyData = true
                } else {
                    planes.append([Float](repeating: 0, count: chunk))
                }
            }
            guard anyData else { break }

            guard let pcm = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(chunk)) else {
                throw AudioProcessorError.conversionFailed("Failed to allocate mix buffer")
            }
            pcm.frameLength = AVAudioFrameCount(chunk)
            guard let channels = pcm.floatChannelData else {
                throw AudioProcessorError.conversionFailed("Mix buffer has no channel data")
            }
            if stereoSplit {
                planes[0].withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: chunk) }
                planes[1].withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: chunk) }
            } else {
                for i in 0..<chunk {
                    var sum: Float = 0
                    for plane in planes { sum += plane[i] }
                    channels[0][i] = sum * scale
                }
            }

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let sampleBuffer = try factory.makeSampleBuffer(from: pcm, presentationTimeSamples: written)
            guard input.append(sampleBuffer) else {
                throw AudioProcessorError.conversionFailed(writer.error?.localizedDescription ?? "AVAssetWriter append failed")
            }
            written += Int64(chunk)
        }

        guard written > 0 else {
            throw AudioProcessorError.conversionFailed("No audio decoded for mix")
        }
        input.markAsFinished()
        let finished = SendableWriter(writer)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finished.writer.finishWriting { continuation.resume() }
        }
        if let error = finished.writer.error {
            throw AudioProcessorError.conversionFailed(error.localizedDescription)
        }
        logger.debug("avfoundation_mix_done inputs=\(inputURLs.count, privacy: .public) frames=\(written, privacy: .public) channels=\(plan.channels, privacy: .public)")
    }

    // MARK: - Helpers

    /// `AVAssetWriter` is not Sendable; it is only touched from the mix task and
    /// its own completion handler, which runs after every other use has finished.
    private final class SendableWriter: @unchecked Sendable {
        let writer: AVAssetWriter
        init(_ writer: AVAssetWriter) { self.writer = writer }
    }

    private static func ensureTempDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macparakeet", isDirectory: true)
        if !FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        }
        return tempDir
    }
}

import AVFoundation
import XCTest
@testable import SplayCore

/// Exercises the AVFoundation converter end to end on synthetic fixtures. This is
/// the iOS conversion path; the tests run on macOS because AVFoundation is the
/// same framework on both.
final class AVFoundationAudioFileConverterTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("avf-converter-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Fixtures

    /// Writes a `seconds`-long sine at `frequency` Hz as a stereo/mono WAV at `sampleRate`.
    private func makeWAV(name: String, seconds: Double = 2, sampleRate: Double = 48_000, channels: AVAudioChannelCount = 2, frequency: Double = 440, amplitude: Float = 0.5) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let data = buffer.floatChannelData![channel]
            for i in 0..<Int(frames) {
                data[i] = amplitude * Float(sin(2 * .pi * frequency * Double(i) / sampleRate))
            }
        }
        try file.write(from: buffer)
        return url
    }

    private func readAll(_ url: URL) throws -> (format: AVAudioFormat, planes: [[Float]]) {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        var planes: [[Float]] = []
        for c in 0..<Int(file.processingFormat.channelCount) {
            planes.append(Array(UnsafeBufferPointer(start: buffer.floatChannelData![c], count: Int(buffer.frameLength))))
        }
        return (file.processingFormat, planes)
    }

    private func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }

    // MARK: - convert

    func testConvertProduces16kMonoFloatWAV() async throws {
        let input = try makeWAV(name: "stereo48k.wav")
        let converter = AVFoundationAudioFileConverter()

        let output = try await converter.convert(fileURL: input)
        defer { try? FileManager.default.removeItem(at: output) }

        XCTAssertEqual(output.pathExtension, "wav")
        let (format, planes) = try readAll(output)
        XCTAssertEqual(format.sampleRate, 16_000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(Double(planes[0].count) / 16_000, 2, accuracy: 0.05, "duration should survive resampling")
        XCTAssertGreaterThan(rms(planes[0][...]), 0.2, "resampled sine should keep its energy")
    }

    func testConvertRejectsFormatsAVFoundationCannotDecode() async {
        let converter = AVFoundationAudioFileConverter()
        do {
            _ = try await converter.convert(fileURL: scratch.appendingPathComponent("clip.ogg"))
            XCTFail("ogg must be refused up front, not fail half-way")
        } catch let error as AudioProcessorError {
            guard case .unsupportedFormat(let ext) = error else { return XCTFail("wrong error: \(error)") }
            XCTAssertEqual(ext, "ogg")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testConvertMissingFileThrowsAndLeavesNoOutput() async throws {
        let converter = AVFoundationAudioFileConverter()
        let before = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.appendingPathComponent("macparakeet").path).count
        do {
            _ = try await converter.convert(fileURL: scratch.appendingPathComponent("missing.m4a"))
            XCTFail("missing input must throw")
        } catch {
            // expected
        }
        let after = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.appendingPathComponent("macparakeet").path).count
        XCTAssertEqual(after, before, "no partial WAV may be left behind")
    }

    // MARK: - mixToM4A

    func testMixSingleInputWritesMono16kAAC() async throws {
        let input = try makeWAV(name: "mic.wav")
        let output = scratch.appendingPathComponent("meeting.m4a")

        try await AVFoundationAudioFileConverter().mixToM4A(inputURLs: [input], outputURL: output)

        let (format, planes) = try readAll(output)
        XCTAssertEqual(format.sampleRate, 16_000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(Double(planes[0].count) / 16_000, 2, accuracy: 0.15, "AAC priming/padding may add a few ms")
        XCTAssertGreaterThan(rms(planes[0][...]), 0.2)
    }

    func testMixTwoInputsKeepsMicLeftSystemRightAndAppliesOffsets() async throws {
        // Distinct tones so the channels can be told apart after encoding.
        let mic = try makeWAV(name: "microphone.wav", seconds: 1, channels: 1, frequency: 440)
        let system = try makeWAV(name: "system.wav", seconds: 2, channels: 1, frequency: 1000)
        let output = scratch.appendingPathComponent("meeting.m4a")
        let alignment = MeetingSourceAlignment(
            meetingOriginHostTime: nil,
            microphone: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 500, writtenFrameCount: 48_000, sampleRate: 48_000),
            system: .init(firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 96_000, sampleRate: 48_000)
        )

        try await AVFoundationAudioFileConverter().mixToM4A(inputURLs: [mic, system], outputURL: output, sourceAlignment: alignment)

        let (format, planes) = try readAll(output)
        XCTAssertEqual(format.sampleRate, 48_000)
        XCTAssertEqual(format.channelCount, 2)
        let left = planes[0], right = planes[1]
        // Longest track wins: system is 2 s, mic is 0.5 s delay + 1 s.
        XCTAssertEqual(Double(left.count) / 48_000, 2, accuracy: 0.2)
        // Mic (left) is silent for its 500 ms offset, then live.
        XCTAssertLessThan(rms(left[0..<20_000]), 0.02, "left channel must be silent during the microphone offset")
        XCTAssertGreaterThan(rms(left[30_000..<60_000]), 0.2, "left channel carries the microphone after its offset")
        // System (right) is live from the start.
        XCTAssertGreaterThan(rms(right[0..<20_000]), 0.2, "right channel carries system audio from t=0")
    }

    func testMixEmptyInputsThrows() async {
        do {
            try await AVFoundationAudioFileConverter().mixToM4A(inputURLs: [], outputURL: scratch.appendingPathComponent("x.m4a"))
            XCTFail("empty inputs must throw")
        } catch let error as AudioProcessorError {
            guard case .conversionFailed = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testMixFailureLeavesNoPartialOutput() async throws {
        let output = scratch.appendingPathComponent("meeting.m4a")
        do {
            try await AVFoundationAudioFileConverter().mixToM4A(inputURLs: [scratch.appendingPathComponent("missing.m4a")], outputURL: output)
            XCTFail("missing input must throw")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "no partial m4a may be left behind")
        }
    }
}

import AVFoundation
import Darwin
import SplayCore
import SwiftUI

// SplayBench: run Parakeet v3 through SplayCore's STT plane on a real iPhone and
// report real-time factor, memory footprint, and thermal state. Everything it
// prints also goes to stdout so `devicectl … launch --console` can stream it to
// the Mac. See docs/plans/splay-ios-utility-layer.md (slice 1).

@main
struct SplayBenchApp: App {
    var body: some Scene {
        WindowGroup {
            BenchView()
        }
    }
}

struct BenchView: View {
    @State private var model = BenchModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button(model.isRunning ? "Running…" : "Run again") {
                Task { await model.run() }
            }
            .disabled(model.isRunning)
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .task { await model.run() }
    }
}

@MainActor
@Observable
final class BenchModel {
    private(set) var lines: [String] = []
    private(set) var isRunning = false

    private let fixtureName = "bench-16k"
    private let warmRuns = 3
    private let sustainedRuns = 10

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        lines.removeAll()

        do {
            try await runBench()
        } catch {
            log("FAILED: \(error)")
        }
    }

    // MARK: - Bench

    private func runBench() async throws {
        log("Splay Bench — Parakeet v3 via SplayCore.STTClient")
        log("device=\(Self.hardwareModel()) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        log("ram=\(Self.formatMB(ProcessInfo.processInfo.physicalMemory)) thermal=\(Self.thermalLabel()) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")

        guard let fixtureURL = Bundle.main.url(forResource: fixtureName, withExtension: "wav") else {
            throw BenchError.missingFixture
        }
        let audioFile = try AVAudioFile(forReading: fixtureURL)
        let audioSeconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        log(String(format: "fixture=%@.wav duration=%.1fs sr=%.0f", fixtureName, audioSeconds, audioFile.fileFormat.sampleRate))

        let cached = STTClient.isModelCached(version: .v3)
        log("model_cached=\(cached) (first run downloads ~600 MB from Hugging Face)")
        log("footprint_before_load=\(Self.formatMB(Self.physicalFootprint()))")

        let client = STTClient(modelVersion: .v3)
        let loadStart = ContinuousClock.now
        try await client.warmUp(onProgress: { message in
            Task { @MainActor in
                BenchModel.stdout("  warmup: \(message)")
            }
        })
        let loadSeconds = Self.seconds(since: loadStart)
        log(String(format: "model_%@_seconds=%.2f footprint_after_load=%@",
                   cached ? "load" : "download_and_load", loadSeconds,
                   Self.formatMB(Self.physicalFootprint())))

        var results: [RunResult] = []

        log("— warm runs (\(warmRuns)) —")
        for index in 1...warmRuns {
            let result = try await timedTranscribe(client: client, path: fixtureURL.path, audioSeconds: audioSeconds)
            results.append(result)
            log(String(format: "run %d: %.2fs rtf=%.1fx footprint=%@ thermal=%@ words=%d",
                       index, result.seconds, result.rtf, Self.formatMB(result.footprint), result.thermal, result.wordCount))
            if index == 1 {
                log("  text: \(result.text.prefix(160))…")
            }
        }

        log("— sustained (\(sustainedRuns) back-to-back, \(Int(audioSeconds) * sustainedRuns)s of audio) —")
        let sustainedStart = ContinuousClock.now
        var sustained: [RunResult] = []
        for index in 1...sustainedRuns {
            let result = try await timedTranscribe(client: client, path: fixtureURL.path, audioSeconds: audioSeconds)
            sustained.append(result)
            if index % 5 == 0 || index == sustainedRuns {
                log(String(format: "  after %d: rtf=%.1fx footprint=%@ thermal=%@",
                           index, result.rtf, Self.formatMB(result.footprint), result.thermal))
            }
        }
        let sustainedSeconds = Self.seconds(since: sustainedStart)
        let sustainedRTF = (audioSeconds * Double(sustainedRuns)) / sustainedSeconds
        let peakFootprint = (results + sustained).map(\.footprint).max() ?? 0
        log(String(format: "sustained_total=%.1fs sustained_rtf=%.1fx peak_footprint=%@ thermal_end=%@",
                   sustainedSeconds, sustainedRTF, Self.formatMB(peakFootprint), Self.thermalLabel()))

        let summary = BenchSummary(
            device: Self.hardwareModel(),
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            fixtureSeconds: audioSeconds,
            modelCachedAtStart: cached,
            modelLoadSeconds: loadSeconds,
            warmRuns: results,
            sustainedRuns: sustained,
            sustainedRTF: sustainedRTF,
            peakFootprintBytes: peakFootprint,
            thermalAtEnd: Self.thermalLabel()
        )
        let outputURL = try Self.writeSummary(summary)
        log("wrote \(outputURL.lastPathComponent) to Documents (Files app → Splay Bench)")
        log("done")
    }

    private func timedTranscribe(client: STTClient, path: String, audioSeconds: Double) async throws -> RunResult {
        let start = ContinuousClock.now
        let result = try await client.transcribe(audioPath: path, job: .fileTranscription, onProgress: nil)
        let seconds = Self.seconds(since: start)
        return RunResult(
            seconds: seconds,
            rtf: audioSeconds / max(seconds, 0.001),
            footprint: Self.physicalFootprint(),
            thermal: Self.thermalLabel(),
            wordCount: result.words.count,
            text: result.text
        )
    }

    // MARK: - Logging

    private func log(_ line: String) {
        lines.append(line)
        Self.stdout(line)
    }

    nonisolated static func stdout(_ line: String) {
        print("[bench] \(line)")
        fflush(Darwin.stdout)
    }

    // MARK: - Measurements

    nonisolated static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    /// Resident + compressed + IOKit-backed memory attributed to this process —
    /// the number Xcode's memory gauge and jetsam use.
    nonisolated static func physicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    nonisolated static func thermalLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    nonisolated static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    nonisolated static func formatMB(_ bytes: UInt64) -> String {
        String(format: "%.0fMB", Double(bytes) / 1_048_576)
    }

    nonisolated static func writeSummary(_ summary: BenchSummary) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = documents.appendingPathComponent("splay-bench-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

struct RunResult: Codable, Sendable {
    let seconds: Double
    let rtf: Double
    let footprint: UInt64
    let thermal: String
    let wordCount: Int
    let text: String
}

struct BenchSummary: Codable, Sendable {
    let device: String
    let os: String
    let fixtureSeconds: Double
    let modelCachedAtStart: Bool
    let modelLoadSeconds: Double
    let warmRuns: [RunResult]
    let sustainedRuns: [RunResult]
    let sustainedRTF: Double
    let peakFootprintBytes: UInt64
    let thermalAtEnd: String
}

enum BenchError: Error {
    case missingFixture
}

import SwiftUI

// MARK: - Voice meter (recording, left slot)

/// The recording meter the owner picked in the live prototype tuner (2026-09-26,
/// variant D — the Voice Memos layout: bars left, timer right). It answers one
/// question: *is Splay taking in my voice right now?* Silent-but-alive rests flat
/// at `silentHeight`; speech lifts the bars; a dead input is drawn motionless in
/// amber by the caller (dead ≠ silent). See `docs/plans/island-voice-meter.md`.
enum SplayMeterTuning {
    static let barCount = 5
    static let barWidth: CGFloat = 2
    static let barGap: CGFloat = 1.5
    static let maxHeight: CGFloat = 14
    static let silentHeight: CGFloat = 2
    /// Input is `micLevel` (per-buffer RMS × 10, clamped). Below `gate` counts as
    /// room hiss and stays flat; above it `sqrt` lifts quiet speech, then `gain`.
    static let gate: Double = 0.04
    static let gain: Double = 1.9
    /// Attack/release time constants (s): fast up, short fall — a meter, not a mood.
    static let attackTau: Double = 0.030
    static let releaseTau: Double = 0.160
    /// Centre bars peak highest (upstream `WaveformView`), outer bars fall off by this.
    static let centreFalloff: Double = 0.55
    /// Per-bar wobble depth so equal loudness still reads as a voice, not a block.
    static let wobble: Double = 0.25

    static var width: CGFloat { CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap }
}

enum SplayMeter {
    /// Map a raw `micLevel` (0…1) onto the meter's 0…1 drive: noise gate, then a
    /// square-root curve (quiet speech still moves the bars), then gain.
    static func shaped(_ raw: Double) -> Double {
        let clamped = min(1, max(0, raw))
        let gated = max(0, (clamped - SplayMeterTuning.gate) / (1 - SplayMeterTuning.gate))
        // The tuner's reference gain was 1.6, so `gain / 1.6` is its "×1".
        return min(1, gated.squareRoot() * SplayMeterTuning.gain / 1.6)
    }

    /// Heights for each bar at envelope `level` (0…1). `phase` (seconds) animates
    /// the per-bar wobble; pass nil for a still meter (Reduce Motion).
    static func barHeights(level: Double, phase: Double?) -> [CGFloat] {
        let n = SplayMeterTuning.barCount
        let centre = Double(n - 1) / 2
        let span = SplayMeterTuning.maxHeight - SplayMeterTuning.silentHeight
        return (0..<n).map { i -> CGFloat in
            let x = Double(i)
            let distance: Double = centre > 0 ? abs(x - centre) / centre : 0
            var wobble: Double = 1
            if let phase {
                let depth = SplayMeterTuning.wobble
                wobble = 1 - depth + depth * sin(phase * 11 + x * 1.7)
            }
            let shape: Double = 1 - distance * SplayMeterTuning.centreFalloff
            let l: Double = min(1, max(0, level * shape * wobble))
            return SplayMeterTuning.silentHeight + span * CGFloat(l)
        }
    }
}

/// A frame-rate-independent attack/release follower for the meter. A reference
/// type held in `@State`, so advancing it inside a `TimelineView` body doesn't
/// invalidate the view.
@MainActor
final class MeterEnvelope {
    private(set) var level: Double = 0
    private var lastT: Double?

    func advance(to target: Double, at t: Double) -> Double {
        let dt = lastT.map { min(0.1, max(0, t - $0)) } ?? 1.0 / 60
        lastT = t
        let tau = target > level ? SplayMeterTuning.attackTau : SplayMeterTuning.releaseTau
        level += (target - level) * (1 - exp(-dt / tau))
        return level
    }

    func reset() {
        level = 0
        lastT = nil
    }
}

struct SplayIslandMeter: View {
    /// Envelope-smoothed drive, 0…1.
    let level: Double
    /// Wobble phase in seconds; nil draws a still meter.
    let phase: Double?
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: SplayMeterTuning.barGap) {
            ForEach(Array(SplayMeter.barHeights(level: level, phase: phase).enumerated()), id: \.offset) { _, h in
                Capsule()
                    .fill(color)
                    .frame(width: SplayMeterTuning.barWidth, height: h)
            }
        }
        .frame(width: SplayMeterTuning.width, height: SplayMeterTuning.maxHeight)
    }
}

/// Elapsed recording time (right slot). `m:ss`, minutes unbounded, so it stays
/// five characters wide up to 99 minutes and never reaches the camera zone.
struct SplayIslandTimer: View {
    let seconds: Int
    let color: Color

    var body: some View {
        Text(Self.format(seconds))
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(color)
            .fixedSize()
    }

    static func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

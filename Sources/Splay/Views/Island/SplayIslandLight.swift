import SwiftUI

// The pill face stays flat, opaque #0B0813. State colour is carried by the glyphs
// alone: the ambient glow the handoff started with (desktop bloom, halo,
// talk-reactive sway) went on 2026-09-26 ("gimmicky"), and the thin fiber rim on
// 2026-09-27 ("the red halo"). The recording meter carries "I hear you"
// (docs/plans/island-voice-meter.md). This file owns the per-state palette +
// geometry and the recolorable three-stroke mark.
//
// The island is always near-black, so these colours are fixed sRGB (no
// light/dark adaptation) — they are the design's final intent, not tokens.

// MARK: - The nine indicator states

/// The discrete forms the island morphs through (handoff "Screen 1"). Distinct
/// from `MeetingRecordingPillViewModel.PillState`: idle splits into
/// dormant/ready, several flow states collapse onto one form, and copied /
/// warning / dropped are light-only forms driven later (Phase 2+).
enum SplayIslandState: Equatable, Hashable {
    case dormant, ready, recording, transcribing, done, copied, warning, failed, dropped
}

// MARK: - Palette

enum SplayLight {
    /// The pill face. Fully opaque — no transparency, no blur, no material.
    static let surface = Color(.sRGB, red: 0x0B / 255, green: 0x08 / 255, blue: 0x13 / 255, opacity: 1)
    /// Brand accent (#A99BF5) — the mark, ready glyphs, the ✦ action.
    static let accent = rgb(0xA9, 0x9B, 0xF5)
    /// Failed glyph (#F0837A) on the island (card danger uses #B3352F).
    static let failedGlyph = rgb(0xF0, 0x83, 0x7A)
    /// The recording red (meter, timer) — Voice-Memos-style.
    static let recordRed = rgb(0xFF, 0x5A, 0x52)
    /// A meeting's system-audio meter (tuner round 2026-09-26): a pale blue,
    /// fainter than the mic's red so "your voice" stays the loud signal.
    static let systemAudio = rgba(0x9F, 0xD3, 0xFF, 0.6)

    struct Palette {
        let fiber: Color      // the state colour: glyphs, mark (name kept from the retired rim)
    }

    /// The **brand** states (dormant / ready / dropped) wear the user's chosen
    /// accent (`SplayTheme` — the seven-accent palette). The **status** states
    /// (recording / transcribing / done / warning / failed) are semantic and never
    /// themed, per the palette export's `--state-*` note — transcribing joined the
    /// status set (2026-08-11) as the "processing" amber, completing the island's
    /// status-light lifecycle (recording red → transcribing amber → done green).
    @MainActor
    static func palette(for state: SplayIslandState) -> Palette {
        let accent = SplayTheme.shared.accent.islandBright   // the accent on the dark island
        switch state {
        case .dormant:
            return Palette(fiber: accent)
        case .ready:
            return Palette(fiber: accent)
        case .transcribing:
            // "Processing" amber — a semantic status colour (not themed) that reads
            // as the middle of the status-light lifecycle: recording red →
            // transcribing amber → done green. Same amber family as `.warning`
            // (they never co-occur). Red is reserved for recording, so amber is the
            // unambiguous "working" hue. The spinner arc uses this same colour.
            return Palette(fiber: rgb(0xF6, 0xC8, 0x6B))
        case .dropped:
            return Palette(fiber: accent)
        case .recording:
            return Palette(fiber: rgb(0xFF, 0x6B, 0x5E))
        case .done, .copied:
            return Palette(fiber: rgb(0x5F, 0xD9, 0xA0))
        case .warning:
            return Palette(fiber: rgb(0xF6, 0xC8, 0x6B))
        case .failed:
            return Palette(fiber: rgb(0xFF, 0x7A, 0x6E))
        }
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
    static func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Double) -> Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: a)
    }
}

// MARK: - Geometry (handoff tables)

enum SplayGeometry {
    /// The fixed camera-housing dead zone. Active content sits left of it and
    /// never runs under it (see `layout`).
    static let cameraDeadZone = CGSize(width: 180, height: 32)

    /// The compact resting nub — a quiet, hidden bar (symmetric under the notch).
    static let dormantWidth: CGFloat = 206
    /// The old hover step (clicks are off, so it is no longer reached; kept so
    /// `AppFeatures.islandTakesMouse` can bring it back).
    static let readyWidth: CGFloat = 248

    // Active states are asymmetric (owner, 2026-09-27): everything lives LEFT of
    // the camera, so the pill's length says what is running — dictation is just
    // the voice bars, a recording adds the timer, a meeting adds the system
    // bars. Right of the camera is only a short ear that rounds the pill off.
    static let activeHeight: CGFloat = 34
    /// Pill edge → first content.
    static let contentInset: CGFloat = 10
    /// Last content → camera housing.
    static let cameraGap: CGFloat = 6
    /// How far the pill reaches right of the camera.
    static let trailingEar: CGFloat = 12
    /// Meters → timer.
    static let slotGap: CGFloat = 8
    /// The timer's fixed slot (fits "99:59" at 12pt), so the pill never
    /// changes length as the seconds tick.
    static let timerWidth: CGFloat = 34
    /// One glyph (spinner, check, failed, mark).
    static let glyphWidth: CGFloat = 16

    /// Width of the content left of the camera for a state + capture kind.
    static func contentWidth(for state: SplayIslandState, kind: IslandCaptureKind) -> CGFloat {
        switch state {
        case .recording:
            let micMeter = SplayMeterTuning.width
            switch kind {
            case .dictation:
                return micMeter
            case .recording:
                return micMeter + slotGap + timerWidth
            case .meeting:
                let meters = micMeter + SplayMeterTuning.twinGap
                    + SplayMeterTuning.width(bars: SplayMeterTuning.systemBarCount)
                return meters + slotGap + timerWidth
            }
        case .transcribing, .done, .copied, .warning, .failed, .dropped:
            return glyphWidth
        case .dormant, .ready:
            return 0
        }
    }

    /// The pill's size and its horizontal offset from the camera's centre
    /// (negative = hangs left). Off the notch there is no camera: the pill
    /// hugs its content, centred.
    static func layout(
        for state: SplayIslandState, kind: IslandCaptureKind, notchAttached: Bool
    ) -> (size: CGSize, centerOffset: CGFloat) {
        switch state {
        case .dormant:
            return (CGSize(width: dormantWidth, height: 34), 0)
        case .ready:
            return (CGSize(width: readyWidth, height: 38), 0)
        case .recording, .transcribing, .done, .copied, .warning, .failed, .dropped:
            let content = contentWidth(for: state, kind: kind)
            guard notchAttached else {
                return (CGSize(width: content + 2 * contentInset, height: activeHeight), 0)
            }
            let left = contentInset + content + cameraGap
            let width = left + cameraDeadZone.width + trailingEar
            return (CGSize(width: width, height: activeHeight), (trailingEar - left) / 2)
        }
    }

    /// Bottom-corner radius per state (top corners are square — the pill's top
    /// edge is flush with the physical screen top).
    static func bottomRadius(for state: SplayIslandState) -> CGFloat {
        state == .ready ? 19 : 17
    }
}

// MARK: - The three-stroke wind mark (handoff SVG, recolorable)

/// The Splay mark, lifted from the handoff prototype: three paths at 100/90/60%
/// opacity in a `viewBox="180 180 640 660"`. Rendered from vectors so it stays
/// crisp at 16px, takes any colour, and can breathe.
struct SplayGlyph: View {
    var color: Color = SplayLight.accent

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 640, sy = size.height / 660
            let t = CGAffineTransform(translationX: -180, y: -180)
                .concatenating(CGAffineTransform(scaleX: sx, y: sy))
            for (path, opacity) in Self.strokes {
                ctx.fill(path.applying(t), with: .color(color.opacity(opacity)))
            }
        }
        .accessibilityLabel("Splay")
    }

    private static let strokes: [(Path, Double)] = [
        (stroke(move: (452, 234), c1: (418, 405), c2: (344, 623), to: (268, 780),
                c3: (390, 639), c4: (463, 420), back: (452, 234)), 1.0),
        (stroke(move: (508, 214), c1: (478, 391), c2: (474, 628), to: (500, 806),
                c3: (530, 629), c4: (534, 392), back: (508, 214)), 0.9),
        (stroke(move: (566, 234), c1: (554, 420), c2: (627, 638), to: (748, 780),
                c3: (673, 623), c4: (600, 405), back: (566, 234)), 0.6)
    ]

    private static func stroke(
        move: (CGFloat, CGFloat), c1: (CGFloat, CGFloat), c2: (CGFloat, CGFloat), to: (CGFloat, CGFloat),
        c3: (CGFloat, CGFloat), c4: (CGFloat, CGFloat), back: (CGFloat, CGFloat)
    ) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: move.0, y: move.1))
        p.addCurve(to: CGPoint(x: to.0, y: to.1), control1: CGPoint(x: c1.0, y: c1.1), control2: CGPoint(x: c2.0, y: c2.1))
        p.addCurve(to: CGPoint(x: back.0, y: back.1), control1: CGPoint(x: c3.0, y: c3.1), control2: CGPoint(x: c4.0, y: c4.1))
        p.closeSubpath()
        return p
    }
}

// MARK: - Animation helpers (handoff §Animations)

enum SplayMotion {
    /// Mark breathe: scale 1…1.08, opacity 0.85…1.
    static func breathe(_ time: Double, period: Double) -> (Double, Double) {
        let f = (time.truncatingRemainder(dividingBy: period)) / period
        let e = 0.5 - 0.5 * cos(f * 2 * .pi)
        return (0.85 + 0.15 * e, 1.0 + 0.08 * e)
    }
}

// MARK: - Cheap breathing (compositor-driven; no per-frame body rebuild)

/// Animates scale + opacity between two values with a slow repeatForever, driven
/// by CoreAnimation so the wrapped Canvas/blur is not rebuilt every frame. Used
/// for the always-on idle island.
struct Breathe: ViewModifier {
    let period: Double
    let scaleRange: ClosedRange<Double>
    let opacityRange: ClosedRange<Double>
    var animate: Bool = true
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? scaleRange.upperBound : scaleRange.lowerBound)
            .opacity(on ? opacityRange.upperBound : opacityRange.lowerBound)
            .onAppear {
                guard animate else { return }
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

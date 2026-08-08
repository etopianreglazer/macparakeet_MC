import SwiftUI

// The island's whole identity is the *light behind it* (design handoff:
// docs/design/splay-island-handoff/README.md, "The light (the whole point)").
// The pill face stays flat, opaque #0B0813; colour only radiates outward into
// the wallpaper via two blurred blooms plus a car-interior "fiber stripe" that
// traces the pill's silhouette. This file owns that light, the exact per-state
// palette/geometry from the handoff, and the recolorable three-stroke mark.
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
    /// The record dot (Voice-Memos-style) shown in the ready state.
    static let recordRed = rgb(0xFF, 0x5A, 0x52)

    struct Palette {
        let bloom: Color      // ambient bloom colour (carries its own alpha)
        let bloomHue: Color   // the same hue, fully opaque — for the pill's leaning halo
        let fiber: Color      // the solid fiber line
        let fiberSoft: Color  // the fiber's bloom (carries its own alpha)
    }

    /// Active-state bloom is deliberately dim (`SplayGlowTuning.peak`): the wide
    /// wash is a faint haze and the pill's own leaning halo carries the presence.
    ///
    /// The **brand** states (dormant / ready / transcribing / dropped) wear the
    /// user's chosen accent (`SplayTheme` — the seven-accent palette). The
    /// **status** states (recording / done / warning / failed) are semantic and
    /// never themed, per the palette export's `--state-*` note.
    @MainActor
    static func palette(for state: SplayIslandState) -> Palette {
        let peak = SplayGlowTuning.peak
        let accent = SplayTheme.shared.accent.islandBright   // the accent on the dark island
        switch state {
        case .dormant:
            return brandPalette(accent, bloomAlpha: 0.30, fiberSoftAlpha: 0.5)
        case .ready:
            return brandPalette(accent, bloomAlpha: peak, fiberSoftAlpha: 0.7)
        case .transcribing, .dropped:
            return brandPalette(accent, bloomAlpha: peak, fiberSoftAlpha: 0.7)
        case .recording:
            // Light-vector model (2026-08-07): one soft, dim, contained light whose
            // *direction* sways on a slow organic path (see SplayGlowTuning /
            // SplayMotion.lightVector) — no visible moving source, just the island's
            // own lighting shifting. Reference: Philips Ambilight bias light.
            return Palette(bloom: rgba(232, 84, 72, peak), bloomHue: rgb(232, 84, 72), fiber: rgb(0xFF, 0x6B, 0x5E), fiberSoft: rgba(255, 90, 74, 0.75))
        case .done, .copied:
            return Palette(bloom: rgba(72, 196, 143, peak), bloomHue: rgb(72, 196, 143), fiber: rgb(0x5F, 0xD9, 0xA0), fiberSoft: rgba(76, 206, 150, 0.7))
        case .warning:
            return Palette(bloom: rgba(244, 190, 89, peak), bloomHue: rgb(244, 190, 89), fiber: rgb(0xF6, 0xC8, 0x6B), fiberSoft: rgba(244, 190, 89, 0.7))
        case .failed:
            return Palette(bloom: rgba(236, 86, 74, peak), bloomHue: rgb(236, 86, 74), fiber: rgb(0xFF, 0x7A, 0x6E), fiberSoft: rgba(240, 110, 96, 0.75))
        }
    }

    /// A brand-state palette derived from the single accent colour: the bloom is
    /// the accent at a state alpha; the fiber + leaning halo use the accent opaque.
    private static func brandPalette(_ c: Color, bloomAlpha: Double, fiberSoftAlpha: Double) -> Palette {
        Palette(bloom: c.opacity(bloomAlpha), bloomHue: c, fiber: c, fiberSoft: c.opacity(fiberSoftAlpha))
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
    static func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Double) -> Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: a)
    }
}

// MARK: - Glow tuning (dialed live 2026-08-07 in the motion tuner)

/// The recording-glow "look" the user landed on in the live tuner. The island's
/// glow is a single soft, dim, contained light whose *direction* sways on a slow
/// organic (Lissajous) path — there is no visible moving source; only the
/// island's own lighting shifts. The pill's leaning halo carries the presence.
enum SplayGlowTuning {
    static let footprint: CGFloat = 490   // contained island-light width
    static let blurL1: CGFloat = 90       // very soft haze
    static let blurL2: CGFloat = 63
    static let peak: Double = 0.20        // dim ambient bloom (the halo carries presence)
    static let sway: Double = 15          // how far the lighting leans (small ⇒ no visible source)
    static let speed: Double = 0.20       // how fast the direction travels
    static let swirl: Double = 2.1        // organic path (not a plain circle)
    static let haloRadius: CGFloat = 26   // the soft glow hugging the pill
    static let haloOpacity: Double = 0.64
    static let rimOpacity: Double = 0.40
}

// MARK: - Geometry (handoff tables)

enum SplayGeometry {
    /// The fixed camera-housing dead zone reserved at the pill's centre; content
    /// splits into a left + right cluster around it and never runs under it.
    static let cameraDeadZone = CGSize(width: 180, height: 32)

    /// The single width the island grows to for any *active* state. Live feedback
    /// (2026-08-07): the old per-state widths (240/244/248/264/300) made the pill
    /// wobble as it morphed recording → transcribing → done. There is now ONE
    /// active width — the island's max — so the whole active lifecycle is a stable
    /// bar that never re-sizes between states; only idle→ready→active step it up.
    static let maxWidth: CGFloat = 280

    /// The compact resting nub (idle looks good — left unchanged).
    static let dormantWidth: CGFloat = 206
    /// The hover/ready step: clearly wider AND taller than dormant so touching the
    /// nub visibly grows it (the hover response the resting nub was missing).
    static let readyWidth: CGFloat = 248

    /// Pill width / height per state. Three widths total (dormant → ready → active
    /// max) so the morph reads as deliberate growth, never a jittering re-size.
    static func size(for state: SplayIslandState) -> CGSize {
        switch state {
        case .dormant:      return CGSize(width: dormantWidth, height: 34)
        case .ready:        return CGSize(width: readyWidth, height: 38)
        // Every active state shares the max width + one height → zero wobble as the
        // lifecycle advances. Recording sits at the island's largest size.
        case .recording, .transcribing, .done, .copied,
             .warning, .failed, .dropped:
            return CGSize(width: maxWidth, height: 38)
        }
    }

    /// Bottom-corner radius per state (top corners are square — the pill's top
    /// edge is flush with the physical screen top). Two radii only, tracking the
    /// two heights above, so the corner never wobbles across the active lifecycle.
    static func bottomRadius(for state: SplayIslandState) -> CGFloat {
        state == .dormant ? 17 : 19
    }

    /// Ambient bloom layer 1: size + base opacity (top:-70 relative to pill top).
    /// Opacities are ~25% above the handoff table: the glow lives on the desktop
    /// now (below windows), so it can be a little fuller without distracting.
    static func bloomL1(for state: SplayIslandState) -> (CGSize, Double) {
        // Dormant keeps its accepted idle glow; every other state uses the single
        // contained island-light footprint (tuner "light size" 490 → base ~510×357).
        if state == .dormant { return (CGSize(width: 440, height: 210), 0.34) }
        let w = SplayGlowTuning.footprint * 1.04
        return (CGSize(width: w, height: w * 0.7), 1.0)
    }

    /// Ambient bloom layer 2 (the tighter core): width + base opacity.
    static func bloomL2(for state: SplayIslandState) -> (CGFloat, Double) {
        if state == .dormant { return (300, 0.18) }
        return (SplayGlowTuning.footprint * 0.62, 1.0)   // ~304 core
    }
}

// MARK: - Ambient bloom (two blurred radial gradients painted behind the pill)

/// The colour never touches the pill's face — it radiates outward into the
/// wallpaper. Layer 1 is a broad soft halo; layer 2 a tighter, brighter core.
/// `intensity` (0…1) modulates opacity/scale: for recording it is fed by the
/// live audio level + the irregular `voice` beat so it reads as a level meter;
/// otherwise a slow `latent` breath.
struct SplayAmbientBloom: View {
    let state: SplayIslandState
    let pillWidth: CGFloat
    /// The light "vector": a small directional offset that leans the whole light,
    /// so the island's lighting *direction* shifts with no visible moving source.
    var sway: CGSize = .zero

    var body: some View {
        let color = SplayLight.palette(for: state).bloom
        let (l1Size, l1Op) = SplayGeometry.bloomL1(for: state)
        let (l2Width, l2Op) = SplayGeometry.bloomL2(for: state)
        // Centre the glow on the pill's vertical middle, then lean it by the sway
        // vector. Both layers move together, so the light stays one cohesive body
        // that leans directionally rather than splitting into visible blobs.
        let center = SplayGeometry.size(for: state).height / 2
        let dormant = state == .dormant
        let b1: CGFloat = dormant ? 62 : SplayGlowTuning.blurL1
        let b2: CGFloat = dormant ? 30 : SplayGlowTuning.blurL2
        let l2Height: CGFloat = dormant ? 110 : l2Width * 0.66
        ZStack(alignment: .top) {
            bloom(color: color, size: l1Size, endFraction: 0.92, blur: b1)
                .opacity(l1Op)
                .offset(x: sway.width, y: center + sway.height)
            bloom(color: color, size: CGSize(width: l2Width, height: l2Height), endFraction: 0.90, blur: b2)
                .opacity(l2Op)
                .offset(x: sway.width, y: center + sway.height)
        }
        .frame(width: pillWidth, height: 0, alignment: .top)   // anchor to pill top-centre
        .allowsHitTesting(false)
    }

    private func bloom(color: Color, size: CGSize, endFraction: Double, blur: CGFloat) -> some View {
        Rectangle()
            .fill(
                EllipticalGradient(
                    // A gradual, multi-stop falloff — the Ambilight quality. A single
                    // colour→transparent stop reads as a hard-edged disc; easing the
                    // alpha down over several stops makes the light fade like real
                    // bias lighting spilling onto a wall.
                    gradient: Gradient(stops: [
                        .init(color: color, location: 0),
                        .init(color: color.opacity(0.55), location: endFraction * 0.42),
                        .init(color: color.opacity(0.18), location: endFraction * 0.74),
                        .init(color: color.opacity(0), location: endFraction)
                    ]),
                    center: .center,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
            )
            .frame(width: size.width, height: size.height)
            .blur(radius: blur)
    }
}

// MARK: - Fiber stripe (the car-interior LED tracing the pill silhouette)

/// A solid, opaque 2px line inset slightly outside the pill, running down both
/// sides and around the bottom curve only (never across the top). Its bloom is
/// the fiber-soft colour.
struct FiberStripeShape: Shape {
    let bottomRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, rect.height, rect.width / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

struct SplayFiberStripe: View {
    let state: SplayIslandState
    var opacity: Double = 1

    var body: some View {
        let palette = SplayLight.palette(for: state)
        // Trace the pill's EXACT edge (no inset) so the rim light hugs the island
        // with no gap. The 2px stroke straddles the edge; only the soft shadow
        // spreads outward as the glow.
        FiberStripeShape(bottomRadius: SplayGeometry.bottomRadius(for: state))
            // Lighter rim (2026-08-07 feedback): a thinner, lower-alpha line so the
            // coloured border reads as a soft edge rather than a hard neon stroke.
            // The ambient bloom below now carries the colour; the rim just hints it.
            .stroke(palette.fiber.opacity(SplayGlowTuning.rimOpacity), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .shadow(color: palette.fiberSoft, radius: 4.5)
            .shadow(color: palette.fiberSoft, radius: 11)
            .opacity(opacity)
            .allowsHitTesting(false)
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
    /// The irregular `voice` beat (1.5s) — opacity 0.5…1 with a level-meter feel,
    /// not a metronome. Returns (opacityMultiplier, scaleMultiplier) for `t`.
    static func voice(_ time: Double) -> (Double, Double) {
        let period = 1.5
        let f = (time.truncatingRemainder(dividingBy: period)) / period
        // (fraction, opacity, scale) keyframes lifted from the prototype.
        let keys: [(Double, Double, Double)] = [
            (0.00, 0.50, 0.96), (0.11, 0.95, 1.03), (0.23, 0.62, 0.99),
            (0.37, 1.00, 1.06), (0.49, 0.68, 1.00), (0.61, 0.92, 1.03),
            (0.74, 0.58, 0.98), (0.87, 0.86, 1.02), (1.00, 0.50, 0.96)
        ]
        for i in 0..<(keys.count - 1) {
            let (f0, o0, s0) = keys[i]
            let (f1, o1, s1) = keys[i + 1]
            if f >= f0 && f <= f1 {
                let k = (f - f0) / (f1 - f0)
                return (o0 + (o1 - o0) * k, s0 + (s1 - s0) * k)
            }
        }
        return (0.5, 0.96)
    }

    /// Slow `latent` breath as a *multiplier* (0.7…1.0) around each state's base
    /// opacity — so dormant stays faint while still feeling alive. (The prototype
    /// CSS animated absolute opacity; the handoff table gives the base intent, so
    /// we breathe around it rather than overriding it.)
    static func latent(_ time: Double, period: Double) -> Double {
        let f = (time.truncatingRemainder(dividingBy: period)) / period
        return 0.7 + 0.3 * (0.5 - 0.5 * cos(f * 2 * .pi))
    }

    /// Mark breathe: scale 1…1.08, opacity 0.85…1.
    static func breathe(_ time: Double, period: Double) -> (Double, Double) {
        let f = (time.truncatingRemainder(dividingBy: period)) / period
        let e = 0.5 - 0.5 * cos(f * 2 * .pi)
        return (0.85 + 0.15 * e, 1.0 + 0.08 * e)
    }

    /// The light "vector" — a small directional offset that leans the whole island
    /// bloom on a slow organic (Lissajous) path, so the island's *lighting
    /// direction* shifts over time with no visible moving source. Both bloom layers
    /// (and the pill's halo) use this same offset, so they lean as one body.
    /// Replaces the old brightness pulse (`bloomIntensityScale`).
    static func lightVector(_ time: Double) -> CGSize {
        let a = time * SplayGlowTuning.speed * 2
        return CGSize(
            width: SplayGlowTuning.sway * cos(a),
            height: SplayGlowTuning.sway * 0.5 * sin(a * SplayGlowTuning.swirl)
        )
    }
}

// MARK: - Cheap breathing (compositor-driven; no per-frame body rebuild)

/// Animates scale + opacity between two values with a slow repeatForever, driven
/// by CoreAnimation so the wrapped Canvas/blur is not rebuilt every frame. Used
/// for the always-on idle island and idle desktop glow.
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

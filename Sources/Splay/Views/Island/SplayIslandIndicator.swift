import SwiftUI

/// The island as a pure indicator (handoff Screen 1): a flat-black, top-flush
/// pill. It never holds a control beyond one or two glyphs; fn (or the on-screen
/// fn chip) drives capture. All interaction in these states is owned by the
/// AppKit tracker, so this view is display-only.
///
/// No glow (owner, 2026-09-26: "gimmicky"). State colour is carried by the
/// glyphs and the thin fiber stripe; while recording, the left slot is a voice
/// meter and the right slot the elapsed time (`SplayIslandMeter.swift`).
struct SplayIslandIndicator: View {
    let state: SplayIslandState
    /// The live **mic** level (0…1, per-buffer RMS × 10). Shaped + envelope-smoothed
    /// here to drive the recording meter; unused otherwise.
    var level: Double = 0
    /// Elapsed recording time for the right-slot timer.
    var elapsedSeconds: Int = 0
    /// Whether audio frames are actually arriving (1 Hz writer-health signal).
    /// While recording, false renders the "waiting" register: the recording
    /// light holds a motionless warning amber instead of the breathing red —
    /// dead ≠ silent (Talkify's doctrine). Geometry, face, and controls stay
    /// the recording ones (the stop click still works); only the light changes.
    var audioAlive: Bool = true
    /// On a notched built-in display the pill straddles the camera housing, so a
    /// central dead zone is reserved. External displays render a centred row.
    var notchAttached: Bool = true
    /// Which control the cursor is over (from the AppKit tracker) — drives the
    /// hover "pop" (lift + glow) so the buttons answer the touch against the moving pill.
    var hoveredControl: IslandControl = .none
    /// Which control is momentarily pressed (a click pulse from the tracker) —
    /// depresses it like a physical key.
    var pressedControl: IslandControl = .none

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Smooths the live mic level into the recording meter.
    @State private var meter = MeterEnvelope()

    private var isActive: Bool {
        switch state {
        case .recording, .transcribing, .dropped: return true
        default: return false
        }
    }

    /// Recording with no frames arriving — the amber waiting register.
    private var waiting: Bool { state == .recording && !audioAlive }

    /// The state whose *palette* paints the light. Only diverges from `state`
    /// in the waiting register, where the recording geometry keeps the warning
    /// amber (`.warning` and live recording never co-occur).
    private var lightState: SplayIslandState { waiting ? .warning : state }

    var body: some View {
        // ONE stable render path (not an if/else that swaps view identity), so the
        // pill's width / height / bottom-radius / colour *interpolate* between
        // states instead of snapping — that identity swap is what made the morph
        // read as static. The timeline is `paused` when the state isn't animated,
        // so the always-on idle island still costs nothing per frame.
        let animated = isActive && !reduceMotion
        TimelineView(.animation(minimumInterval: nil, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // The meter follows your voice only while frames arrive. The waiting
            // register (dead input) is deliberately *motionless* and flat — a still
            // amber is what makes a dead mic legible against ordinary quiet speech.
            let live = state == .recording && audioAlive
            let drive = live ? SplayMeter.shaped(level) : 0
            // Reduce Motion: bars still track the level, just unsmoothed + no wobble.
            let meterLevel = animated ? meter.advance(to: drive, at: t) : drive
            let m = (animated && !waiting) ? motion(at: t) : Motion(fiberOpacity: staticFiberOpacity, markBreathe: (1, 1))
            pill(fiberOpacity: m.fiberOpacity, markBreathe: m.markBreathe, live: animated,
                 meterLevel: meterLevel, meterPhase: (animated && live) ? t : nil)
                // Ease the red ↔ amber swap (dead-mic waiting register).
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: audioAlive)
        }
    }

    // MARK: Pill

    private func pill(fiberOpacity: Double, markBreathe: (Double, Double), live: Bool,
                      meterLevel: Double, meterPhase: Double?) -> some View {
        let size = SplayGeometry.size(for: state)
        let radius = SplayGeometry.bottomRadius(for: state)
        return ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                   bottomTrailingRadius: radius, topTrailingRadius: 0,
                                   style: .continuous)
                .fill(SplayLight.surface)
                .frame(width: size.width, height: size.height)
                .overlay(SplayFiberStripe(state: lightState, opacity: fiberOpacity))
            face(markBreathe: markBreathe, live: live, meterLevel: meterLevel, meterPhase: meterPhase)
                .frame(width: size.width, height: size.height, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: Face content (left cluster · camera dead zone · right cluster)

    private func face(markBreathe: (Double, Double), live: Bool, meterLevel: Double, meterPhase: Double?) -> some View {
        HStack(spacing: 0) {
            leftCluster(markBreathe: markBreathe, live: live, meterLevel: meterLevel, meterPhase: meterPhase)
                .frame(maxWidth: .infinity, alignment: .leading)
            if notchAttached {
                Spacer(minLength: SplayGeometry.cameraDeadZone.width)
                    .frame(width: SplayGeometry.cameraDeadZone.width)
            } else {
                Spacer(minLength: 8)
            }
            rightCluster
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 26)
        // Horizontal breathing room so the mark clears the rounded corner.
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    /// Elements scale up + fade as they appear, so they feel spawned with the
    /// island (fires under the parent's spring animation on state change). A gentle
    /// 0.8 start (was 0.5) reads as a quick settle rather than a half-size pop.
    /// The `splayBlur` layer (harvested from DynamicNotchKit) blurs each glyph as
    /// it swaps in on every state change, so the face resolves into focus rather
    /// than hard-popping. `intensity` is the one knob to dial if it's too soft/hard.
    private var spawn: AnyTransition {
        .scale(scale: 0.8, anchor: .center)
            .combined(with: .opacity)
            .combined(with: .splayBlur(intensity: 6))
    }

    /// The mark/glyph colour tracks the state's light (recording → coral, done →
    /// green, transcribing → lavender). Live feedback (2026-08-07): the logo used
    /// to stay lavender in every state; it should change colour to match the state.
    private var markColor: Color { SplayLight.palette(for: lightState).fiber }

    @ViewBuilder private func leftCluster(markBreathe: (Double, Double), live: Bool,
                                          meterLevel: Double, meterPhase: Double?) -> some View {
        switch state {
        case .recording:
            // The voice meter sits where the mark was and keeps its job: clicking it
            // opens the card. Red while frames arrive; flat motionless amber when dead.
            hoverPop(SplayIslandMeter(level: meterLevel, phase: meterPhase, color: statusDotColor),
                     control: .menu, scale: 1.12, glow: statusDotColor)
                .transition(spawn)
        case .ready, .transcribing, .dropped:
            // The mark is the menu affordance (revealed on hover): clicking it opens
            // the card (recents / settings / about). Kept off the dormant nub so idle
            // stays a quiet, hidden bar.
            hoverPop(mark(markBreathe: markBreathe, live: live), control: .menu, scale: 1.20, glow: markColor)
                .transition(spawn)
        case .done:
            glyphCircle("checkmark", color: markColor).transition(spawn)
        case .copied:
            glyphCircle("doc.on.doc", color: markColor).transition(spawn)
        case .failed:
            glyphCircle("exclamationmark", color: markColor).transition(spawn)
        case .dormant, .warning:
            EmptyView()
        }
    }

    @ViewBuilder private var rightCluster: some View {
        switch state {
        case .ready:
            // The record dot (revealed on hover) — a small status LED, calm and
            // glow-free at rest. Clicking it (or anywhere off the mark) records.
            hoverPop(statusDot, control: .record).transition(spawn)
        case .recording:
            // Elapsed time (Voice Memos layout). Clicking it stops.
            hoverPop(SplayIslandTimer(seconds: elapsedSeconds, color: statusDotColor),
                     control: .stop, scale: 1.08, glow: statusDotColor)
                .transition(spawn)
        case .transcribing:
            // "wrapping up" — no button. Amber arc (markColor is the transcribing
            // palette's amber) so the spinner reads as semantic "processing".
            SplayIslandSpinner(color: markColor).frame(width: 14, height: 14).transition(spawn)
        case .done:
            // One icon only. At the 280 max width the two-button cluster spilled
            // into the 180px camera dead zone and disappeared behind the housing
            // (2026-08-07 feedback). A single trailing "open" button clears the
            // camera — and clicking the done pill already triggers Open, so this is
            // just its affordance.
            hoverPop(
                actionButton(system: "folder", background: SplayTheme.shared.accent.islandBright, glyph: SplayLight.surface),
                control: .open, scale: 1.16, glow: SplayTheme.shared.accent.islandBright
            )
            .transition(spawn)
        case .warning, .failed:
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .transition(spawn)
        case .dormant, .copied, .dropped:
            EmptyView()
        }
    }

    /// Interactive feedback for a control. On **hover** it lifts, brightens, and
    /// blooms a strong coloured glow — a clear 3D "you can press this" invite. On
    /// **press** (a click pulse from the tracker) it pushes *down* below the hover
    /// pop and the glow squeezes in, like a physical key bottoming out; it then
    /// springs back up. Press wins over hover. Both disabled under Reduce Motion.
    @ViewBuilder private func hoverPop<V: View>(
        _ view: V, control: IslandControl, scale: CGFloat = 1.20,
        glow: Color = SplayLight.recordRed, hueShift: Double = 0
    ) -> some View {
        let hovered = hoveredControl == control && !reduceMotion
        let pressed = pressedControl == control && !reduceMotion
        let active = hovered || pressed
        // Rest → flat. Hover → scale up, brighten, *richen* (saturate — makes the red
        // read as lucious rather than washed), tight glow. Press → sink toward rest
        // (0.95), glow tightens, a touch darker — the key bottoming out.
        let s: CGFloat = pressed ? 0.95 : (hovered ? scale : 1)
        let glowRadius: CGFloat = pressed ? 1 : (hovered ? 3 : 0)
        let glowOpacity: Double = pressed ? 0.6 : (hovered ? 1.0 : 0)
        let lift: CGFloat = pressed ? 0 : (hovered ? 2 : 0)   // sits "above" the surface on hover
        view
            .saturation(active ? 1.30 : 1)                      // richer, more lucious on touch
            .hueRotation(.degrees(active ? hueShift : 0))       // nudge the red's hue (dot only; 0 = off)
            .brightness(pressed ? -0.05 : (hovered ? 0.25 : 0))
            .scaleEffect(s)
            .shadow(color: glow.opacity(glowOpacity), radius: glowRadius, y: lift)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.58), value: hoveredControl)
            // A soft, gentle spring for the press.
            .animation(reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.55), value: pressedControl)
    }

    // MARK: Pieces

    /// The island's record LED (right cluster, ready state). A small, light
    /// coral-red dot; clicking it records. The AppKit tracker owns the click.
    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 8, height: 8)   // small — a status light, not a button
            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    /// A vivid, light coral-red — "the red the button had before." (Dimming it to
    /// 50% over the near-black pill read as a muddy red.) Also the recording meter
    /// and timer colour; in the waiting register (recording, no frames arriving)
    /// they turn warning amber.
    private var statusDotColor: Color {
        waiting ? SplayLight.palette(for: .warning).fiber : SplayLight.recordRed
    }

    @ViewBuilder private func mark(markBreathe: (Double, Double), live: Bool) -> some View {
        // The mark breathes in the state's colour (lavender while ready, etc.).
        let glyph = SplayGlyph(color: markColor)
            .frame(width: 16, height: 16)
        if live {
            glyph.scaleEffect(markBreathe.1).opacity(markBreathe.0)
        } else {
            glyph.modifier(Breathe(period: 3.6, scaleRange: 1...1.08, opacityRange: 0.85...1, animate: !reduceMotion))
        }
    }

    private func glyphCircle(_ system: String, color: Color) -> some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 16, height: 16)
            Image(systemName: system).font(.system(size: 8, weight: .bold)).foregroundStyle(color)
        }
    }

    private func actionButton(system: String, background: Color, glyph: Color) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(background)
            .frame(width: 22, height: 22)
            .overlay(Image(systemName: system).font(.system(size: 11)).foregroundStyle(glyph))
    }

    // MARK: Active motion (per-frame: fiber pulse + mark breathe)

    private struct Motion { let fiberOpacity: Double; let markBreathe: (Double, Double) }

    private func motion(at t: Double) -> Motion {
        switch state {
        case .recording:
            // A steady rim: the meter carries the "I hear you" signal now.
            return Motion(fiberOpacity: 1, markBreathe: (1, 1))
        case .transcribing, .dropped:
            let rimsoft = 0.4 + 0.4 * (0.5 - 0.5 * cos(t.truncatingRemainder(dividingBy: 2.2) / 2.2 * 2 * .pi))
            return Motion(fiberOpacity: rimsoft, markBreathe: SplayMotion.breathe(t, period: 1.1))
        default:
            return Motion(fiberOpacity: 1, markBreathe: (1, 1))
        }
    }

    private var staticFiberOpacity: Double { state == .dormant ? 0.55 : 1 }
}

// MARK: - Transcribing spinner (2px ring, amber top edge = semantic "processing")

private struct SplayIslandSpinner: View {
    /// The rotating arc's colour — the transcribing palette's "processing" amber
    /// (see `SplayLight.palette(for: .transcribing)`), passed in so the spinner
    /// stays a status colour rather than the themed accent.
    var color: Color
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
                .overlay(
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees((t / 0.8).truncatingRemainder(dividingBy: 1) * 360))
                )
        }
    }
}

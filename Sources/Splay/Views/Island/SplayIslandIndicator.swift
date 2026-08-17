import SwiftUI

/// The island as a pure indicator (handoff Screen 1): a flat-black, top-flush
/// pill. It never holds a control beyond one or two glyphs; fn (or the on-screen
/// fn chip) drives capture. All interaction in these states is owned by the
/// AppKit tracker, so this view is display-only.
///
/// The big ambient bloom now lives on a separate desktop-level panel
/// (`SplayGlowView`), so the light sprays onto the wallpaper instead of hovering
/// over your work. The pill keeps only a small local glow + the fiber stripe so
/// it still reads as alive on top, even when the desktop bloom is behind a window.
struct SplayIslandIndicator: View {
    let state: SplayIslandState
    /// The live mic level (0…1, max of mic/system). Envelope-smoothed here to drive
    /// the talk-reactive recording glow (sweep + rim brightness); unused otherwise.
    var level: Double = 0
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
    /// Smooths the live mic level into the talk-reactive recording glow.
    @State private var env = TalkEnvelope()

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
            // Talk-reactive recording level: the smoothed mic envelope × the master
            // intensity. Only recording reacts; 0 elsewhere and when the Settings
            // slider is at 0 (which reverts to the original calm sway).
            let intensity = SplayGlowSettings.shared.talkIntensity
            let reactive = animated && state == .recording && intensity > 0 && audioAlive
            let talk = reactive ? env.advance(to: min(1, max(0, level)), at: t) * intensity : 0
            // The waiting register is deliberately *motionless* — a still amber
            // is what makes a dead mic legible against ordinary quiet speech.
            let m = (animated && !waiting) ? motion(at: t, talk: talk) : Motion(fiberOpacity: staticFiberOpacity, markBreathe: (1, 1))
            let sway = waiting ? .zero
                : (reactive ? SplayMotion.talkVector(t, level: talk)
                            : (animated ? SplayMotion.lightVector(t) : .zero))
            pill(fiberOpacity: m.fiberOpacity, markBreathe: m.markBreathe, live: animated, sway: sway, talk: talk)
                // Ease the red ↔ amber light swap (dead-mic waiting register)
                // instead of snapping it mid-frame.
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: audioAlive)
        }
    }

    // MARK: Pill

    private func pill(fiberOpacity: Double, markBreathe: (Double, Double), live: Bool, sway: CGSize, talk: Double = 0) -> some View {
        let size = SplayGeometry.size(for: state)
        let radius = SplayGeometry.bottomRadius(for: state)
        // Talk reaction: the pill's own halo brightens + grows a touch as you speak,
        // so the "I'm talking" light reads even when the desktop wash is occluded.
        let haloOpacity = min(1, SplayGlowTuning.haloOpacity * (1 + SplayTalkGlowTuning.brightGain * talk))
        let haloRadius = SplayGlowTuning.haloRadius * CGFloat(1 + SplayTalkGlowTuning.brightGain * talk * 0.3)
        return ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                   bottomTrailingRadius: radius, topTrailingRadius: 0,
                                   style: .continuous)
                .fill(SplayLight.surface)
                .frame(width: size.width, height: size.height)
                // The pill's own soft halo carries the island's visible light (the
                // desktop bloom is faint + often behind a window). It *leans* with
                // the light vector — the halo shifts toward the current lighting
                // direction — and (while recording) brightens with your voice.
                .shadow(color: SplayLight.palette(for: lightState).bloomHue.opacity(haloOpacity),
                        radius: haloRadius,
                        x: sway.width * 0.16, y: 7 + sway.height * 0.12)
                .overlay(SplayFiberStripe(state: lightState, opacity: fiberOpacity))
            face(markBreathe: markBreathe, live: live)
                .frame(width: size.width, height: size.height, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: Face content (left cluster · camera dead zone · right cluster)

    private func face(markBreathe: (Double, Double), live: Bool) -> some View {
        HStack(spacing: 0) {
            leftCluster(markBreathe: markBreathe, live: live)
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

    @ViewBuilder private func leftCluster(markBreathe: (Double, Double), live: Bool) -> some View {
        switch state {
        case .ready, .recording, .transcribing, .dropped:
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
            // The same dot, now lit red + glowing = "recording". Clicking it stops.
            hoverPop(statusDot, control: .stop, scale: 1.2).transition(spawn)
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

    /// The island's persistent record LED (right cluster). A small, light coral-red
    /// dot — the *colour* is constant (see `statusDotColor`); only the glow and rim
    /// brighten while recording. So rest = a calm light-red dot (no glow), recording
    /// = the same dot lit. Clicking it records (idle) or stops (recording); the
    /// AppKit tracker owns the click. Replaces the old hover-gated dot / stop square.
    private var statusDot: some View {
        let recording = state == .recording
        return Circle()
            .fill(statusDotColor)
            .frame(width: 8, height: 8)   // small — a status light, not a button
            .overlay(Circle().strokeBorder(.white.opacity(recording ? 0.3 : 0.12), lineWidth: 0.5))
            // Glow ONLY while recording (design brief): the resting bar stays quiet.
            .shadow(color: recording ? statusDotColor.opacity(0.85) : .clear,
                    radius: recording ? 5 : 0)
    }

    /// A vivid, light coral-red at all times — "the red the button had before."
    /// (Dimming this to 50% opacity over the near-black pill produced a dark, muddy
    /// red, which read as an odd colour.) Recording doesn't darken or lighten the
    /// hue — it just adds the glow below, so rest = light red, recording = the same
    /// light red, lit. In the waiting register (recording, no frames arriving)
    /// the LED joins the rest of the light on warning amber.
    private var statusDotColor: Color {
        waiting ? SplayLight.palette(for: .warning).fiber : SplayLight.recordRed
    }

    @ViewBuilder private func mark(markBreathe: (Double, Double), live: Bool) -> some View {
        // Give the mark its own soft, breathing glow in the state's colour, so the
        // logo reads coral while recording, lavender while ready, etc.
        let glyph = SplayGlyph(color: markColor)
            .frame(width: 16, height: 16)
            .shadow(color: markColor.opacity(0.55), radius: 5)
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

    private func motion(at t: Double, talk: Double = 0) -> Motion {
        switch state {
        case .recording:
            // Rim brightness = your actual voice (talk > 0): the pill's edge lights
            // up as you speak — the clearest "I'm talking" cue on the pill itself.
            // With the talk glow off (talk == 0), fall back to the decorative beat.
            let rim: Double
            if talk > 0 {
                rim = 0.45 + 0.55 * min(1, talk)
            } else {
                let (voiceOp, _) = SplayMotion.voice(t)
                rim = 0.45 + 0.55 * ((voiceOp - 0.5) / 0.5)
            }
            return Motion(fiberOpacity: rim, markBreathe: SplayMotion.breathe(t, period: 1.9))
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

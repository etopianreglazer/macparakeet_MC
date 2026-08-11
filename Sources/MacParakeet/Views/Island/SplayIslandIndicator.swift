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
    /// Retained for call-site symmetry; the live level now drives the glow panel.
    var level: Double = 0
    /// On a notched built-in display the pill straddles the camera housing, so a
    /// central dead zone is reserved. External displays render a centred row.
    var notchAttached: Bool = true
    /// Which control the cursor is over (from the AppKit tracker) — drives the
    /// subtle hover "pop" so the buttons answer the touch against the moving pill.
    var hoveredControl: IslandControl = .none

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool {
        switch state {
        case .recording, .transcribing, .dropped: return true
        default: return false
        }
    }

    var body: some View {
        // ONE stable render path (not an if/else that swaps view identity), so the
        // pill's width / height / bottom-radius / colour *interpolate* between
        // states instead of snapping — that identity swap is what made the morph
        // read as static. The timeline is `paused` when the state isn't animated,
        // so the always-on idle island still costs nothing per frame.
        let animated = isActive && !reduceMotion
        TimelineView(.animation(minimumInterval: nil, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let m = animated ? motion(at: t) : Motion(fiberOpacity: staticFiberOpacity, markBreathe: (1, 1))
            let sway = animated ? SplayMotion.lightVector(t) : .zero
            pill(fiberOpacity: m.fiberOpacity, markBreathe: m.markBreathe, live: animated, sway: sway)
        }
    }

    // MARK: Pill

    private func pill(fiberOpacity: Double, markBreathe: (Double, Double), live: Bool, sway: CGSize) -> some View {
        let size = SplayGeometry.size(for: state)
        let radius = SplayGeometry.bottomRadius(for: state)
        return ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                   bottomTrailingRadius: radius, topTrailingRadius: 0,
                                   style: .continuous)
                .fill(SplayLight.surface)
                .frame(width: size.width, height: size.height)
                // The pill's own soft halo carries the island's visible light (the
                // desktop bloom is faint + often behind a window). It *leans* with
                // the light vector — the halo shifts toward the current lighting
                // direction, so the island's edge lighting travels without any
                // visible moving source.
                .shadow(color: SplayLight.palette(for: state).bloomHue.opacity(SplayGlowTuning.haloOpacity),
                        radius: SplayGlowTuning.haloRadius,
                        x: sway.width * 0.16, y: 7 + sway.height * 0.12)
                .overlay(SplayFiberStripe(state: state, opacity: fiberOpacity))
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
        // More horizontal breathing room so the mark clears the rounded corner
        // and sits balanced against the fn chip (was 6 — felt jammed into the edge).
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
    private var markColor: Color { SplayLight.palette(for: state).fiber }

    @ViewBuilder private func leftCluster(markBreathe: (Double, Double), live: Bool) -> some View {
        switch state {
        case .ready, .recording, .transcribing, .dropped:
            mark(markBreathe: markBreathe, live: live).transition(spawn)
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
            hoverPop(recordButton, control: .record).transition(spawn)   // click → start; the tracker owns the click
        case .recording:
            hoverPop(stopButton, control: .stop, scale: 1.2).transition(spawn)  // click → stop
        case .transcribing:
            SplayIslandSpinner().frame(width: 14, height: 14).transition(spawn)  // "wrapping up" — no button
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

    /// The hover "pop": lift a control and bloom a soft halo when the tracker
    /// reports the cursor is over it, so it clearly answers the touch against the
    /// moving island. The halo matters because the cursor is often stationary over
    /// the control (scale alone was too quiet to read). Smoothed spring; disabled
    /// under Reduce Motion.
    @ViewBuilder private func hoverPop<V: View>(
        _ view: V, control: IslandControl, scale: CGFloat = 1.22, glow: Color = SplayLight.recordRed
    ) -> some View {
        let on = hoveredControl == control && !reduceMotion
        view
            .scaleEffect(on ? scale : 1)
            .shadow(color: glow.opacity(on ? 0.8 : 0), radius: on ? 6 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.58), value: hoveredControl)
    }

    // MARK: Pieces

    /// The island's one deliberately clickable thing: a simple record dot
    /// (Voice-Memos-style) — a red circle with a thin rim and a soft red glow.
    /// Clicking it records; the AppKit tracker owns the click.
    private var recordButton: some View {
        Circle()
            .fill(SplayLight.recordRed)
            .frame(width: 13, height: 13)   // sized to match the mark's visual weight
            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
            .shadow(color: SplayLight.recordRed.opacity(0.6), radius: 4)
    }

    /// Recording's clickable affordance: a red rounded square (Voice-Memos stop),
    /// matched to the record dot's weight + glow so the two states read as one
    /// control changing meaning — circle = start, square = stop. Previously the
    /// recording pill had only an invisible right-edge hit zone, which made the
    /// record dot feel like a gimmick that vanished the moment you used it.
    private var stopButton: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(SplayLight.recordRed)
            .frame(width: 12, height: 12)
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
            .shadow(color: SplayLight.recordRed.opacity(0.6), radius: 4)
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

    private func motion(at t: Double) -> Motion {
        switch state {
        case .recording:
            let (voiceOp, _) = SplayMotion.voice(t)
            let rim = 0.45 + 0.55 * ((voiceOp - 0.5) / 0.5)   // rimlive on the voice beat
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

// MARK: - Transcribing spinner (2px ring, accent top edge, per handoff)

private struct SplayIslandSpinner: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
                .overlay(
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(SplayTheme.shared.accent.islandBright, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees((t / 0.8).truncatingRemainder(dividingBy: 1) * 360))
                )
        }
    }
}

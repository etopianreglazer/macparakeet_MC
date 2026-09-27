import SwiftUI

/// The island as a pure indicator: a flat-black, top-flush pill, display-only
/// (fn drives capture; the island takes no mouse input).
///
/// No glow, no rim. The voice meter (plus a meeting's system-audio meter) sits
/// left of the camera, the timer right of it; dictation is the voice meter alone
/// with only a short ear past the camera (`SplayGeometry.layout`,
/// `SplayIslandMeter.swift`).
struct SplayIslandIndicator: View {
    let state: SplayIslandState
    /// Which capture the active pill shows: recording (meter + timer), meeting
    /// (twin meter + timer) or dictation (meter alone).
    var captureKind: IslandCaptureKind = .recording
    /// The live **mic** level (0…1, per-buffer RMS × 10). Shaped + envelope-smoothed
    /// here to drive the recording meter; unused otherwise.
    var level: Double = 0
    /// The live **system audio** level (0…1) — a meeting's second, fainter meter.
    var systemLevel: Double = 0
    /// Elapsed recording time for the timer (recordings and meetings).
    var elapsedSeconds: Int = 0
    /// Whether audio frames are actually arriving (1 Hz writer-health signal).
    /// While recording, false renders the "waiting" register: the recording
    /// light holds a motionless warning amber instead of the breathing red —
    /// dead ≠ silent (Talkify's doctrine). Geometry and face stay the
    /// recording ones; only the light changes.
    var audioAlive: Bool = true
    /// On a notched built-in display the pill straddles the camera housing, each
    /// side hugging its own content (it never runs under the camera). External
    /// displays hug the content, centred.
    var notchAttached: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Smooths the live mic level into the recording meter.
    @State private var meter = MeterEnvelope()
    /// Smooths the live system-audio level into a meeting's second meter.
    @State private var systemMeter = MeterEnvelope()

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
            let systemDrive = (live && captureKind == .meeting) ? SplayMeter.shaped(systemLevel) : 0
            let systemMeterLevel = animated ? systemMeter.advance(to: systemDrive, at: t) : systemDrive
            let markBreathe = (animated && !waiting) ? breathe(at: t) : (1, 1)
            pill(markBreathe: markBreathe, live: animated,
                 meterLevel: meterLevel, systemMeterLevel: systemMeterLevel,
                 meterPhase: (animated && live) ? t : nil)
                // Ease the red ↔ amber swap (dead-mic waiting register).
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: audioAlive)
        }
    }

    // MARK: Pill

    private func pill(markBreathe: (Double, Double), live: Bool,
                      meterLevel: Double, systemMeterLevel: Double, meterPhase: Double?) -> some View {
        let layout = SplayGeometry.layout(for: state, kind: captureKind, notchAttached: notchAttached)
        let size = layout.size
        let radius = SplayGeometry.bottomRadius(for: state)
        return ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: radius,
                                   bottomTrailingRadius: radius, topTrailingRadius: 0,
                                   style: .continuous)
                .fill(SplayLight.surface)
                .frame(width: size.width, height: size.height)
            face(markBreathe: markBreathe, live: live, meterLevel: meterLevel,
                 systemMeterLevel: systemMeterLevel, meterPhase: meterPhase)
                .frame(width: size.width, height: size.height, alignment: .bottom)
        }
        // Each side hugs its own content, so the pill sits a few points off the
        // camera's centre; dictation (bars + short ear) hangs visibly left.
        .offset(x: layout.centerOffset)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: Face content (bars left of the camera · timer right of it)

    private func face(markBreathe: (Double, Double), live: Bool, meterLevel: Double,
                      systemMeterLevel: Double, meterPhase: Double?) -> some View {
        let height = SplayGeometry.layout(for: state, kind: captureKind, notchAttached: notchAttached).size.height
        return HStack(spacing: 0) {
            leftCluster(markBreathe: markBreathe, live: live, meterLevel: meterLevel,
                        systemMeterLevel: systemMeterLevel, meterPhase: meterPhase)
            Spacer(minLength: 0)
            rightCluster
        }
        .frame(height: 26)
        .padding(.horizontal, SplayGeometry.contentInset)
        .padding(.bottom, max(0, (height - 26) / 2))
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
                                          meterLevel: Double, systemMeterLevel: Double,
                                          meterPhase: Double?) -> some View {
        switch state {
        case .recording:
            // Your mic in every capture: red while frames arrive, flat motionless
            // amber when dead. A meeting adds the fainter system-audio bars
            // ("more voices"). The timer is the right cluster.
            HStack(spacing: SplayMeterTuning.twinGap) {
                SplayIslandMeter(level: meterLevel, phase: meterPhase, color: statusDotColor)
                if captureKind == .meeting {
                    SplayIslandMeter(level: systemMeterLevel, phase: meterPhase.map { $0 + 0.7 },
                                     color: SplayLight.systemAudio, bars: SplayMeterTuning.systemBarCount)
                }
            }
            .transition(spawn)
        case .transcribing:
            // Amber arc (the transcribing palette) = semantic "processing".
            SplayIslandSpinner(color: markColor).frame(width: 14, height: 14).transition(spawn)
        case .dropped:
            // A dropped file (menu bar icon drop) still shows the brand mark.
            mark(markBreathe: markBreathe, live: live).transition(spawn)
        case .done:
            glyphCircle("checkmark", color: markColor).transition(spawn)
        case .copied:
            glyphCircle("doc.on.doc", color: markColor).transition(spawn)
        case .failed, .warning:
            glyphCircle("exclamationmark", color: markColor).transition(spawn)
        case .dormant, .ready:
            // The resting nub shows nothing (no mark, owner 2026-09-26).
            EmptyView()
        }
    }

    /// Right of the camera: the elapsed time while a recording or meeting runs.
    /// Dictation shows nothing here (owner, 2026-09-27) — the pill just ends.
    @ViewBuilder private var rightCluster: some View {
        if state == .recording, captureKind != .dictation {
            SplayIslandTimer(seconds: elapsedSeconds, color: statusDotColor)
                .frame(width: SplayGeometry.timerWidth, alignment: .trailing)
                .transition(spawn)
        }
    }

    // MARK: Pieces

    /// The recording red — a vivid, light coral-red. (Dimming it to
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

    // MARK: Active motion (per-frame mark breathe)

    /// The mark breathes while a dropped file is working; everything else is still.
    /// No rim (owner, 2026-09-27: the red halo is gone) — the glyphs carry state.
    private func breathe(at t: Double) -> (Double, Double) {
        switch state {
        case .transcribing, .dropped: return SplayMotion.breathe(t, period: 1.1)
        default: return (1, 1)
        }
    }
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

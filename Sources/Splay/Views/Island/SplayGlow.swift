import SwiftUI
import SplayViewModels

extension SplayIslandState {
    /// Shared mapping from the recording lifecycle + idle chrome to an indicator
    /// form, so the pill (on top) and the desktop glow (below windows) always
    /// show the same state. Returns nil when nothing should be shown (hidden).
    static func resolve(pillState: MeetingRecordingPillViewModel.PillState,
                        hovered: Bool, idleVisible: Bool, heldOpen: Bool = false) -> SplayIslandState? {
        switch pillState {
        case .idle:                     return idleVisible ? ((hovered || heldOpen) ? .ready : .dormant) : nil
        case .recording, .paused:       return .recording
        case .completing, .transcribing: return .transcribing
        case .completed:                return .done
        case .error:                    return .failed
        }
    }
}

/// The ambient bloom, rendered on its OWN panel that sits *below* app windows
/// (see `IslandController`'s glow panel). This makes the light spray onto the
/// wallpaper rather than hover as a distracting foreground over your work: at the
/// desktop it's fully visible; with a window open, the glow is behind it. The
/// pill/indicator stays on top and carries state; only this big glow drops back.
struct SplayGlowView: View {
    @Bindable var pill: MeetingRecordingPillViewModel
    @Bindable var chrome: IslandChromeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Smooths the live mic level into the talk-reactive wash (recording only).
    @State private var env = TalkEnvelope()

    private var state: SplayIslandState? {
        let resolved = SplayIslandState.resolve(pillState: pill.state, hovered: chrome.isHovered,
                                                idleVisible: chrome.idleVisible, heldOpen: chrome.heldOpen)
        // Waiting register (dead ≠ silent): recording with no frames arriving
        // shows the *warning* light — a motionless amber bloom (the static
        // branch below) in place of the voice-reactive red wash. Same max
        // geometry, so only the colour and the motion change. Self-healing:
        // the moment frames flow the resolve returns to `.recording`.
        if resolved == .recording, !chrome.audioAlive { return .warning }
        return resolved
    }

    var body: some View {
        ZStack {
            if let state {
                // `.id` + opacity transition cross-fades the light between states
                // (gradients don't interpolate their colours), so it dissolves
                // rather than snaps — and fades in/out when it appears/vanishes.
                bloom(state)
                    .id(state)
                    // Burst in (scale + fade) so the light spawns with the island
                    // and cross-fades colour between states rather than snapping.
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Anchor the bloom to the pill's top edge, mirroring the indicator's
        // placement so the glow lines up with the pill above it.
        .padding(.top, chrome.isNotchResting ? 0 : IslandLayout.topInset)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: state)
    }

    @ViewBuilder private func bloom(_ state: SplayIslandState) -> some View {
        let width = SplayGeometry.size(for: state).width
        let isActive = state == .recording || state == .transcribing || state == .dropped
        if isActive && !reduceMotion {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                if state == .recording {
                    // Voice-reactive "moving-head wash": a smoothed mic envelope,
                    // scaled by the master intensity, widens/speeds the sweep and
                    // brightens the wash. Intensity 0 = the original calm sway.
                    let intensity = SplayGlowSettings.shared.talkIntensity
                    // Fast (~30 fps) level via the island's isolated channel, not the
                    // 1 s pill-poll — this is what lets the wash track your voice.
                    let raw = chrome.liveLevel
                    let level = env.advance(to: raw, at: t) * intensity
                    let reactive = intensity > 0
                    SplayAmbientBloom(
                        state: state, pillWidth: width,
                        sway: reactive ? SplayMotion.talkVector(t, level: level) : SplayMotion.lightVector(t),
                        talk: reactive ? level : 0
                    )
                } else {
                    SplayAmbientBloom(state: state, pillWidth: width, sway: SplayMotion.lightVector(t))
                }
            }
        } else {
            // The waiting register (`.warning` while recording) is deliberately
            // *motionless* — no breathe — so a dead mic reads as "stuck", clearly
            // distinct from every alive state's gentle life.
            SplayAmbientBloom(state: state, pillWidth: width)
                .modifier(Breathe(period: 7, scaleRange: 1...1, opacityRange: 0.7...1,
                                  animate: !reduceMotion && state != .warning))
        }
    }
}

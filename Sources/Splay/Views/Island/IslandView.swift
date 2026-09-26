import AppKit
import SwiftUI
import SplayCore
import SplayViewModels

// MARK: - Visual states

/// The discrete visual forms the ambient island morphs through. Distinct from
/// `MeetingRecordingPillViewModel.PillState` because several recording-flow
/// states collapse onto one island form (e.g. `.paused` reuses the recording
/// form; `.completing` reuses transcribing), and idle splits into collapsed vs.
/// hover. The AppKit tracker and the SwiftUI view derive sizes from the same
/// `IslandLayout`, so their hit-rects never drift from what's drawn.
///
/// The island is an **indicator only** (two-surface design): it never expands
/// into a control surface. Everything else is a card (`SplayCardController`).
enum IslandVisual: Equatable {
    case hidden
    case idleCollapsed
    case idleHover
    case recording
    case transcribing
    case done
}

/// The island's interactive controls — the few clickable affordances the pill
/// exposes per visual state. Used both to route clicks and to drive per-control
/// hover feedback (the "pop" that tells you a control is touchable). The island
/// is in constant motion; its controls shouldn't feel dead, so the tracker feeds
/// the hovered control into the SwiftUI indicator, which lifts it slightly.
enum IslandControl: Equatable {
    case none
    case menu     // the mark (left) → open the card (recents / settings / about)
    case record   // idle → start a recording
    case stop     // recording → stop
    case open     // done → open the menu card
}

// MARK: - Shared layout (single source of truth for view + tracker)

enum IslandLayout {
    /// The panel is a fixed, generous stage; the pill morphs *within* it,
    /// horizontally centered and anchored just below the menu bar. Nothing
    /// resizes the panel, so the morph stays smooth and its hit geometry never
    /// changes with the lifecycle state.
    // A fixed stage (sized when the island still had a glow around it). The pill
    // stays centred; the extra area is transparent and click-through.
    static let panelWidth: CGFloat = 840
    static let panelHeight: CGFloat = 460

    // The panel stage itself starts at the menu-bar safe edge. On the internal
    // notched display an 8pt inset places the idle nub *inside* the physical
    // camera cut-out, which makes it look like the notch and steals its click
    // target. Keep the island visually attached, but begin just beneath the
    // cut-out so the resting pill is both visible and usable.
    static let topInset: CGFloat = 32

    // Sizes mirror the design handoff's per-state geometry so the AppKit tracker's
    // hit-rects never drift from the drawn pill (`SplayGeometry.size` is the twin
    // used by the SwiftUI indicator).
    static func pillSize(for visual: IslandVisual) -> CGSize {
        switch visual {
        case .hidden:        return .zero
        case .idleCollapsed: return SplayGeometry.size(for: .dormant)
        case .idleHover:     return SplayGeometry.size(for: .ready)
        case .recording:     return SplayGeometry.size(for: .recording)
        case .transcribing:  return SplayGeometry.size(for: .transcribing)
        case .done:          return SplayGeometry.size(for: .done)
        }
    }

    /// Width of a right-cluster control's hit region (the status dot / open
    /// button). Kept tight — close to the drawn glyph — so hover/click detection
    /// hugs the small dot instead of arming across the whole right of the pill.
    static let controlHitWidth: CGFloat = 16
    /// Hit width over the recording timer (`m:ss` at 12pt ≈ 28pt, up to 99 min).
    static let recordingTimerHitWidth: CGFloat = 34

    /// Interaction rect for the AppKit tracker — simply the drawn pill (notch-mode
    /// hover is additionally served by `notchRevealRect`).
    static func hitRect(for visual: IslandVisual, notchAttached: Bool = false) -> CGRect {
        pillRect(for: visual, notchAttached: notchAttached)
    }

    /// Hover-only central approach zone. In Notch mode it deliberately meets
    /// the physical top edge alongside the narrow visible companion; clicks
    /// remain restricted to `hitRect` so transparent panel pixels pass through.
    static func notchRevealRect() -> CGRect {
        CGRect(x: (panelWidth - 240) / 2, y: panelHeight - 56, width: 240, height: 56)
    }

    /// Hover *hysteresis*: once revealed, the ready pill stays active while the
    /// cursor is anywhere on it (plus a forgiving margin below), so moving from
    /// the notch onto the tile no longer collapses it back to idle.
    static func hoverStayRect(notchAttached: Bool = false) -> CGRect {
        let ready = pillRect(for: .idleHover, notchAttached: notchAttached)
        let w = max(ready.width + 24, 272)
        let extraBelow: CGFloat = 28
        return CGRect(x: (panelWidth - w) / 2, y: ready.minY - extraBelow, width: w, height: ready.height + extraBelow)
    }

    /// The right-cluster control hit region for a given visual — where the status
    /// dot / open button is drawn (`SplayIslandIndicator.rightCluster`, trailing-
    /// aligned with 14pt face padding, in both notch and non-notch layouts). The
    /// rect is a bit wider than the glyph so it's an easy target. The drawn glyph
    /// and this rect derive from the same `pillRect`, so they never drift.
    static func controlRect(for visual: IslandVisual, notchAttached: Bool = false) -> CGRect {
        let pill = pillRect(for: visual, notchAttached: notchAttached)
        if visual == .recording {
            // The recording stop control is the elapsed timer, right-aligned at the
            // 14pt face padding — cover its width, not just a dot.
            return CGRect(x: pill.maxX - 14 - recordingTimerHitWidth, y: pill.minY,
                          width: recordingTimerHitWidth + 8, height: pill.height)
        }
        let w = controlHitWidth
        // Centre the tight target on the trailing glyph (drawn ~14pt in from the
        // pill's right edge), not flush to the edge, so it sits right over the dot.
        let center = pill.maxX - 18
        return CGRect(x: center - w / 2, y: pill.minY, width: w, height: pill.height)
    }

    /// A compact hit target over the leading-aligned mark (drawn at ~x 14…30: a
    /// 14pt leading pad + a 16pt glyph, identical in notch and non-notch layouts).
    /// Deliberately narrow — a click on the empty middle of the bar must still
    /// record / stop, not open the card — and clamped so it can never reach the
    /// right-cluster control rect.
    static let markHitWidth: CGFloat = 44
    static func markRect(for visual: IslandVisual, notchAttached: Bool = false) -> CGRect {
        let pill = pillRect(for: visual, notchAttached: notchAttached)
        let w = min(markHitWidth, pill.width - controlHitWidth - 8)
        return CGRect(x: pill.minX, y: pill.minY, width: max(0, w), height: pill.height)
    }

    /// Grace window after hover drops during which an idle click is still
    /// treated as aimed at the *revealed* pill (the hover race: `mouseDown`
    /// outrunning the tracker's hover flip, or the shallow stay-margin dropping
    /// hover between aim and click).
    static let hoverRaceGrace: TimeInterval = 0.7

    /// The visual a *click* should be resolved against. During the hover race
    /// the model reads dormant while the user clicks the *revealed* pill they
    /// saw drawn — which would swallow the mark region (it pokes outside the
    /// narrower nub's hit rect) or misroute it to record. So while hover is (or
    /// was just, within `hoverRaceGrace`) active, idle clicks inside the
    /// revealed geometry resolve against the revealed visual. A cold dormant
    /// click (`recentlyRevealed == false`) is never rerouted — the resting
    /// nub's click-anywhere-records behavior stays intact.
    static func clickVisual(
        for visual: IslandVisual, at point: CGPoint,
        notchAttached: Bool, recentlyRevealed: Bool
    ) -> IslandVisual {
        guard visual == .idleCollapsed, recentlyRevealed,
              hitRect(for: .idleHover, notchAttached: notchAttached).contains(point)
        else { return visual }
        return .idleHover
    }

    /// Which interactive control (if any) sits under `point` for the current
    /// visual. Shared by the click router and the hover-feedback path so the two
    /// never disagree about where a control is. The right-cluster control (record /
    /// stop / open) wins its rect; the mark (menu) owns the left region.
    static func control(at point: CGPoint, visual: IslandVisual, notchAttached: Bool) -> IslandControl {
        switch visual {
        case .idleHover:
            if controlRect(for: .idleHover, notchAttached: notchAttached).contains(point) { return .record }
            if markRect(for: .idleHover, notchAttached: notchAttached).contains(point) { return .menu }
            return .none
        case .idleCollapsed:
            // The dormant nub draws no mark or dot — any click just records.
            // (A click during the hover race never reaches this case: the
            // router re-resolves it to `.idleHover` via `clickVisual` first.)
            return .none
        case .recording:
            if controlRect(for: .recording, notchAttached: notchAttached).contains(point) { return .stop }
            if markRect(for: .recording, notchAttached: notchAttached).contains(point) { return .menu }
            return .none
        case .transcribing:
            return markRect(for: .transcribing, notchAttached: notchAttached).contains(point) ? .menu : .none
        case .done:
            return controlRect(for: .done, notchAttached: notchAttached).contains(point) ? .open : .none
        default:
            return .none
        }
    }

    /// Map recording-flow state (+ idle chrome) onto a visual form. `heldOpen`
    /// keeps the idle island in its ready ("open") form while a card is showing.
    static func visual(
        for state: MeetingRecordingPillViewModel.PillState,
        hovered: Bool,
        idleVisible: Bool,
        heldOpen: Bool = false
    ) -> IslandVisual {
        switch state {
        case .idle:
            guard idleVisible else { return .hidden }
            return (hovered || heldOpen) ? .idleHover : .idleCollapsed
        case .recording, .paused:
            return .recording
        case .completing, .transcribing:
            return .transcribing
        case .completed, .error:
            return .done
        }
    }

    /// The pill's frame in panel (AppKit, bottom-left origin) coordinates.
    /// The view is top-anchored, while AppKit coordinates grow upward, so the
    /// shared tracker uses the corresponding top-derived y value.
    static func pillRect(for visual: IslandVisual, notchAttached: Bool = false) -> CGRect {
        let size = pillSize(for: visual)
        let topBreathingRoom = notchAttached ? 0 : topInset
        return CGRect(
            x: (panelWidth - size.width) / 2,
            y: panelHeight - topBreathingRoom - size.height,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Local chrome model (idle hover + visibility)

/// Lightweight, app-target-local state for the island's idle chrome. The
/// recording lifecycle lives on the shared `MeetingRecordingPillViewModel`;
/// this only carries hover + the user's "show idle pill" preference.
@MainActor @Observable
final class IslandChromeModel {
    var isHovered = false
    var idleVisible = true
    var isNotchResting = false
    /// A card (the second surface) is open — hold the idle island in its ready
    /// ("open") form until the card closes, so the two surfaces move together.
    var heldOpen = false
    /// Which control the cursor is currently over (mark / status dot / open), fed
    /// by the AppKit tracker so the SwiftUI indicator can pop it on hover. The
    /// island is display-only, so hover can't come from SwiftUI itself.
    var hoveredControl: IslandControl = .none
    /// Which control is momentarily *pressed* (a short pulse fired on click), so the
    /// indicator can depress it like a physical key. Cleared automatically after the
    /// pulse. Also fed by the tracker, since the click lives at the AppKit layer.
    var pressedControl: IslandControl = .none
    /// Distance from the panel's physically hidden top to the housing's lower edge.
    var notchCueInset: CGFloat = 0
    /// Live **mic** level (0…1), pushed at ~30 fps while recording via
    /// `IslandController.updateLiveAudioLevel` — the island's own isolated channel
    /// so the recording meter tracks your voice in real time, without 30 fps
    /// writes to the shared pill VM. Only the island observes this model.
    var liveLevel: Double = 0
    /// Whether audio frames are actually being written while recording (pushed
    /// at 1 Hz from the coordinator's writer-health poll). False turns the
    /// recording meter + timer into a motionless warning amber — dead ≠ silent: a mic
    /// that delivers nothing is *shown*, the recording is never failed for it.
    /// Self-healing: flips back the moment frames flow.
    var audioAlive = true
    init() {}
}

// MARK: - Island view

/// The ambient island hanging from the notch. Pure **indicator**: it renders the
/// lifecycle indicator (fiber stripe + glyphs, meter + timer while recording) and nothing else — no controls,
/// no expansion. All interaction is routed through `IslandController`'s AppKit
/// tracking layer (hover/click on a non-activating panel can't go through
/// SwiftUI), and anything the app needs to *say* is a card.
struct IslandView: View {
    @Bindable var pill: MeetingRecordingPillViewModel
    @Bindable var chrome: IslandChromeModel

    private var visual: IslandVisual {
        IslandLayout.visual(
            for: pill.state,
            hovered: chrome.isHovered,
            idleVisible: chrome.idleVisible,
            heldOpen: chrome.heldOpen
        )
    }

    private var motion: Animation? {
        // A spring (not a slow fade) so the island *pops* and its elements feel
        // spawned with it. A touch more response than the old 0.26 so the
        // width/colour morph between states reads as a smooth glide, not a snap
        // (paired with the indicator's now-stable single render path).
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if let splayState = mappedState {
                SplayIslandIndicator(
                    state: splayState,
                    level: chrome.liveLevel,
                    elapsedSeconds: pill.elapsedSeconds,
                    audioAlive: chrome.audioAlive,
                    notchAttached: chrome.isNotchResting,
                    hoveredControl: chrome.hoveredControl,
                    pressedControl: chrome.pressedControl
                )
                // Mirror the tracker's `pillRect` top offset exactly so the drawn
                // pill and its hit-rect stay aligned: flush to the physical top in
                // Notch mode, the menu-safe inset otherwise.
                .padding(.top, chrome.isNotchResting ? 0 : IslandLayout.topInset)
                // Pop the whole island in from slightly small, anchored at the
                // notch, so it reads as spawning rather than fading. The blur layer
                // (harvested from DynamicNotchKit) softens the show/hide so the pill
                // resolves into focus instead of hard-cutting.
                .transition(.scale(scale: 0.85, anchor: .top)
                    .combined(with: .opacity)
                    .combined(with: .splayBlur(intensity: 8)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(motion, value: visual)
        // Display-only: the AppKit tracker owns all hover/click.
        .allowsHitTesting(false)
    }

    /// Map the tracker's `IslandVisual` (+ recording-flow state) onto the design's
    /// indicator forms.
    private var mappedState: SplayIslandState? {
        switch visual {
        case .hidden:        return nil
        case .idleCollapsed: return .dormant
        case .idleHover:     return .ready
        case .recording:     return .recording
        case .transcribing:  return .transcribing
        case .done:
            if case .error = pill.state { return .failed }
            return .done
        }
    }
}

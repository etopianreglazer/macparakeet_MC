import AppKit
import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

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

// MARK: - Shared layout (single source of truth for view + tracker)

enum IslandLayout {
    /// The panel is a fixed, generous stage; the pill morphs *within* it,
    /// horizontally centered and anchored just below the menu bar. Nothing
    /// resizes the panel, so the morph stays smooth and its hit geometry never
    /// changes with the lifecycle state.
    // The stage must be wide/tall enough to contain the widest indicator bloom
    // (the recording glow fans out well beyond the pill). The pill stays centred;
    // the extra width is transparent and click-through.
    static let panelWidth: CGFloat = 840
    static let panelHeight: CGFloat = 460

    /// The desktop glow renders on its own, *much wider* panel below app windows
    /// so the Ambilight wash can spread far and fade to nothing without clipping
    /// at a panel edge. It is inert and click-through, so the extra width is free.
    static let glowPanelWidth: CGFloat = 1400
    static let glowPanelHeight: CGFloat = 460

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

    /// Width of the right-edge stop-button hit zone inside the recording pill.
    static let stopHitWidth: CGFloat = 38

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

    /// The record dot's hit region — the right cluster of the ready pill. A click
    /// here records; a click elsewhere on the pill opens the recents card.
    static func recordButtonRect(notchAttached: Bool = false) -> CGRect {
        let ready = pillRect(for: .idleHover, notchAttached: notchAttached)
        let w: CGFloat = 52
        return CGRect(x: ready.maxX - w - 4, y: ready.minY, width: w, height: ready.height)
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
    /// Distance from the panel's physically hidden top to the housing's lower edge.
    var notchCueInset: CGFloat = 0
    init() {}
}

// MARK: - Island view

/// The ambient island hanging from the notch. Pure **indicator**: it renders the
/// lifecycle light (bloom + fiber stripe + mark) and nothing else — no controls,
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
                    level: Double(max(pill.micLevel, pill.systemLevel)),
                    notchAttached: chrome.isNotchResting
                )
                // Mirror the tracker's `pillRect` top offset exactly so the drawn
                // pill and its hit-rect stay aligned: flush to the physical top in
                // Notch mode, the menu-safe inset otherwise.
                .padding(.top, chrome.isNotchResting ? 0 : IslandLayout.topInset)
                // Pop the whole island in from slightly small, anchored at the
                // notch, so it reads as spawning rather than fading.
                .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
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

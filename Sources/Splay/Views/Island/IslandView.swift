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

/// The island's click targets per visual state (the whole pill, since the face
/// draws no buttons). Only used when `AppFeatures.islandTakesMouse` is on.
enum IslandControl: Equatable {
    case none
    case stop     // recording → stop
    case open     // done → open the menu card
}

/// What a click on the island does (`IslandLayout.clickAction`).
enum IslandClickAction: Equatable {
    case none
    case openCard
    case stop
}

/// Which capture the active island is showing — one pill, three faces.
enum IslandCaptureKind: Equatable {
    /// fn tap: mic-only recording — meter + timer.
    case recording
    /// fn triple-tap: mic + system — twin meter + timer.
    case meeting
    /// fn double-tap: dictation — meter only, plus a short ear right of the camera
    /// (no file, so no timer).
    case dictation
}

/// Dictation's lifecycle as the island shows it (fed by
/// `DictationFlowCoordinator.islandPhase(for:)`; nil = no dictation).
enum IslandDictationPhase: Equatable {
    case recording
    case transcribing
    case pasted
    case copied
    case failed
    /// Escape was pressed: discarding in `secondsLeft` unless fn is tapped.
    case cancelling(secondsLeft: Int)
}

/// A file transcription (menu ▸ Transcribe File, or a drop on the menu bar
/// icon) as the island shows it: the same spinner / check / failure faces a
/// recording ends with, and nothing else — no meter, no timer. Fed by
/// `FileJobIslandPresenter`; nil = no file job showing.
enum IslandFileJobPhase: Equatable {
    case transcribing
    case done
    case failed
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
    // hit-rects never drift from the drawn pill (both read `SplayGeometry.layout`).
    static func pillSize(
        for visual: IslandVisual, kind: IslandCaptureKind = .recording, notchAttached: Bool
    ) -> CGSize {
        guard let state = indicatorState(for: visual) else { return .zero }
        return SplayGeometry.layout(for: state, kind: kind, notchAttached: notchAttached).size
    }

    /// The indicator state whose geometry a visual uses (nil = hidden).
    static func indicatorState(for visual: IslandVisual) -> SplayIslandState? {
        switch visual {
        case .hidden:        return nil
        case .idleCollapsed: return .dormant
        case .idleHover:     return .ready
        case .recording:     return .recording
        case .transcribing:  return .transcribing
        case .done:          return .done
        }
    }

    /// Interaction rect for the AppKit tracker — simply the drawn pill (notch-mode
    /// hover is additionally served by `notchRevealRect`).
    static func hitRect(
        for visual: IslandVisual, kind: IslandCaptureKind = .recording, notchAttached: Bool = false
    ) -> CGRect {
        pillRect(for: visual, kind: kind, notchAttached: notchAttached)
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

    /// The control hit region for a visual. There are no small buttons any
    /// more (the face is display-only), so a running capture's stop target and
    /// the done pill's open target are the whole pill.
    static func controlRect(
        for visual: IslandVisual, kind: IslandCaptureKind = .recording, notchAttached: Bool = false
    ) -> CGRect {
        pillRect(for: visual, kind: kind, notchAttached: notchAttached)
    }

    /// Grace window after hover drops during which an idle click is still
    /// treated as aimed at the *revealed* pill (the hover race: `mouseDown`
    /// outrunning the tracker's hover flip, or the shallow stay-margin dropping
    /// hover between aim and click).
    static let hoverRaceGrace: TimeInterval = 0.7

    /// The visual a *click* should be resolved against. During the hover race
    /// the model reads dormant while the user clicks the *revealed* pill they
    /// saw drawn — whose edges poke outside the narrower nub's hit rect, so the
    /// click would be swallowed. So while hover is (or was just, within
    /// `hoverRaceGrace`) active, idle clicks inside the revealed geometry
    /// resolve against the revealed visual. A cold dormant click
    /// (`recentlyRevealed == false`) is never rerouted.
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
    /// visual — logged with each click; `clickAction` decides by visual alone.
    /// The island has no mark (owner, tuner round 2026-09-26), so idle has none.
    static func control(
        at point: CGPoint, visual: IslandVisual, kind: IslandCaptureKind, notchAttached: Bool
    ) -> IslandControl {
        switch visual {
        case .recording:
            return controlRect(for: .recording, kind: kind, notchAttached: notchAttached).contains(point) ? .stop : .none
        case .done:
            return controlRect(for: .done, kind: kind, notchAttached: notchAttached).contains(point) ? .open : .none
        case .hidden, .idleCollapsed, .idleHover, .transcribing:
            return .none
        }
    }

    /// What a click inside the pill does. Idle: open the card — the fallback way
    /// in when the menu bar icon is hidden behind the notch (fn is how you
    /// record). Recording: the whole bar stops. Done: open the card.
    static func clickAction(visual: IslandVisual, control: IslandControl) -> IslandClickAction {
        switch visual {
        case .idleCollapsed, .idleHover, .done: return .openCard
        case .recording: return .stop
        case .transcribing, .hidden: return .none
        }
    }

    /// The pill state the island shows. The meeting flow wins whenever it is not
    /// idle (fn never runs both); then a dictation; then a file transcription,
    /// which runs in the background and must never hide a live capture.
    static func effectiveState(
        pill: MeetingRecordingPillViewModel.PillState,
        dictation: IslandDictationPhase?,
        fileJob: IslandFileJobPhase? = nil
    ) -> MeetingRecordingPillViewModel.PillState {
        guard pill == .idle else { return pill }
        if let dictation {
            switch dictation {
            case .recording: return .recording
            case .transcribing: return .transcribing
            case .pasted, .copied, .cancelling: return .completed
            case .failed: return .error("dictation")
            }
        }
        switch fileJob {
        case .transcribing: return .transcribing
        case .done: return .completed
        case .failed: return .error("file")
        case nil: return pill
        }
    }

    static func captureKind(
        pill: MeetingRecordingPillViewModel.PillState,
        dictation: IslandDictationPhase?,
        meetingCapturesSystem: Bool
    ) -> IslandCaptureKind {
        if pill == .idle, dictation != nil { return .dictation }
        return meetingCapturesSystem ? .meeting : .recording
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
    static func pillRect(
        for visual: IslandVisual, kind: IslandCaptureKind = .recording, notchAttached: Bool = false
    ) -> CGRect {
        let size = pillSize(for: visual, kind: kind, notchAttached: notchAttached)
        let offset = indicatorState(for: visual).map {
            SplayGeometry.layout(for: $0, kind: kind, notchAttached: notchAttached).centerOffset
        } ?? 0
        let topBreathingRoom = notchAttached ? 0 : topInset
        return CGRect(
            x: (panelWidth - size.width) / 2 + offset,
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
    /// The cursor is over a running capture's pill (fed by the AppKit tracker).
    /// The view lifts the pill slightly; cleared whenever the pill stops recording.
    var captureHovered = false
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
    /// Live **system audio** level (0…1) for a meeting's second meter.
    var liveSystemLevel: Double = 0
    /// The running meeting captures system audio (triple-tap) — twin meter.
    var meetingCapturesSystem = false
    /// The dictation the island is showing, if any (nil = none).
    var dictation: IslandDictationPhase?
    /// The file transcription the island is showing, if any (nil = none).
    var fileJob: IslandFileJobPhase?
    init() {}
}

// MARK: - Island view

/// The ambient island hanging from the notch. Pure **indicator**: it renders the
/// lifecycle (meters, timer, glyphs) and nothing else — no controls and no clicks
/// (`AppFeatures.islandTakesMouse`); its only reaction to the cursor is a slight
/// lift while a capture runs. Anything the app needs to *say* is a card, opened
/// from the menu bar icon.
struct IslandView: View {
    @Bindable var pill: MeetingRecordingPillViewModel
    @Bindable var chrome: IslandChromeModel

    private var effectiveState: MeetingRecordingPillViewModel.PillState {
        IslandLayout.effectiveState(pill: pill.state, dictation: chrome.dictation, fileJob: chrome.fileJob)
    }

    private var visual: IslandVisual {
        IslandLayout.visual(
            for: effectiveState,
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
                    captureKind: IslandLayout.captureKind(
                        pill: pill.state, dictation: chrome.dictation,
                        meetingCapturesSystem: chrome.meetingCapturesSystem
                    ),
                    level: chrome.liveLevel,
                    systemLevel: chrome.liveSystemLevel,
                    elapsedSeconds: pill.elapsedSeconds,
                    cancelSecondsLeft: cancelSecondsLeft,
                    audioAlive: chrome.audioAlive,
                    notchAttached: chrome.isNotchResting
                )
                // Mirror the tracker's `pillRect` top offset exactly so the drawn
                // pill and its hit-rect stay aligned: flush to the physical top in
                // Notch mode, the menu-safe inset otherwise.
                .padding(.top, chrome.isNotchResting ? 0 : IslandLayout.topInset)
                // A running capture lifts slightly under the cursor, anchored at
                // the notch so it grows downward and outward, never off-axis.
                .scaleEffect(liftsForHover ? SplayGeometry.captureHoverScale : 1, anchor: .top)
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
        .animation(motion, value: liftsForHover)
        // A stale hover must not lift the next capture before the cursor moves.
        .onChange(of: visual) { _, newVisual in
            if newVisual != .recording { chrome.captureHovered = false }
        }
        // Display-only: the AppKit tracker owns all hover/click.
        .allowsHitTesting(false)
    }

    private var cancelSecondsLeft: Int? {
        if case .cancelling(let left) = chrome.dictation { return left }
        return nil
    }

    private var liftsForHover: Bool { visual == .recording && chrome.captureHovered }

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
            if case .error = effectiveState { return .failed }
            if pill.state == .idle {
                if chrome.dictation == .copied { return .copied }
                if cancelSecondsLeft != nil { return .cancelling }
            }
            return .done
        }
    }
}

import AppKit
import SwiftUI
import SplayCore
import SplayViewModels

// MARK: - Tracking layer

/// Routes hover + clicks for the pill — **dormant** while
/// `AppFeatures.islandTakesMouse` is false (the panel ignores the mouse, so none
/// of this runs; kept so the flag can restore clicks). The SwiftUI content is
/// display-only, so this AppKit view owns interaction (hover/click on a non-key
/// floating panel can't go through SwiftUI). With the flag on: an idle click or
/// the done pill opens the card, a click on a running capture stops it.
private final class IslandTrackingView: NSView {
    var stateProvider: () -> MeetingRecordingPillViewModel.PillState = { .idle }
    var idleVisibleProvider: () -> Bool = { true }
    var heldOpenProvider: () -> Bool = { false }
    var notchProvider: () -> Bool = { false }
    var kindProvider: () -> IslandCaptureKind = { .recording }

    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    /// An idle click, or a click on the done pill — open the menu card.
    var onOpenCard: (() -> Void)?
    /// A click on a running capture — stop it.
    var onStopClick: (() -> Void)?

    /// Cursor is over the idle nub's hover zone (grows the pill to the hint).
    private var hovering = false {
        didSet {
            if oldValue && !hovering { hoverDroppedAt = Date() }
            if oldValue != hovering {
                AudioCaptureDiagnostics.append("splay_island hover=\(hovering ? "enter" : "exit")")
            }
        }
    }
    /// When hover last dropped — the click router and the active-rect gate treat
    /// a click within `IslandLayout.hoverRaceGrace` of it (or while still
    /// hovering) as aimed at the *revealed* pill, so a `mouseDown` that outruns
    /// the tracker's hover flip still reaches the revealed pill. A cold dormant nub
    /// (no recent hover) keeps its narrow gate and pass-through pixels.
    private var hoverDroppedAt: Date?
    private var recentlyRevealed: Bool {
        hovering || hoverDroppedAt.map { Date().timeIntervalSince($0) < IslandLayout.hoverRaceGrace } ?? false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    private func currentVisual() -> IslandVisual {
        IslandLayout.visual(
            for: stateProvider(),
            hovered: hovering,
            idleVisible: idleVisibleProvider(),
            heldOpen: heldOpenProvider()
        )
    }

    func currentActiveRect() -> CGRect {
        let visual = currentVisual()
        // During the hover race the gate must admit the *revealed* geometry —
        // otherwise the revealed edges that poke outside the narrower nub are
        // dropped here and `dispatchClick`'s re-resolution never runs. A cold
        // dormant nub (no recent hover) keeps the narrow rect so the pixels
        // around the hidden bar stay click-through.
        if visual == .idleCollapsed, recentlyRevealed {
            return IslandLayout.hitRect(for: .idleHover, notchAttached: notchProvider())
        }
        return IslandLayout.hitRect(for: visual, kind: kindProvider(), notchAttached: notchProvider())
    }

    override func mouseExited(with event: NSEvent) {
        if hovering { hovering = false; onHoverExit?() }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Idle nub → ready growth (hysteresis) lives only in the idle form.
        if stateProvider() == .idle {
            // Hysteresis: a "reach the notch/back" zone activates the ready pill; a
            // larger "stay while on the tile" zone keeps it active so crossing onto
            // the pill no longer snaps it back to idle.
            let enterRect = notchProvider()
                ? IslandLayout.notchRevealRect()
                : IslandLayout.hitRect(for: .idleCollapsed, notchAttached: false)
            let stayRect = IslandLayout.hoverStayRect(notchAttached: notchProvider())
            let active = hovering ? stayRect : enterRect
            if active.contains(point) {
                if !hovering { hovering = true; onHoverEnter?() }
            } else {
                if hovering { hovering = false; onHoverExit?() }
            }
        } else if hovering {
            hovering = false; onHoverExit?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dispatchClick(at: convert(event.locationInWindow, from: nil), source: "mouseDown")
    }

    /// Dispatch a click at `point` (this view's coordinates). Shared by the
    /// AppKit `mouseDown` path and the controller's event monitors; `source`
    /// records which of the three actually delivered it (the local monitor is the
    /// only one that can fire while Splay itself is the active app).
    func dispatchClick(at point: CGPoint, source: String = "direct") {
        // Hover-race tolerance lives in `clickVisual`: an idle click lands on
        // the revealed geometry only if hover is (or was just) active, so a
        // racing click reaches the revealed pill while a cold dormant click
        // resolves against the nub.
        let visual = IslandLayout.clickVisual(
            for: currentVisual(), at: point,
            notchAttached: notchProvider(), recentlyRevealed: recentlyRevealed
        )
        guard IslandLayout.hitRect(for: visual, kind: kindProvider(), notchAttached: notchProvider()).contains(point) else {
            AudioCaptureDiagnostics.append(
                "splay_island click_rejected src=\(source) point=\(point) visual=\(visual) hovering=\(hovering) "
                + "recently_revealed=\(recentlyRevealed) rect=\(IslandLayout.hitRect(for: visual, kind: kindProvider(), notchAttached: notchProvider()))"
            )
            return
        }
        let control = IslandLayout.control(at: point, visual: visual, kind: kindProvider(), notchAttached: notchProvider())
        let action = IslandLayout.clickAction(visual: visual, control: control)
        AudioCaptureDiagnostics.append(
            "splay_island click src=\(source) control=\(control) visual=\(visual) action=\(action)"
        )
        switch action {
        case .openCard:
            hovering = false
            onOpenCard?()
        case .stop:
            onStopClick?()
        case .none:
            break
        }
    }

    // Behave as a subview hit target (the container gates the active rect).
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point)
    }
}

// MARK: - Panel

/// A borderless floating panel. It stays non-key (ambient) — the island never
/// takes focus, since it holds no controls the keyboard drives.
private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A lightweight AppKit cue for the otherwise hidden camera-housing anchor.
/// Retired in the two-surface design; kept inert/hidden so its layer work
/// never runs.
private final class IslandNotchCueView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Container (the panel's contentView)

/// Plain container that owns the SwiftUI display + the tracking subview. Its
/// hitTest descends to a *subview* within the active rect and returns `nil`
/// elsewhere (pass-through). A hitTest that resolves to the contentView itself is
/// treated as a window-background click and never delivers `mouseDown`, so the
/// click target must be a subview.
private final class IslandContainerView: NSView {
    var activeRectProvider: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        guard activeRectProvider().contains(local) else { return nil }
        return super.hitTest(point)
    }
}

// MARK: - Island controller

/// Owns the single, long-lived top-center island panel. The SwiftUI
/// `IslandView` morphs through the capture lifecycle (dormant → recording →
/// transcribing → done) as a pure indicator for all three fn captures
/// (recording, meeting, dictation). It takes no mouse input
/// (`AppFeatures.islandTakesMouse`): fn starts and stops, the menu bar icon
/// opens the card. The island never becomes a control surface.
@MainActor
final class IslandController: NSObject {
    private var anchorPanel: NSPanel?
    private var panel: IslandPanel?
    private var hostingView: NSHostingView<IslandView>?
    private var trackingView: IslandTrackingView?
    private var notchCue: IslandNotchCueView?
    /// Click monitors — only installed when `AppFeatures.islandTakesMouse`.
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var defaultsObserver: NSObjectProtocol?
    private var appResignActiveObserver: NSObjectProtocol?
    private var ambientVisibilityTimer: Timer?
    private var isExplicitlyHiding = false

    private let pillViewModel: MeetingRecordingPillViewModel
    private let chrome = IslandChromeModel()

    private var placementPreference: IslandPlacementPreference {
        IslandPlacementPreference(rawValue: UserDefaults.standard.string(forKey: IslandPlacementPreference.defaultsKey) ?? "") ?? .automatic
    }

    private func resolvesNotch(for screen: NSScreen) -> Bool {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let builtIn = number.map { CGDisplayIsBuiltin(CGDirectDisplayID($0.uint32Value)) != 0 } ?? false
        let auxiliary = !(screen.auxiliaryTopLeftArea ?? .zero).isEmpty || !(screen.auxiliaryTopRightArea ?? .zero).isEmpty
        return IslandPlacementPreference.resolved(placementPreference, safeAreaTop: screen.safeAreaInsets.top, hasAuxiliaryTopArea: auxiliary, isBuiltIn: builtIn) == .notch
    }

    /// A running capture was clicked — stop it (only with `islandTakesMouse`).
    var onStop: (() -> Void)?
    /// The idle island or the done pill was clicked — open the menu card (only
    /// with `islandTakesMouse`).
    var onOpenCard: (() -> Void)?

    init(pillViewModel: MeetingRecordingPillViewModel, idleVisible: Bool) {
        self.pillViewModel = pillViewModel
        self.chrome.idleVisible = idleVisible
        super.init()
    }

    func show() {
        if panel != nil { return }

        let bounds = NSRect(x: 0, y: 0, width: IslandLayout.panelWidth, height: IslandLayout.panelHeight)
        let container = IslandContainerView(frame: bounds)

        let view = IslandView(pill: pillViewModel, chrome: chrome)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]

        let tracker = IslandTrackingView(frame: bounds)
        tracker.autoresizingMask = [.width, .height]
        tracker.stateProvider = { [weak self] in
            guard let self else { return .idle }
            return IslandLayout.effectiveState(pill: self.pillViewModel.state, dictation: self.chrome.dictation)
        }
        tracker.idleVisibleProvider = { [weak self] in self?.chrome.idleVisible ?? true }
        tracker.heldOpenProvider = { [weak self] in self?.chrome.heldOpen ?? false }
        tracker.notchProvider = { [weak self] in self?.chrome.isNotchResting ?? false }
        tracker.kindProvider = { [weak self] in
            guard let self else { return .recording }
            return IslandLayout.captureKind(
                pill: self.pillViewModel.state, dictation: self.chrome.dictation,
                meetingCapturesSystem: self.chrome.meetingCapturesSystem
            )
        }
        tracker.onHoverEnter = { [weak self] in self?.chrome.isHovered = true }
        tracker.onHoverExit = { [weak self] in self?.chrome.isHovered = false }
        tracker.onOpenCard = { [weak self] in
            self?.chrome.isHovered = false
            self?.onOpenCard?()
        }
        tracker.onStopClick = { [weak self] in
            guard let self else { return }
            self.onStop?()
        }
        trackingView = tracker

        container.addSubview(hosting)   // display (below)
        let cue = IslandNotchCueView(frame: bounds)
        cue.autoresizingMask = [.width, .height]
        container.addSubview(cue)       // decorative and always mouse-transparent
        container.addSubview(tracker)   // events (on top)
        container.activeRectProvider = { [weak tracker] in tracker?.currentActiveRect() ?? .zero }

        let panel = IslandPanel(
            contentRect: bounds,
            // `.nonactivatingPanel` keeps this ambient companion from ever becoming
            // key or activating Splay. (When `islandTakesMouse` is on, it is also
            // what lets it take a click in *both* activation states.) Matches
            // every other floating panel in the app.
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Hover-enter lives entirely in the tracker's `mouseMoved`; an NSPanel does
        // NOT post mouseMoved to its views unless this is enabled. Inert while
        // `ignoresMouseEvents` is set below (no hover, so the nub never grows).
        panel.acceptsMouseMovedEvents = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // Splay is an ambient global control, not a document window. Joining
        // every Space keeps the physical-top companion visible when the user
        // switches desktops or enters a browser/full-screen Space; its own
        // transparent hit testing still prevents a broad interaction overlay.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = container
        // Indicator only: every click (and hover) goes straight through to the
        // app beneath — the island sits over address bars and tabs.
        panel.ignoresMouseEvents = !AppFeatures.islandTakesMouse

        if let screen = NSScreen.main {
            chrome.isNotchResting = resolvesNotch(for: screen)
            chrome.notchCueInset = 0
            if chrome.isNotchResting {
                // Keep the hardware-sized anchor inert behind the camera
                // housing, but render the visible companion at the *physical*
                // top edge. `.floating` is menu-safe-clamped on this Mac; a
                // pop-up-menu companion is the narrow, intentional exception.
                panel.level = .popUpMenu
                let anchor = NSPanel(contentRect: NSRect(x: screen.frame.midX - 90, y: screen.frame.maxY - screen.safeAreaInsets.top, width: 180, height: screen.safeAreaInsets.top), styleMask: [.borderless], backing: .buffered, defer: false)
                anchor.isOpaque = false; anchor.backgroundColor = .clear; anchor.level = .statusBar; anchor.ignoresMouseEvents = true
                anchor.orderFront(nil); anchorPanel = anchor
                panel.setFrameOrigin(NSPoint(x: screen.frame.midX - bounds.width / 2, y: screen.frame.maxY - bounds.height))
            } else { panel.setFrameOrigin(topCenterOrigin(for: screen, panelSize: bounds.size)) }
        }

        panel.orderFrontRegardless()
        AudioCaptureDiagnostics.append("splay_island ordered visible=\(panel.isVisible) frame=\(NSStringFromRect(panel.frame)) level=\(panel.level.rawValue) idle=\(chrome.idleVisible) notch=\(chrome.isNotchResting)")
        self.panel = panel
        self.hostingView = hosting
        self.notchCue = cue
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.repositionPanel() }
        }
        // Switching an LSUIElement/accessory app away from the foreground can
        // order its panels out despite `hidesOnDeactivate = false`. The island
        // is intentionally ambient, so restore only its already-visible,
        // non-key surface on the next turn of the run loop.
        appResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restoreAmbientVisibility() }
        }
        // Accessory apps can lose a floating/popup companion during a later
        // Space transaction without emitting a public window-order-out event.
        // Keep this one ambient (never-key) surface ordered while Splay lives.
        ambientVisibilityTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isExplicitlyHiding else { return }
                self.restoreAmbientVisibility()
            }
        }
        if AppFeatures.islandTakesMouse { installClickMonitors() }
    }

    /// Re-order the existing ambient panels after an activation-policy change
    /// or resignation. This intentionally does not make Splay key or focus a
    /// text field, and transparent regions remain pass-through.
    func restoreAmbientVisibility() {
        // `setActivationPolicy(.accessory)` hides windows asynchronously. A
        // same-turn `orderFrontRegardless()` is therefore overwritten by the
        // system's pending hide; reorder after that policy transaction drains.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            // Accessory-policy transitions can hide the whole app, in which
            // case ordering a panel alone is ignored by WindowServer. Unhide
            // without activating/focusing Splay, then restore the ambient card.
            if NSApp.isHidden { NSApp.unhide(nil) }
            if self.chrome.isNotchResting { self.anchorPanel?.orderFrontRegardless() }
            panel.orderFrontRegardless()
        }
    }

    /// Keeps the ambient surface directly below the menu-bar safe region rather
    /// than over its controls. Use the *physical* screen frame for horizontal
    /// centering: `visibleFrame` may exclude a left/right Dock and therefore
    /// has a midpoint that is not the display/notch/webcam axis. Its maxY still
    /// supplies the safe vertical boundary below the menu bar.
    private func topCenterOrigin(for screen: NSScreen, panelSize: CGSize) -> NSPoint {
        IslandPlacementPreference.panelOrigin(
            screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top, panelSize: panelSize,
            preference: placementPreference
        )
    }

    /// Re-resolve notch mode and re-anchor the (fixed-size) panel. The
    /// panel never resizes — it is a stage the pill morphs within — so this only
    /// runs when the placement preference or screen geometry may have changed.
    private func repositionPanel() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        chrome.isNotchResting = resolvesNotch(for: screen)
        panel.level = chrome.isNotchResting ? .popUpMenu : .floating
        chrome.notchCueInset = 0
        let size = CGSize(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight)
        let origin: NSPoint
        if chrome.isNotchResting {
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        } else {
            origin = topCenterOrigin(for: screen, panelSize: size)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: Click monitors

    /// Catch the click at the event level rather than relying on the panel's view
    /// hit-testing (unreliable for a non-key floating panel).
    ///
    /// The two cover disjoint halves of the world and both are load-bearing: AppKit
    /// never reports our own app's events to a global monitor, so the **global** one
    /// serves only the window where Splay is *inactive*, and the **local** one is the
    /// sole path for any click that lands while Splay holds the foreground (which it
    /// does for as long as a card is up, and briefly after).
    ///
    /// Both resolve the click in *screen* space, so the two paths agree by
    /// construction. The local one accepts a click tagged with this panel or with no
    /// window at all, and declines one tagged with a different Splay window — the
    /// card's frame can overlap this panel's, and its clicks are its own. Every
    /// decline inside the panel frame is logged, so a click that fails to route is
    /// always visible in the diagnostics rather than vanishing.
    private func installClickMonitors() {
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  let panel = self.panel,
                  let tracker = self.trackingView else { return event }
            // Never steal a click that belongs to another Splay window (the card
            // can overlap the island's panel frame while it is up).
            if let window = event.window, window !== panel { return event }
            // `locationInWindow` is window-relative when the event has a window and
            // screen-relative when it doesn't; normalise to screen, then to panel.
            let screenPoint = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) }
                ?? event.locationInWindow
            let local = CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
            if tracker.currentActiveRect().contains(local) {
                tracker.dispatchClick(at: local, source: "local")
                return nil
            }
            if panel.frame.contains(NSPoint(x: screenPoint.x, y: screenPoint.y)) {
                AudioCaptureDiagnostics.append(
                    "splay_island monitor_rejected src=local point=\(local) rect=\(tracker.currentActiveRect()) "
                    + "window=\(event.window.map { String(describing: type(of: $0)) } ?? "nil")"
                )
            }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  let panel = self.panel, let tracker = self.trackingView else { return }
            let screenPoint = event.locationInWindow   // screen coords for global events
            let local = CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
            guard tracker.currentActiveRect().contains(local) else {
                // Log only clicks that land within the panel's bounds — a global
                // monitor sees every click on the desktop, and those are noise.
                if panel.frame.insetBy(dx: 0, dy: 0).contains(NSPoint(x: screenPoint.x, y: screenPoint.y)) {
                    AudioCaptureDiagnostics.append(
                        "splay_island monitor_rejected src=global point=\(local) rect=\(tracker.currentActiveRect())"
                    )
                }
                return
            }
            tracker.dispatchClick(at: local, source: "global")
        }
    }

    private func removeClickMonitors() {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localClickMonitor = nil
        globalClickMonitor = nil
    }

    func hide() {
        isExplicitlyHiding = true
        removeClickMonitors()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
        if let appResignActiveObserver { NotificationCenter.default.removeObserver(appResignActiveObserver) }
        appResignActiveObserver = nil
        ambientVisibilityTimer?.invalidate()
        ambientVisibilityTimer = nil
        panel?.orderOut(nil)
        anchorPanel?.orderOut(nil)
        anchorPanel = nil
        panel = nil
        hostingView = nil
        trackingView = nil
        notchCue = nil
    }

    /// Reflect the user's "show idle pill" preference. Recording-flow states are
    /// shown regardless; this only governs the idle nub/hover.
    func setIdleVisible(_ visible: Bool) {
        chrome.idleVisible = visible
    }

    /// Clear hover (e.g. when a recording starts via the Fn key, not a click).
    func resetHover() {
        chrome.isHovered = false
    }

    /// Hold the idle island in its ready ("open") form while a card is showing, so
    /// the two surfaces open and close together. The `IslandView` animates the
    /// morph on its `value: visual` transaction.
    func setHeldOpen(_ open: Bool) {
        chrome.heldOpen = open
    }

    /// Push the live mic level (0…1) into the island's isolated `liveLevel`
    /// channel at recording rate (~30 fps). This is the island's equivalent of the
    /// floating pill's CALayer feed — only the island surfaces observe
    /// `IslandChromeModel`, and they already re-render each frame while recording,
    /// so this avoids 30 fps writes to the shared pill VM (which the Transcribe tile
    /// reads). Change-gated so an unchanged level never invalidates the view.
    func updateLiveAudioLevel(_ level: Float) {
        let v = Double(min(1, max(0, level)))
        guard chrome.liveLevel != v else { return }
        chrome.liveLevel = v
    }

    /// Push whether audio frames are actually arriving (1 Hz, from the
    /// coordinator's writer-health poll). While recording, false turns the
    /// island's meter + timer a motionless warning amber (dead ≠ silent).
    /// Push the live system-audio level (0…1) for a meeting's second meter.
    func updateLiveSystemAudioLevel(_ level: Float) {
        let v = Double(max(0, min(1, level)))
        guard chrome.liveSystemLevel != v else { return }
        chrome.liveSystemLevel = v
    }

    /// The meeting flow settled its audio source for this recording.
    func setMeetingCapturesSystem(_ captures: Bool) {
        guard chrome.meetingCapturesSystem != captures else { return }
        chrome.meetingCapturesSystem = captures
    }

    /// The dictation flow's phase changed (nil = no dictation showing).
    func setDictationPhase(_ phase: IslandDictationPhase?) {
        guard chrome.dictation != phase else { return }
        if phase == nil { chrome.liveLevel = 0 }
        chrome.dictation = phase
    }

    func updateAudioAlive(_ alive: Bool) {
        guard chrome.audioAlive != alive else { return }
        chrome.audioAlive = alive
    }
}

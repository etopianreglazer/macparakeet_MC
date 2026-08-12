import AppKit
import SwiftUI
import SplayCore
import SplayViewModels

// MARK: - Tracking layer

/// Routes hover + clicks for the pill. The SwiftUI content is display-only, so
/// this AppKit view owns interaction (hover/click on a non-key floating panel
/// can't go through SwiftUI). The island is an indicator only — a click opens a
/// card (the second surface); it never expands the pill into a control surface.
private final class IslandTrackingView: NSView {
    var stateProvider: () -> MeetingRecordingPillViewModel.PillState = { .idle }
    var idleVisibleProvider: () -> Bool = { true }
    var heldOpenProvider: () -> Bool = { false }
    var notchProvider: () -> Bool = { false }

    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    /// The mark (left cluster) was clicked — open the menu card. A click anywhere
    /// else on the pill records or stops instead.
    var onOpenCard: (() -> Void)?
    /// An idle click off the mark (the status dot, or the bar) — start a recording.
    var onRecordClick: (() -> Void)?
    var onStopClick: (() -> Void)?
    /// The control under the cursor changed (record / stop / open / none) — drives
    /// the SwiftUI hover pop. Distinct from `onHoverEnter/Exit`, which only govern
    /// the idle nub → ready growth.
    var onControlHover: ((IslandControl) -> Void)?
    /// A control was pressed (a click pulse: pressed → released) — drives the
    /// SwiftUI "physical key" depress on the touched control.
    var onControlPress: ((IslandControl) -> Void)?

    /// Cursor is over the idle nub's hover zone (grows the pill to the hint).
    private var hovering = false
    /// Last control the cursor was over, so we only signal on change.
    private var lastControl: IslandControl = .none

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
        IslandLayout.hitRect(for: currentVisual(), notchAttached: notchProvider())
    }

    override func mouseExited(with event: NSEvent) {
        if hovering { hovering = false; onHoverExit?() }
        setControlHover(.none)
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

        // Per-control hover (mark / status dot / open button) for the pop
        // feedback — computed for whatever the current visual is, in every state.
        setControlHover(IslandLayout.control(at: point, visual: currentVisual(), notchAttached: notchProvider()))
    }

    /// Signal the hovered control only when it changes.
    private func setControlHover(_ control: IslandControl) {
        guard control != lastControl else { return }
        lastControl = control
        onControlHover?(control)
    }

    override func mouseDown(with event: NSEvent) {
        dispatchClick(at: convert(event.locationInWindow, from: nil))
    }

    /// Dispatch a click at `point` (this view's coordinates). Shared by the
    /// AppKit `mouseDown` path and the controller's event monitors.
    func dispatchClick(at point: CGPoint) {
        let visual = currentVisual()
        guard IslandLayout.hitRect(for: visual, notchAttached: notchProvider()).contains(point) else { return }
        let control = IslandLayout.control(at: point, visual: visual, notchAttached: notchProvider())

        // Depress the touched control like a physical key (a short pulse), before
        // running its action. Only a real glyph (mark / dot / open) depresses; a
        // click on the empty bar records but has nothing to push down.
        pressPulse(control)

        // The mark (left cluster) opens the card in every state where it's shown —
        // this is the "click the splay icon to reach the menu" affordance. It takes
        // precedence over the pill-body actions below.
        if control == .menu {
            hovering = false
            onOpenCard?()
            return
        }

        switch visual {
        case .idleCollapsed, .idleHover:
            // Recording is the primary action, so a click anywhere on the idle
            // island *other than the mark* records — no hover required. The mark
            // (handled above) is the one spot that opens the menu instead.
            hovering = false
            onRecordClick?()
        case .recording:
            // A click anywhere on the recording bar (off the mark) stops it — the
            // glowing dot is the affordance but the whole bar is forgiving.
            onStopClick?()
        case .done:
            onOpenCard?()                                 // after a recording, the done pill opens the card
        case .transcribing, .hidden:
            break
        }
    }

    /// Fire a short "pressed" pulse on the touched control, then release it, so the
    /// SwiftUI indicator can depress it like a physical key. Auto-releases (rather
    /// than tracking mouse-up) so a fast tap is still visibly a down-then-up press.
    private func pressPulse(_ control: IslandControl) {
        guard control != .none else { return }
        onControlPress?(control)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
            self?.onControlPress?(.none)
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
/// Retired in the two-surface design (the bloom + fiber stripe are the light
/// now); kept inert/hidden so its layer work never runs.
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
/// transcribing → done) as a pure indicator. Interaction is minimal: hover grows
/// the nub; clicking the mark (left) opens a card (`onOpenCard`); clicking the
/// status dot — or anywhere else on the bar — records (idle) or stops (recording).
/// The island never becomes a control surface.
@MainActor
final class IslandController: NSObject {
    private var anchorPanel: NSPanel?
    private var panel: IslandPanel?
    private var hostingView: NSHostingView<IslandView>?
    private var trackingView: IslandTrackingView?
    private var notchCue: IslandNotchCueView?
    /// The ambient bloom rendered on its own panel *below* app windows, so the
    /// light sprays onto the wallpaper instead of hovering over the user's work.
    private var glowPanel: NSPanel?
    private var glowHosting: NSHostingView<SplayGlowView>?
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

    /// The recording bar was clicked off the mark — stop the recording.
    var onStop: (() -> Void)?
    /// Start a recording with the chosen source mode (the status dot, or any idle
    /// click off the mark).
    var onRecord: ((MeetingAudioSourceMode) -> Void)?
    /// The mark was clicked (any state), or the done pill — open the menu card.
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
        tracker.stateProvider = { [weak self] in self?.pillViewModel.state ?? .idle }
        tracker.idleVisibleProvider = { [weak self] in self?.chrome.idleVisible ?? true }
        tracker.heldOpenProvider = { [weak self] in self?.chrome.heldOpen ?? false }
        tracker.notchProvider = { [weak self] in self?.chrome.isNotchResting ?? false }
        tracker.onHoverEnter = { [weak self] in self?.chrome.isHovered = true }
        tracker.onHoverExit = { [weak self] in self?.chrome.isHovered = false }
        tracker.onOpenCard = { [weak self] in
            self?.chrome.isHovered = false
            self?.onOpenCard?()
        }
        tracker.onRecordClick = { [weak self] in
            // A click anywhere on the idle island starts a mic recording (mirrors
            // fn; solo voice notes are the common case, hardware fn keeps its
            // single=mic / double=mic+system behaviour).
            guard let self else { return }
            self.chrome.isHovered = false
            self.chrome.hoveredControl = .none
            self.onRecord?(.microphoneOnly)
        }
        tracker.onStopClick = { [weak self] in
            guard let self else { return }
            self.onStop?()
        }
        tracker.onControlHover = { [weak self] control in
            self?.chrome.hoveredControl = control
        }
        tracker.onControlPress = { [weak self] control in
            self?.chrome.pressedControl = control
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
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Hover-enter lives entirely in the tracker's `mouseMoved`. An NSPanel
        // does NOT post mouseMoved to its views unless this is enabled, so without
        // it the resting nub never grew when the cursor reached it. (mouseExited
        // still comes via the tracking area regardless.)
        panel.acceptsMouseMovedEvents = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // Splay is an ambient global control, not a document window. Joining
        // every Space keeps the physical-top companion visible when the user
        // switches desktops or enters a browser/full-screen Space; its own
        // transparent hit testing still prevents a broad interaction overlay.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = container

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
        installGlowPanel()
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
        installClickMonitors()
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
            // Re-assert the desktop glow; its level keeps it below normal windows.
            self.glowPanel?.orderFrontRegardless()
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

    /// Re-resolve notch mode and re-anchor the (fixed-size) panel + glow. The
    /// panel never resizes — it is a stage the pill morphs within — so this only
    /// runs when the placement preference or screen geometry may have changed.
    private func repositionPanel() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        chrome.isNotchResting = resolvesNotch(for: screen)
        panel.level = chrome.isNotchResting ? .popUpMenu : .floating
        chrome.notchCueInset = 0
        positionGlowPanel()
        let size = CGSize(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight)
        let origin: NSPoint
        if chrome.isNotchResting {
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        } else {
            origin = topCenterOrigin(for: screen, panelSize: size)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: Desktop glow panel (the light spills onto the wallpaper, below windows)

    /// Build the second panel that renders only the ambient bloom, at a level
    /// *below* normal app windows. The pill panel stays on top and carries state;
    /// this glow drops behind whatever window is open, so it never distracts as a
    /// foreground overlay. It is inert (ignores all mouse events).
    private func installGlowPanel() {
        let size = CGSize(width: IslandLayout.glowPanelWidth, height: IslandLayout.glowPanelHeight)
        let glow = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        glow.isOpaque = false
        glow.backgroundColor = .clear
        glow.hasShadow = false
        glow.ignoresMouseEvents = true
        // One below `.normal` → above the wallpaper/desktop icons, below every
        // app window, so the glow reads as light on the desktop itself.
        glow.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        glow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let hosting = NSHostingView(rootView: SplayGlowView(pill: pillViewModel, chrome: chrome))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        glow.contentView = hosting
        self.glowPanel = glow
        self.glowHosting = hosting
        positionGlowPanel()
        glow.orderFrontRegardless()   // visible, but stays below normal windows via its level
    }

    /// Keep the glow panel aligned with the pill's idle frame.
    private func positionGlowPanel() {
        guard let glow = glowPanel, let screen = panel?.screen ?? NSScreen.main else { return }
        let size = CGSize(width: IslandLayout.glowPanelWidth, height: IslandLayout.glowPanelHeight)
        let origin: NSPoint
        if chrome.isNotchResting {
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        } else {
            origin = IslandPlacementPreference.panelOrigin(
                screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                safeAreaTop: screen.safeAreaInsets.top, panelSize: size,
                preference: placementPreference
            )
        }
        glow.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: Click monitors

    /// Catch the click at the event level rather than relying on the panel's view
    /// hit-testing (unreliable for a non-key floating panel).
    private func installClickMonitors() {
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  let panel = self.panel, event.window === panel,
                  let tracker = self.trackingView else { return event }
            let local = tracker.convert(event.locationInWindow, from: nil)
            if tracker.currentActiveRect().contains(local) {
                tracker.dispatchClick(at: local)
                return nil
            }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  let panel = self.panel, let tracker = self.trackingView else { return }
            let screenPoint = event.locationInWindow   // screen coords for global events
            let local = CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
            guard tracker.currentActiveRect().contains(local) else { return }
            tracker.dispatchClick(at: local)
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
        glowPanel?.orderOut(nil)
        anchorPanel = nil
        panel = nil
        hostingView = nil
        trackingView = nil
        notchCue = nil
        glowPanel = nil
        glowHosting = nil
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
}

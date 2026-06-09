import AppKit
import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

// MARK: - Tracking layer

/// Routes hover + clicks for the non-expanded pill states. The SwiftUI content
/// is display-only in those states and this AppKit view owns interaction
/// (hover/click on a non-key floating panel can't go through SwiftUI). When the
/// island is *expanded*, this view steps aside (hitTest → nil) so the real
/// SwiftUI controls (search field, buttons) receive events directly.
private final class IslandTrackingView: NSView {
    var stateProvider: () -> MeetingRecordingPillViewModel.PillState = { .idle }
    var idleVisibleProvider: () -> Bool = { true }
    var expandedProvider: () -> Bool = { false }

    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    var onIdleClick: (() -> Void)?
    var onStopClick: (() -> Void)?
    var onBodyClick: (() -> Void)?

    /// Cursor is over the idle nub's hover zone (grows the pill to the hint).
    private var hovering = false

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
            expanded: expandedProvider()
        )
    }

    func currentActiveRect() -> CGRect { IslandLayout.hitRect(for: currentVisual()) }

    override func mouseExited(with event: NSEvent) {
        if hovering { hovering = false; onHoverExit?() }
    }

    override func mouseMoved(with event: NSEvent) {
        // Hover only matters in the idle form.
        guard !expandedProvider(), stateProvider() == .idle else {
            if hovering { hovering = false; onHoverExit?() }
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if currentActiveRect().contains(point) {
            if !hovering { hovering = true; onHoverEnter?() }
        } else {
            if hovering { hovering = false; onHoverExit?() }
        }
    }

    override func mouseDown(with event: NSEvent) {
        dispatchClick(at: convert(event.locationInWindow, from: nil))
    }

    /// Dispatch a click at `point` (this view's coordinates). Shared by the
    /// AppKit `mouseDown` path and the controller's event monitors. No-op when
    /// expanded (SwiftUI owns interaction then).
    func dispatchClick(at point: CGPoint) {
        guard !expandedProvider() else { return }
        let visual = currentVisual()
        guard IslandLayout.hitRect(for: visual).contains(point) else { return }

        switch visual {
        case .idleCollapsed, .idleHover:
            hovering = false
            onIdleClick?()
        case .recording:
            let pill = IslandLayout.pillRect(for: visual)
            let stopRect = CGRect(
                x: pill.maxX - IslandLayout.stopHitWidth,
                y: pill.minY,
                width: IslandLayout.stopHitWidth,
                height: pill.height
            )
            if stopRect.contains(point) { onStopClick?() }
        case .done:
            onBodyClick?()
        case .transcribing, .hidden, .expanded:
            break
        }
    }

    // When expanded, step aside so the SwiftUI controls below receive clicks;
    // otherwise behave as a subview hit target (the container gates the rect).
    override func hitTest(_ point: NSPoint) -> NSView? {
        if expandedProvider() { return nil }
        return super.hitTest(point)
    }
}

// MARK: - Panel

/// Non-activating, but able to become key on demand so the expanded card's
/// search field can type. Showing/hovering never calls `makeKey`, so the ambient
/// pill doesn't steal focus until the card is opened.
private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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

/// Owns the single, long-lived bottom-center island panel. The SwiftUI
/// `IslandView` morphs through the capture lifecycle *and* the expanded
/// ("Spotlight card") state — all in one panel, so clicking the nub grows it into
/// the card with the same `.smooth` curve as the hover expansion.
@MainActor
final class IslandController: NSObject {
    private var panel: IslandPanel?
    private var hostingView: NSHostingView<IslandView>?
    private var trackingView: IslandTrackingView?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    private let pillViewModel: MeetingRecordingPillViewModel
    private let library: TranscriptionLibraryViewModel
    private let chrome = IslandChromeModel()
    private let expandedModel = ExpandedIslandModel()
    /// Guards click-away dismissal so the makeKey during expand can't instantly
    /// collapse the card.
    private var dismissArmed = false

    /// Stop square clicked while recording.
    var onStop: (() -> Void)?
    /// Done "Open" clicked.
    var onOpen: (() -> Void)?
    /// Expanded card: start a recording with the chosen source mode.
    var onRecord: ((MeetingAudioSourceMode) -> Void)?
    /// Expanded card: open a chosen recent transcription.
    var onSelect: ((Transcription) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenLibrary: (() -> Void)?
    var onRevealInFinder: (() -> Void)?

    init(pillViewModel: MeetingRecordingPillViewModel, library: TranscriptionLibraryViewModel, idleVisible: Bool) {
        self.pillViewModel = pillViewModel
        self.library = library
        self.chrome.idleVisible = idleVisible
        super.init()
    }

    func show() {
        if panel != nil { return }

        let bounds = NSRect(x: 0, y: 0, width: IslandLayout.panelWidth, height: IslandLayout.panelHeight)
        let container = IslandContainerView(frame: bounds)

        let view = IslandView(
            pill: pillViewModel,
            chrome: chrome,
            expandedModel: expandedModel,
            library: library,
            onRecord: { [weak self] in
                guard let self else { return }
                let mode = self.expandedModel.sourceMode
                self.collapse()
                self.onRecord?(mode)
            },
            onSelect: { [weak self] t in self?.collapse(); self?.onSelect?(t) },
            onOpenSettings: { [weak self] in self?.collapse(); self?.onOpenSettings?() },
            onOpenLibrary: { [weak self] in self?.collapse(); self?.onOpenLibrary?() },
            onRevealInFinder: { [weak self] in self?.collapse(); self?.onRevealInFinder?() },
            onCollapse: { [weak self] in self?.collapse() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]

        let tracker = IslandTrackingView(frame: bounds)
        tracker.autoresizingMask = [.width, .height]
        tracker.stateProvider = { [weak self] in self?.pillViewModel.state ?? .idle }
        tracker.idleVisibleProvider = { [weak self] in self?.chrome.idleVisible ?? true }
        tracker.expandedProvider = { [weak self] in self?.chrome.isExpanded ?? false }
        tracker.onHoverEnter = { [weak self] in self?.chrome.isHovered = true }
        tracker.onHoverExit = { [weak self] in self?.chrome.isHovered = false }
        tracker.onIdleClick = { [weak self] in self?.chrome.isHovered = false; self?.expand() }
        tracker.onStopClick = { [weak self] in self?.onStop?() }
        tracker.onBodyClick = { [weak self] in self?.onOpen?() }
        trackingView = tracker

        container.addSubview(hosting)   // display (below)
        container.addSubview(tracker)   // events (on top)
        container.activeRectProvider = { [weak tracker] in tracker?.currentActiveRect() ?? .zero }

        let panel = IslandPanel(
            contentRect: bounds,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = container
        panel.delegate = self

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - bounds.width / 2, y: frame.origin.y + 12))
        }

        panel.orderFront(nil)
        self.panel = panel
        self.hostingView = hosting
        installClickMonitors()
    }

    // MARK: Expand / collapse

    private func expand() {
        guard !chrome.isExpanded, let panel else { return }
        expandedModel.searchText = ""
        expandedModel.sourceMode = .microphoneOnly
        _ = library.loadTranscriptions()
        chrome.isExpanded = true
        dismissArmed = false
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        // Arm click-away dismissal only after the key handoff settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.dismissArmed = true
        }
    }

    private func collapse() {
        guard chrome.isExpanded else { return }
        chrome.isExpanded = false
        dismissArmed = false
    }

    // MARK: Click monitors (non-expanded states only)

    /// Catch the click at the event level rather than relying on the panel's view
    /// hit-testing (unreliable for a non-key floating panel). Only active in the
    /// non-expanded states; when expanded the panel is key and SwiftUI handles
    /// clicks directly.
    private func installClickMonitors() {
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, !self.chrome.isExpanded,
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
            guard let self, !self.chrome.isExpanded,
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
        removeClickMonitors()
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        trackingView = nil
    }

    /// Reflect the user's "show idle pill" preference. Recording-flow + expanded
    /// states are shown regardless; this only governs the idle nub/hover.
    func setIdleVisible(_ visible: Bool) {
        chrome.idleVisible = visible
    }

    /// Clear hover (e.g. when a recording starts via the Fn key, not a click).
    func resetHover() {
        chrome.isHovered = false
    }
}

// MARK: - Dismiss the expanded card on click-away

extension IslandController: NSWindowDelegate {
    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            guard self.chrome.isExpanded, self.dismissArmed else { return }
            self.collapse()
        }
    }
}

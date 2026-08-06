import AppKit
import SwiftUI

// MARK: - Panel

/// Can become key/main so the hosted SwiftUI controls (text fields, pickers in
/// Settings; search in Library) accept input.
private final class IslandOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Chrome

/// Island-matched dark backdrop for the hosted content. Flat, understated —
/// same `Color(white: 0.13)` + `.dark` scheme as the expanded island card, NOT
/// frosted glass (true vibrancy is deferred; see docs/thread-state.md). The
/// rounded corners + shadow are OS-drawn by the titled window, so this view only
/// paints the fill and forwards Esc.
private struct IslandOverlayChrome: View {
    var onClose: () -> Void
    var content: AnyView

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.13))
            .environment(\.colorScheme, .dark)
            .onExitCommand(perform: onClose)
    }
}

// MARK: - Controller

/// Hosts a full SwiftUI surface (Settings, Library) in a centered, dark,
/// island-matched floating overlay — the island's self-sufficient alternative to
/// popping the main window (Slice 4; prerequisite for retiring the main window).
///
/// Copied from `MeetingRecordingPanelController`: a titled `fullSizeContentView`
/// panel gives clean OS-drawn rounded corners + shadow (borderless + hand-drawn
/// shadow casts a visible rectangle — see docs/thread-state.md). One overlay at a
/// time; `show` swaps content if already visible. Dismiss via the close button or
/// Esc — NOT click-away, so the user can tab to another app (e.g. to copy an API
/// key) without losing the surface.
@MainActor
final class IslandOverlayController: NSObject {
    private var panel: IslandOverlayPanel?
    private var hostingView: NSHostingView<IslandOverlayChrome>?
    private var windowDelegate: Delegate?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Present `content` centered in the overlay, replacing whatever was shown.
    func show<Content: View>(
        width: CGFloat = 920,
        height: CGFloat = 680,
        @ViewBuilder content: () -> Content
    ) {
        let chrome = IslandOverlayChrome(
            onClose: { [weak self] in self?.hide() },
            content: AnyView(content())
        )

        if let hostingView {
            hostingView.rootView = chrome
            panel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = IslandOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(white: 0.13, alpha: 1)
        panel.isOpaque = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // NSPanel hides on app deactivation by default — clicking the desktop
        // would make the overlay vanish (but stay alive) and then reappear on the
        // next nub click. Keep it visible across deactivation so the user can tab
        // to another app (e.g. to copy an API key) without losing it; dismissal
        // stays explicit (close button / Esc). Click-away dismissal would be
        // fragile here because Settings' alerts/sheets steal key focus.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 880, height: 560)

        let hosting = NSHostingView(rootView: chrome)
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - width / 2,
                y: frame.midY - height / 2
            ))
        }

        let delegate = Delegate { [weak self] in self?.hide() }
        panel.delegate = delegate

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
        self.hostingView = hosting
        self.windowDelegate = delegate
    }

    func hide() {
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        windowDelegate = nil
    }

    // MARK: - Window delegate

    private final class Delegate: NSObject, NSWindowDelegate {
        private let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            onClose()
            return false
        }
    }
}

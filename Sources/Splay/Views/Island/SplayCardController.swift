import AppKit
import SplayCore
import SwiftUI

// Presentation for Splay's second surface (the card). A light **floating window**
// (not a modal): a small borderless panel, sized to the card + a margin, centred
// on screen — nothing dimmed, nothing behind it locked. It breathes in and out:
// the card grows from small → settles (a gentle overshoot) on present, and
// contracts back on dismiss. Dismiss via Esc, a click in the margin, a click
// outside the panel (resign-key), or a card button.
//
// Modelled on the island's proven borderless key-capable panel (copy the working
// panel, per the fork gotchas) rather than a fresh NSWindow subclass.

// MARK: - Panel

private final class SplayCardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Presentation state (drives the breathing in/out)

@MainActor
@Observable
final class SplayCardPresentation {
    /// false = small + faded (pre-entry / post-exit); true = settled at full size.
    var visible = false
}

// MARK: - Floating card wrapper

/// Wraps the card with the breathing entry/exit: it scales up from small and
/// settles (a soft spring overshoot), and contracts + fades on dismiss. No Y
/// translation — it grows "out of itself", centred, like the island breathing.
private struct SplayCardFloat<Content: View>: View {
    @Bindable var presentation: SplayCardPresentation
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            // Grow from small → settle; contract back on exit. Anchored centre so
            // it emerges from itself, not from an edge. The blur (harvested from
            // DynamicNotchKit) lets the card resolve *into focus* as it breathes
            // open, and soften back out on dismiss.
            .scaleEffect(presentation.visible ? 1 : 0.86, anchor: .center)
            .opacity(presentation.visible ? 1 : 0)
            .blur(radius: presentation.visible ? 0 : 10)
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.66),
                       value: presentation.visible)
            // Room for the card's (now subtle) drop shadow + a comfortable off-card
            // dismiss ring. The panel is sized to fit this padded content, so this
            // must exceed the shadow's ~33pt reach or its edge gets clipped.
            .padding(48)
            // The transparent margin around the card. A click here (the card
            // swallows its own taps) dismisses; the desktop behind the small panel
            // stays fully visible and interactive — no scrim, nothing locked.
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
            )
            // Size the panel to the card (+ margin) rather than the whole screen.
            .fixedSize()
            .onExitCommand { onDismiss() }
    }
}

// MARK: - Controller

@MainActor
final class SplayCardController: NSObject {
    private var panel: SplayCardPanel?
    private var escMonitor: Any?
    private let presentation = SplayCardPresentation()
    /// Pending panel-teardown after the exit animation; cancelled if re-presented.
    private var removalWorkItem: DispatchWorkItem?
    private var isDismissing = false
    /// Guards click-away-outside-the-app dismissal so the `makeKey` + activation
    /// during present can't immediately resign-key and close the card.
    private var dismissOnResignArmed = false

    /// Fires when the card begins dismissing (Esc / click-away / button). Used by
    /// the app to release the island's "held open" state.
    var onDismiss: (() -> Void)?

    var isPresenting: Bool { panel != nil && !isDismissing }

    /// Present a card. `make` receives a `dismiss` closure so buttons can close it,
    /// and a `resize` closure so a card whose content height changes (e.g. switching
    /// tabs in the menu card) can re-fit + re-centre the floating panel. The
    /// controller supplies the panel + the breathing animation.
    func present(make: @escaping (_ dismiss: @escaping () -> Void, _ resize: @escaping () -> Void) -> AnyView) {
        guard let screen = NSScreen.main else { return }

        // Cancel any in-flight teardown so re-presenting reuses the live panel.
        removalWorkItem?.cancel()
        removalWorkItem = nil
        isDismissing = false

        let reusedLivePanel = self.panel != nil
        let panel = self.panel ?? makePanel()
        let dismiss: () -> Void = { [weak self] in self?.dismiss(reason: "card_button_or_margin") }
        let resize: () -> Void = { [weak self] in self?.refit(animated: true) }

        // Start small + faded so the first frame is the pre-entry state; the async
        // flip to `visible = true` below then animates the breathing entry.
        presentation.visible = false
        let root = SplayCardFloat(presentation: presentation, onDismiss: dismiss) { make(dismiss, resize) }
        let hosting = NSHostingView(rootView: root)
        hosting.layoutSubtreeIfNeeded()
        // Size the panel to the card + its shadow margin, then centre it. A small
        // floating window — never a full-screen scrim that locks the screen.
        var size = hosting.fittingSize
        if size.width < 200 || size.height < 200 { size = CGSize(width: 560, height: 520) }
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        self.panel = panel
        AudioCaptureDiagnostics.append(
            "splay_card present reused=\(reusedLivePanel) size=\(Int(size.width))x\(Int(size.height)) app_active=\(NSApp.isActive)"
        )
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()
        // Arm click-away-outside-the-app dismissal only after the key handoff
        // settles, so activation doesn't instantly resign-key and close it.
        dismissOnResignArmed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.dismissOnResignArmed = true
        }
        // Trigger the breathing entry on the next runloop turn (after the pre-entry
        // frame has rendered), so `.animation(value:)` actually animates.
        DispatchQueue.main.async { [weak self] in
            self?.presentation.visible = true
        }
        // TEMP diagnostic: snapshot the panel's real state shortly after the
        // entrance settles, so an invisible-or-self-dismissed card is
        // distinguishable in the log (strip once the menu-reopen bug is closed).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if let p = self.panel {
                AudioCaptureDiagnostics.append(
                    "splay_card post_present visible=\(p.isVisible) key=\(p.isKeyWindow) frame=\(p.frame) "
                    + "entry_flag=\(self.presentation.visible) app_active=\(NSApp.isActive) "
                    + "screens=\(NSScreen.screens.map { $0.frame })"
                )
            } else {
                AudioCaptureDiagnostics.append("splay_card post_present panel=nil (torn down within 0.6s)")
            }
        }
    }

    func dismiss(reason: String = "api") {
        guard panel != nil, !isDismissing else { return }
        AudioCaptureDiagnostics.append("splay_card dismiss reason=\(reason)")
        isDismissing = true
        onDismiss?()
        removeEscMonitor()
        dismissOnResignArmed = false
        // Contract + fade out, then tear the panel down once the exit settles.
        presentation.visible = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            self.panel?.contentView = nil
            self.panel = nil
            self.isDismissing = false
        }
        removalWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34, execute: work)
    }

    /// Re-measure the hosted card and resize + re-centre the panel to fit it. Used
    /// when the card's content height changes in place (menu tab switch), so the
    /// floating window grows/shrinks to the new tab instead of clipping or leaving
    /// a gap. The SwiftUI content has a fixed width, so `fittingSize` gives the new
    /// natural height for that width.
    func refit(animated: Bool) {
        guard let panel, let content = panel.contentView else { return }
        content.invalidateIntrinsicContentSize()
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        guard size.width > 100, size.height > 100 else { return }
        // Top-anchored resize: pin the panel's current top edge and grow/shrink
        // *downward*, rather than re-centring on the screen's midY. Re-centring made
        // the top edge hop up/down on every tab switch — annoying when flipping
        // quickly between Recents/Settings/About. Horizontal centre stays where the
        // panel currently sits (tab widths match, so x rarely moves).
        let currentTop = panel.frame.maxY
        let origin = NSPoint(
            x: panel.frame.midX - size.width / 2,
            y: currentTop - size.height
        )
        let frame = NSRect(origin: origin, size: size)
        guard frame != panel.frame else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.26
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func makePanel() -> SplayCardPanel {
        let panel = SplayCardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // Above the island (which reaches `.popUpMenu` in notch mode) so the card
        // floats over every Splay surface. Joins all Spaces like the island.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }  // Escape
            self.dismiss(reason: "esc")
            return nil
        }
    }

    private func removeEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }
}

// MARK: - Dismiss on click-away outside the app

extension SplayCardController: NSWindowDelegate {
    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            guard self.dismissOnResignArmed else { return }
            self.dismiss(reason: "resign_key")
        }
    }
}

import AppKit
import SplayViewModels

/// Two-surface design (island + card) has no ordinary main window. What remains
/// window-level is the app's *activation policy* (menu-bar-only vs. Dock-visible)
/// and the Dock menu — both routed to the card surfaces.
@MainActor
final class AppActivationCoordinator: NSObject {
    private let settingsViewModel: SettingsViewModel
    private let onOpenRecent: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(
        settingsViewModel: SettingsViewModel,
        onOpenRecent: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.settingsViewModel = settingsViewModel
        self.onOpenRecent = onOpenRecent
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    func applyActivationPolicyFromSettings() {
        let mode: NSApplication.ActivationPolicy = settingsViewModel.menuBarOnlyMode ? .accessory : .regular
        NSApp.setActivationPolicy(mode)
    }

    func makeDockMenu() -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Splay", action: #selector(dockOpenRecent), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(dockOpenSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Splay", action: #selector(dockQuit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func dockOpenRecent() {
        onOpenRecent()
    }

    @objc private func dockOpenSettings() {
        onOpenSettings()
    }

    @objc private func dockQuit() {
        onQuit()
    }
}

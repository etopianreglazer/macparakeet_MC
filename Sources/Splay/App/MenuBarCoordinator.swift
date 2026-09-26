import AppKit
import Sparkle
import UniformTypeIdentifiers
import SplayCore
import SplayViewModels

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate {
    private let updaterController: SPUStandardUpdaterController
    private let transcriptionViewModel: TranscriptionViewModel
    private let environmentProvider: () -> AppEnvironment?
    private let hotkeyMenuTitleProvider: () -> String
    private let meetingHotkeyTriggerProvider: () -> HotkeyTrigger
    private let fileTranscriptionHotkeyTriggerProvider: () -> HotkeyTrigger
    private let meetingRecordingActiveProvider: () -> Bool
    private let dictationCaptureActiveProvider: () -> Bool
    private let onOpenSettings: () -> Void
    /// Menu-bar "Recordings" presents the recents card (the second surface).
    private let onOpenRecent: () -> Void
    private let onStartDictation: () -> Void
    private let onToggleMeetingRecording: () -> Void
    private let onQuit: () -> Void
    private let onShowAboutPanel: () -> Void

    private var statusItem: NSStatusItem?
    private var startDictationMenuItem: NSMenuItem?
    private var pasteLastMenuItem: NSMenuItem?
    private var recentDictationsMenuItem: NSMenuItem?
    private var recordMeetingMenuItems: [NSMenuItem] = []
    private var transcribeFileMenuItems: [NSMenuItem] = []
    private var hotkeyMenuItem: NSMenuItem?

    init(
        updaterController: SPUStandardUpdaterController,
        transcriptionViewModel: TranscriptionViewModel,
        environmentProvider: @escaping () -> AppEnvironment?,
        hotkeyMenuTitleProvider: @escaping () -> String,
        meetingHotkeyTriggerProvider: @escaping () -> HotkeyTrigger,
        fileTranscriptionHotkeyTriggerProvider: @escaping () -> HotkeyTrigger,
        meetingRecordingActiveProvider: @escaping () -> Bool,
        dictationCaptureActiveProvider: @escaping () -> Bool,
        onOpenSettings: @escaping () -> Void,
        onOpenRecent: @escaping () -> Void,
        onStartDictation: @escaping () -> Void,
        onToggleMeetingRecording: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onShowAboutPanel: @escaping () -> Void
    ) {
        self.updaterController = updaterController
        self.transcriptionViewModel = transcriptionViewModel
        self.environmentProvider = environmentProvider
        self.hotkeyMenuTitleProvider = hotkeyMenuTitleProvider
        self.meetingHotkeyTriggerProvider = meetingHotkeyTriggerProvider
        self.fileTranscriptionHotkeyTriggerProvider = fileTranscriptionHotkeyTriggerProvider
        self.meetingRecordingActiveProvider = meetingRecordingActiveProvider
        self.dictationCaptureActiveProvider = dictationCaptureActiveProvider
        self.onOpenSettings = onOpenSettings
        self.onOpenRecent = onOpenRecent
        self.onStartDictation = onStartDictation
        self.onToggleMeetingRecording = onToggleMeetingRecording
        self.onQuit = onQuit
        self.onShowAboutPanel = onShowAboutPanel
    }

    private static var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Splay"
    }

    private func makeMenuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = Self.appDisplayName

        let aboutItem = NSMenuItem(
            title: "About \(appName)",
            action: #selector(showAboutPanel),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(showSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = updaterController
        appMenu.addItem(checkForUpdatesItem)
        appMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(
            title: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)
        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(appName)",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let captureMenuItem = NSMenuItem()
        let captureMenu = NSMenu(title: "Capture")
        captureMenu.autoenablesItems = false
        captureMenu.delegate = self
        let startDictationItem = makeMenuItem(
            title: "Start Dictation",
            action: #selector(startDictationFromMenu),
            key: ""
        )
        captureMenu.addItem(startDictationItem)
        startDictationMenuItem = startDictationItem
        captureMenu.addItem(NSMenuItem.separator())
        let fileTranscriptionItem = makeMenuItem(
            title: "Transcribe File...",
            action: #selector(transcribeFileFromMenu),
            key: ""
        )
        applyChordShortcut(fileTranscriptionHotkeyTriggerProvider(), to: fileTranscriptionItem)
        transcribeFileMenuItems.append(fileTranscriptionItem)
        captureMenu.addItem(fileTranscriptionItem)
        if AppFeatures.meetingRecordingEnabled {
            let recordMeetingItem = makeMenuItem(
                title: "Start Recording",
                action: #selector(toggleMeetingRecordingFromMenu),
                key: ""
            )
            applyChordShortcut(meetingHotkeyTriggerProvider(), to: recordMeetingItem)
            captureMenu.addItem(recordMeetingItem)
            recordMeetingMenuItems.append(recordMeetingItem)
        }
        captureMenuItem.submenu = captureMenu
        mainMenu.addItem(captureMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        ))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(makeMenuItem(title: "\(appName) Help", action: #selector(openHelp), key: ""))
        helpMenu.addItem(makeMenuItem(title: "View on GitHub", action: #selector(openGitHub), key: ""))
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    /// AppKit's per-item defaults key for where the icon sits (points from the
    /// screen's right edge). "Item-0" is the default autosave name of our one item.
    static let statusItemPositionKey = "NSStatusItem Preferred Position Item-0"

    /// On a notched screen a crowded menu bar can leave the icon remembered
    /// *behind the camera*, where macOS draws it offscreen — Splay then has no
    /// visible menu bar icon at all (owner, 2026-09-26). Returns a position right
    /// of the notch when the remembered one is hidden (or absent); nil keeps it.
    static func correctedStatusItemPosition(stored: Double?, rightOfNotchWidth: CGFloat?) -> Double? {
        guard let rightOfNotchWidth, rightOfNotchWidth > 0 else { return nil }
        let visibleLimit = Double(rightOfNotchWidth) - 40   // an icon's width inside the right area
        if let stored, stored > 0, stored <= visibleLimit { return nil }
        return (Double(rightOfNotchWidth) / 2).rounded()
    }

    private func placeStatusItemRightOfNotch() {
        // The menu bar lives on the primary screen (screens[0]).
        guard let screen = NSScreen.screens.first else { return }
        let rightArea = screen.auxiliaryTopRightArea?.width
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: Self.statusItemPositionKey) as? Double
        guard let position = Self.correctedStatusItemPosition(stored: stored, rightOfNotchWidth: rightArea) else { return }
        defaults.set(position, forKey: Self.statusItemPositionKey)
        AudioCaptureDiagnostics.append(
            "splay_status_item moved_right_of_notch stored=\(stored.map { String($0) } ?? "nil") position=\(position)"
        )
    }

    func setupMenuBar() {
        placeStatusItemRightOfNotch()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let statusItem,
              let button = statusItem.button else { return }

        button.image = BreathWaveIcon.menuBarIcon(pointSize: 18)

        let dropView = MenuBarDropView(frame: button.bounds)
        dropView.onDrop = { [weak self] urls in
            Task { @MainActor in
                self?.handleDroppedFiles(urls)
            }
        }
        button.addSubview(dropView)

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let appName = Self.appDisplayName

        // Splay's menu: the card, dictation recall, capture, then app chrome.
        // Each item carries an SF Symbol so the menu scans at a glance.
        let recordingsItem = NSMenuItem(
            title: "Recordings",
            action: #selector(openRecentCard),
            keyEquivalent: "o"
        )
        recordingsItem.target = self
        recordingsItem.image = Self.symbol("waveform")
        menu.addItem(recordingsItem)

        menu.addItem(NSMenuItem.separator())

        let pasteItem = NSMenuItem(
            title: "Paste Last Dictation",
            action: #selector(pasteLastDictation),
            keyEquivalent: ""
        )
        pasteItem.isEnabled = false
        pasteItem.target = self
        pasteItem.image = Self.symbol("doc.on.clipboard")
        menu.addItem(pasteItem)
        pasteLastMenuItem = pasteItem

        let recentItem = NSMenuItem(
            title: "Recent Dictations",
            action: nil,
            keyEquivalent: ""
        )
        recentItem.submenu = NSMenu()
        recentItem.isHidden = true
        recentItem.image = Self.symbol("text.bubble")
        menu.addItem(recentItem)
        recentDictationsMenuItem = recentItem

        menu.addItem(NSMenuItem.separator())

        if AppFeatures.meetingRecordingEnabled {
            let recordMeetingItem = NSMenuItem(
                title: "Start Recording",
                action: #selector(toggleMeetingRecordingFromMenu),
                keyEquivalent: ""
            )
            recordMeetingItem.target = self
            recordMeetingItem.image = Self.symbol("record.circle")
            applyChordShortcut(meetingHotkeyTriggerProvider(), to: recordMeetingItem)
            menu.addItem(recordMeetingItem)
            recordMeetingMenuItems.append(recordMeetingItem)
        }

        let transcribeFileItem = NSMenuItem(
            title: "Transcribe File...",
            action: #selector(transcribeFileFromMenu),
            keyEquivalent: ""
        )
        transcribeFileItem.target = self
        transcribeFileItem.image = Self.symbol("doc.badge.plus")
        applyChordShortcut(fileTranscriptionHotkeyTriggerProvider(), to: transcribeFileItem)
        menu.addItem(transcribeFileItem)
        transcribeFileMenuItems.append(transcribeFileItem)

        menu.addItem(NSMenuItem.separator())

        let hotkeyItem = NSMenuItem(
            title: hotkeyMenuTitleProvider(),
            action: nil,
            keyEquivalent: ""
        )
        hotkeyItem.isEnabled = false
        hotkeyItem.image = Self.symbol("keyboard")
        menu.addItem(hotkeyItem)
        hotkeyMenuItem = hotkeyItem

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(showSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = Self.symbol("gearshape")
        menu.addItem(settingsItem)

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = updaterController
        checkForUpdatesItem.image = Self.symbol("arrow.triangle.2.circlepath")
        menu.addItem(checkForUpdatesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(appName)",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = Self.symbol("power")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// An SF Symbol sized for a menu item (template, so it follows the menu's
    /// text colour and highlight).
    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    func refreshHotkeyTitle() {
        hotkeyMenuItem?.title = hotkeyMenuTitleProvider()
    }

    func refreshMeetingHotkeyShortcut() {
        recordMeetingMenuItems.forEach { applyChordShortcut(meetingHotkeyTriggerProvider(), to: $0) }
    }

    func refreshTranscriptionHotkeyShortcuts() {
        transcribeFileMenuItems.forEach { applyChordShortcut(fileTranscriptionHotkeyTriggerProvider(), to: $0) }
    }

    /// Entry point for the file-transcription global hotkey. Shares its
    /// implementation with the menu-bar item so both behave identically.
    func invokeTranscribeFileFlow() {
        transcribeFileFlow()
    }

    func updateIcon(state: BreathWaveIcon.MenuBarState) {
        statusItem?.button?.image = BreathWaveIcon.menuBarIcon(pointSize: 18, state: state)
    }

    @objc private func showAboutPanel() {
        onShowAboutPanel()
    }

    /// Menu-bar "Recordings" → the recents card.
    @objc private func openRecentCard() {
        onOpenRecent()
    }

    // Named to avoid matching the macOS 14+ `openSettings:` system action,
    // which would trigger automatic gear SF Symbol decoration on the menu item.
    @objc private func showSettingsWindow() {
        onOpenSettings()
    }

    @objc private func startDictationFromMenu() {
        onStartDictation()
    }

    @objc private func openHelp() {
        openExternalURL("https://github.com/etopianreglazer/splay")
    }

    @objc private func openGitHub() {
        openExternalURL("https://github.com/etopianreglazer/splay")
    }

    @objc private func quitApp() {
        onQuit()
    }

    private func openExternalURL(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func pasteLastDictation() {
        guard let env = environmentProvider() else { return }
        Task {
            guard let dictation = (try? env.dictationRepo.fetchAll(limit: 1))?.first else { return }
            // displayText honors the per-row "Undo AI edit" override.
            let text = dictation.displayText
            await pasteFromMenu(text: text, clipboardService: env.clipboardService)
        }
    }

    @objc private func pasteRecentDictation(_ sender: NSMenuItem) {
        guard let env = environmentProvider(),
              let id = sender.representedObject as? UUID else { return }
        Task {
            guard let dictation = try? env.dictationRepo.fetch(id: id) else { return }
            let text = dictation.displayText
            await pasteFromMenu(text: text, clipboardService: env.clipboardService)
        }
    }

    @objc private func transcribeFileFromMenu() {
        transcribeFileFlow()
    }

    private func transcribeFileFlow() {
        guard environmentProvider() != nil else { return }

        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose one or more audio/video files, or a folder, to transcribe."
        panel.allowedContentTypes = AudioFileConverter.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }

        if panel.runModal() == .OK, !panel.urls.isEmpty {
            transcriptionViewModel.transcribeFiles(urls: panel.urls)
            SoundManager.shared.play(.fileDropped)
        }
    }

    @objc private func toggleMeetingRecordingFromMenu() {
        onToggleMeetingRecording()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let environmentReady = environmentProvider() != nil
        startDictationMenuItem?.isEnabled = environmentReady && !dictationCaptureActiveProvider()
        transcribeFileMenuItems.forEach { $0.isEnabled = environmentReady }
        recordMeetingMenuItems.forEach {
            $0.isEnabled = environmentReady
            let active = meetingRecordingActiveProvider()
            $0.title = active ? "Stop Recording" : "Start Recording"
            $0.image = Self.symbol(active ? "stop.circle" : "record.circle")
        }

        guard let env = environmentProvider() else {
            pasteLastMenuItem?.isEnabled = false
            recentDictationsMenuItem?.isHidden = true
            return
        }

        let dictations = (try? env.dictationRepo.fetchAll(limit: 5)) ?? []
        pasteLastMenuItem?.isEnabled = !dictations.isEmpty
        rebuildRecentDictationsSubmenu(with: dictations)
    }

    private func handleDroppedFiles(_ urls: [URL]) {
        // Route through the guarded batch entry point: it expands folders,
        // chooses single vs. batch, and no-ops while a transcription/batch is
        // already running (so an icon drop can't corrupt an active batch).
        if transcriptionViewModel.transcribeFiles(urls: urls) {
            SoundManager.shared.play(.fileDropped)
        }
    }

    /// Resign menu-bar focus, wait for the target app to regain focus, then paste.
    private func pasteFromMenu(text: String, clipboardService: ClipboardServiceProtocol) async {
        NSApp.deactivate()
        try? await Task.sleep(for: .milliseconds(200))
        do {
            try await clipboardService.pasteText(text)
        } catch {
            await clipboardService.copyToClipboard(text)
        }
    }

    private func rebuildRecentDictationsSubmenu(with dictations: [Dictation]) {
        guard let recentItem = recentDictationsMenuItem else { return }
        recentItem.isHidden = dictations.isEmpty

        let submenu = NSMenu()
        for dictation in dictations {
            let item = NSMenuItem(
                title: MenuPreviewFormatter.dictationTitle(text: dictation.displayText),
                action: #selector(pasteRecentDictation(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = dictation.id
            submenu.addItem(item)
        }
        recentItem.submenu = submenu
    }

    /// Apply a chord trigger's visual shortcut to a menu item. Non-chord or
    /// disabled triggers clear the key equivalent.
    ///
    /// Note: this only paints the visual hint. The actual hotkey is handled by
    /// `GlobalShortcutManager` in the app layer, so keyEquivalent matches
    /// aren't required for the shortcut to fire while the menu is closed.
    private func applyChordShortcut(_ trigger: HotkeyTrigger, to item: NSMenuItem) {
        guard trigger.kind == .chord, let code = trigger.keyCode else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }

        let keyName = KeyCodeNames.name(for: code).shortSymbol
        item.keyEquivalent = keyName.lowercased()

        var mask: NSEvent.ModifierFlags = []
        for modifier in trigger.chordModifiers ?? [] {
            switch modifier {
            case "command": mask.insert(.command)
            case "shift": mask.insert(.shift)
            case "control": mask.insert(.control)
            case "option": mask.insert(.option)
            default: break
            }
        }
        item.keyEquivalentModifierMask = mask
    }
}

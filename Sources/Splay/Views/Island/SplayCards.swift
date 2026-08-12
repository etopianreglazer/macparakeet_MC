import SwiftUI
import SplayCore
import SplayViewModels

// The menu card — Splay's second surface as a small **tabbed navigator**. One
// floating card with an icon tab strip at the top (Recents · Settings · About);
// picking a tab swaps the body in place and re-fits the panel (via `resize`), so
// you can move between recents and settings without dismissing. This generalises
// the old single-purpose cards into one surface and adds an About tab carrying the
// licence, version, and the Sparkle updater.
//
// The reusable shell pieces (palette, buttons, list/toggle/accent blocks) live in
// `SplayCard.swift`; this file owns the tabbed container that assembles them.

// MARK: - Tabs

enum SplayCardTab: String, CaseIterable, Identifiable {
    case recents, settings, about
    var id: String { rawValue }

    /// SF Symbol shown in the tab tile.
    var glyph: String {
        switch self {
        case .recents:  return "waveform"
        case .settings: return "gearshape.fill"
        case .about:    return "info"
        }
    }

    var title: String {
        switch self {
        case .recents:  return "Recent recordings"
        case .settings: return "Settings"
        case .about:    return "About Splay"
        }
    }

    var message: String {
        switch self {
        case .recents:  return "The last five — Splay keeps no library, these are just the newest files."
        case .settings: return "A few switches. Everything else Splay has already decided for you."
        case .about:    return "A fast, private voice recorder that runs entirely on your Mac."
        }
    }

    var accessibilityLabel: String { title }
}

// MARK: - The card

struct SplayMenuCard: View {
    // Recents
    let rows: [SplayRecordingRow]
    let totalCount: Int
    let folderDisplayPath: String
    let onOpenFolder: () -> Void
    let onCopy: (SplayRecordingRow) -> Void
    // Settings (plain reference; bindings are built by hand so no custom-init dance)
    let settings: SettingsViewModel
    // About
    let appVersion: String
    let onCheckForUpdates: () -> Void
    let onOpenRepo: () -> Void
    // Shell
    let onQuit: () -> Void
    let dismiss: () -> Void
    let resize: () -> Void

    @State private var tab: SplayCardTab
    @AppStorage("splay.playSoundOnStart") private var playSoundOnStart = false

    init(
        tab: SplayCardTab,
        rows: [SplayRecordingRow],
        totalCount: Int,
        folderDisplayPath: String,
        onOpenFolder: @escaping () -> Void,
        onCopy: @escaping (SplayRecordingRow) -> Void,
        settings: SettingsViewModel,
        appVersion: String,
        onCheckForUpdates: @escaping () -> Void,
        onOpenRepo: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        dismiss: @escaping () -> Void,
        resize: @escaping () -> Void
    ) {
        _tab = State(initialValue: tab)
        self.rows = rows
        self.totalCount = totalCount
        self.folderDisplayPath = folderDisplayPath
        self.onOpenFolder = onOpenFolder
        self.onCopy = onCopy
        self.settings = settings
        self.appVersion = appVersion
        self.onCheckForUpdates = onCheckForUpdates
        self.onOpenRepo = onOpenRepo
        self.onQuit = onQuit
        self.dismiss = dismiss
        self.resize = resize
    }

    private var recordSystemAudio: Binding<Bool> {
        Binding(
            get: { settings.meetingAudioSourceMode == .microphoneAndSystem },
            set: { settings.meetingAudioSourceMode = $0 ? .microphoneAndSystem : .microphoneOnly }
        )
    }
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 })
    }

    var body: some View {
        // Reuse the shared card shell (`SplayCardView`) — the tab strip stands in
        // for the glyph-tile header, and each tab supplies its own title / message /
        // body / buttons via the chrome. This keeps one source of truth for the
        // card surface, padding, and shadow rather than forking it.
        SplayCardView(
            chrome: chrome,
            header: AnyView(SplayTabStrip(selection: $tab)),
            onPrimary: primaryAction,
            onSecondary: secondaryAction,
            bodyBlock: { bodyBlock }
        )
        // Content height changes per tab → re-fit the floating panel once SwiftUI
        // has committed the new tab's layout (a bare next-runloop hop can read the
        // pre-swap size, so wait a beat before measuring `fittingSize`).
        .onChange(of: tab) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { resize() }
        }
    }

    // MARK: Per-tab chrome + actions

    private var chrome: SplayCardChrome {
        switch tab {
        case .recents:
            return SplayCardChrome(glyph: "", title: tab.title, message: tab.message,
                                   width: 460, primaryLabel: "Open folder", secondaryLabel: "Close")
        case .settings:
            return SplayCardChrome(glyph: "", title: tab.title, message: tab.message,
                                   width: 460, primaryLabel: "Done", secondaryLabel: "Quit Splay")
        case .about:
            return SplayCardChrome(glyph: "", title: tab.title, message: tab.message,
                                   width: 460, primaryLabel: "Check for Updates", secondaryLabel: "Close")
        }
    }

    private var primaryAction: () -> Void {
        switch tab {
        case .recents: return { onOpenFolder(); dismiss() }
        case .settings: return dismiss
        case .about: return { onCheckForUpdates(); dismiss() }
        }
    }

    private var secondaryAction: () -> Void {
        switch tab {
        case .recents: return dismiss
        case .settings: return onQuit
        case .about: return dismiss
        }
    }

    // MARK: Body per tab

    private var bodyBlock: AnyView {
        switch tab {
        case .recents:
            if rows.isEmpty {
                return AnyView(
                    Text("Nothing recorded yet. Hold your shortcut and start talking — the file appears here when it goes quiet.")
                        .font(.system(size: 12))
                        .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.5))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                )
            }
            let noun = totalCount == 1 ? "recording" : "recordings"
            return AnyView(
                SplayRecordingList(
                    rows: rows,
                    footer: "\(folderDisplayPath) · \(totalCount) \(noun) · everything older is just files",
                    onCopy: onCopy
                )
            )
        case .settings:
            return AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    SplayToggleList(toggles: [
                        SplayToggle(label: "Record system audio too", isOn: recordSystemAudio),
                        SplayToggle(label: "Launch at login", isOn: launchAtLogin),
                        SplayToggle(label: "Play a sound when it starts", isOn: $playSoundOnStart)
                    ])
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Accent")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.5))
                        SplayAccentPicker()
                    }
                }
            )
        case .about:
            return AnyView(SplayAboutBlock(appVersion: appVersion, onOpenRepo: onOpenRepo))
        }
    }
}

// MARK: - Tab strip

/// The icon tab row that replaces the single glyph tile. Three tiles; the active
/// one wears the brand accent (echoing the design's coloured tile), the others sit
/// quiet. Picking one switches the card body in place.
private struct SplayTabStrip: View {
    @Binding var selection: SplayCardTab

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SplayCardTab.allCases) { tab in
                SplayTabTile(tab: tab, selected: tab == selection) {
                    guard tab != selection else { return }
                    withAnimation(.easeInOut(duration: 0.18)) { selection = tab }
                }
            }
        }
    }
}

private struct SplayTabTile: View {
    let tab: SplayCardTab
    let selected: Bool
    let onPick: () -> Void
    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(selected ? SplayCardPalette.brand : SplayCardPalette.rgba(36, 31, 56, hovering ? 0.09 : 0.05))
            .frame(width: 52, height: 44)
            .overlay(
                Image(systemName: tab.glyph)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : SplayCardPalette.rgba(36, 31, 56, 0.55))
            )
            .brightness(selected && hovering ? 0.06 : 0)
            .scaleEffect(hovering && !selected ? 1.04 : 1)
            .shadow(color: selected ? SplayCardPalette.brand.opacity(0.35) : .clear, radius: selected ? 7 : 0, y: 2)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .onTapGesture(perform: onPick)
            .onHover { hovering = $0; SplayHoverCursor.apply($0) }
            .help(tab.title)
            .accessibilityLabel(tab.accessibilityLabel)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - About block

/// The About tab body: the app's licence (rights), version, and a link to the
/// source. The updater lives in the tab's primary button.
private struct SplayAboutBlock: View {
    let appVersion: String
    let onOpenRepo: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            infoRow(label: "Version", value: appVersion.isEmpty ? "dev build" : appVersion)
            infoRow(label: "Licence", value: "GPL-3.0 · free & open source")
            SplayRepoRow(onOpenRepo: onOpenRepo)

            Text("Splay is a personal fork of MacParakeet. Free and open source under the GPL-3.0 — you may use, study, share, and modify it.")
                .font(.system(size: 11))
                .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(SplayCardPalette.ink)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.6))
        }
        .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(SplayCardPalette.rgba(36, 31, 56, 0.035))
        )
    }
}

private struct SplayRepoRow: View {
    let onOpenRepo: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Text("View source on GitHub")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(SplayCardPalette.brand)
            Spacer(minLength: 12)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SplayCardPalette.brand)
        }
        .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(SplayCardPalette.brandTint(hovering ? 0.14 : 0.09))
        )
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenRepo)
        .onHover { hovering = $0; SplayHoverCursor.apply($0) }
        .accessibilityLabel("View source on GitHub")
        .accessibilityAddTraits(.isButton)
    }
}

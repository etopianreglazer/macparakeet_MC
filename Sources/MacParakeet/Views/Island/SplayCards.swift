import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

// The concrete cards wired for Phase 3: Recent recordings and Settings (handoff
// §"Recent & settings"). The reusable shell + body blocks live in `SplayCard.swift`;
// this file assembles the two that are reachable today from real view models.
// First-run and alert cards (which reuse the same shell + the destination /
// permission / key-cap blocks) are wired in a later phase.

enum SplayCards {

    // MARK: Recent recordings

    /// The last five recordings (newest files), with an "Open folder" handoff.
    static func recent(
        rows: [SplayRecordingRow],
        totalCount: Int,
        folderDisplayPath: String,
        onOpenFolder: @escaping () -> Void,
        onCopy: @escaping (SplayRecordingRow) -> Void,
        dismiss: @escaping () -> Void
    ) -> AnyView {
        let noun = totalCount == 1 ? "recording" : "recordings"
        let footer = "\(folderDisplayPath) · \(totalCount) \(noun) · everything older is just files"
        let chrome = SplayCardChrome(
            glyph: "▤",
            title: "Recent recordings",
            message: "The last five. Splay keeps no library — these are simply the newest files in \(folderDisplayPath).",
            width: 480,
            primaryLabel: "Open folder",
            secondaryLabel: "Close"
        )
        return AnyView(
            SplayCardView(
                chrome: chrome,
                onPrimary: { onOpenFolder(); dismiss() },
                onSecondary: dismiss
            ) {
                if rows.isEmpty {
                    SplayEmptyRecordings()
                } else {
                    SplayRecordingList(rows: rows, footer: footer, onCopy: onCopy)
                }
            }
        )
    }

    // MARK: Settings

    /// Three switches and a quit — the entire settings surface.
    static func settings(
        settings: SettingsViewModel,
        onDone: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> AnyView {
        AnyView(SplaySettingsCard(settings: settings, onDone: onDone, onQuit: onQuit))
    }
}

// MARK: - Empty recent-recordings block

private struct SplayEmptyRecordings: View {
    var body: some View {
        Text("Nothing recorded yet. Hold your shortcut and start talking — the file appears here when it goes quiet.")
            .font(.system(size: 12))
            .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.5))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
    }
}

// MARK: - Settings card (live-bound to SettingsViewModel)

private struct SplaySettingsCard: View {
    @Bindable var settings: SettingsViewModel
    let onDone: () -> Void
    let onQuit: () -> Void

    /// No dedicated backing store yet (Phase 4 wires the start sound). Persist the
    /// user's choice now so the switch is honest across launches.
    @AppStorage("splay.playSoundOnStart") private var playSoundOnStart = false

    private var recordSystemAudio: Binding<Bool> {
        Binding(
            get: { settings.meetingAudioSourceMode == .microphoneAndSystem },
            set: { settings.meetingAudioSourceMode = $0 ? .microphoneAndSystem : .microphoneOnly }
        )
    }

    var body: some View {
        let chrome = SplayCardChrome(
            glyph: "◎",
            title: "Settings",
            message: "Three switches. Everything else Splay has already decided for you.",
            width: 420,
            primaryLabel: "Done",
            secondaryLabel: "Quit Splay"
        )
        SplayCardView(chrome: chrome, onPrimary: onDone, onSecondary: onQuit) {
            VStack(alignment: .leading, spacing: 14) {
                SplayToggleList(
                    toggles: [
                        SplayToggle(label: "Record system audio too", isOn: recordSystemAudio),
                        SplayToggle(label: "Launch at login", isOn: $settings.launchAtLogin),
                        SplayToggle(label: "Play a sound when it starts", isOn: $playSoundOnStart)
                    ]
                )
                VStack(alignment: .leading, spacing: 9) {
                    Text("Accent")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.5))
                    SplayAccentPicker()
                }
            }
        }
    }
}

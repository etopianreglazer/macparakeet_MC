import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

// MARK: - Model

/// Local state for the expanded island. Search is kept here (not on the shared
/// `TranscriptionLibraryViewModel`) so typing in the island doesn't disturb the
/// main Library tab's filter.
@MainActor @Observable
final class ExpandedIslandModel {
    var searchText = ""
    var sourceMode: MeetingAudioSourceMode = .microphoneOnly
    init() {}
}

// MARK: - Expanded island

/// The Spotlight-style surface shown when the island is expanded: search +
/// Record + source toggle + recents + chips. Rendered as the `.expanded` morph
/// state of `IslandView`, which provides the card background, the key-window
/// focus handoff, and routes these callbacks.
struct ExpandedIslandView: View {
    @Bindable var model: ExpandedIslandModel
    @Bindable var library: TranscriptionLibraryViewModel
    var searchFocused: FocusState<Bool>.Binding

    var onRecord: () -> Void
    var onSelect: (Transcription) -> Void
    var onOpenSettings: () -> Void
    var onOpenLibrary: () -> Void
    var onRevealInFinder: () -> Void
    var onEscape: () -> Void

    private var recents: [Transcription] {
        let all = library.groupedTranscriptions.flatMap(\.items)
        let q = model.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? all : all.filter { t in
            (t.derivedTitle ?? t.fileName).lowercased().contains(q) || t.fileName.lowercased().contains(q)
        }
        return Array(filtered.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchRow
            actionRow
            if !recents.isEmpty {
                Divider().overlay(Color.white.opacity(0.08))
                recentsList
            }
            Spacer(minLength: 0)
            chipsRow
        }
        .padding(16)
        // Fill the fixed card the island morphs to (background/shadow come from
        // the morphing IslandView shape — this is now a state of the same pill).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onExitCommand(perform: onEscape)
    }

    // MARK: Search

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            TextField("", text: $model.searchText, prompt: Text("Search transcripts, or just hit record…").foregroundColor(.white.opacity(0.45)))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused(searchFocused)
                .onSubmit {
                    if let first = recents.first { onSelect(first) }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: Record + source toggle

    private var actionRow: some View {
        HStack(spacing: 9) {
            Button(action: onRecord) {
                HStack(spacing: 8) {
                    Circle().fill(.white).frame(width: 9, height: 9)
                    Text("Record")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(IslandPalette.accent)
                )
            }
            .buttonStyle(.plain)

            sourceToggle
        }
    }

    private var sourceToggle: some View {
        HStack(spacing: 0) {
            segment("Mic", mode: .microphoneOnly)
            segment("Mic + System", mode: .microphoneAndSystem)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    private func segment(_ title: String, mode: MeetingAudioSourceMode) -> some View {
        let on = model.sourceMode == mode
        return Text(title)
            .font(.system(size: 11.5, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? .white : .white.opacity(0.6))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? Color.white.opacity(0.16) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { model.sourceMode = mode }
    }

    // MARK: Recents

    private var recentsList: some View {
        VStack(spacing: 1) {
            ForEach(recents) { t in
                Button { onSelect(t) } label: {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(dotColor(for: t.sourceType))
                            .frame(width: 7, height: 7)
                        Text(t.derivedTitle ?? t.fileName)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(durationLabel(t.durationMs))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RecentRowButtonStyle())
            }
        }
    }

    // MARK: Chips

    private var chipsRow: some View {
        HStack(spacing: 8) {
            chip("gearshape", "Settings", action: onOpenSettings)
            chip("square.grid.2x2", "Library", action: onOpenLibrary)
            chip("folder", "Reveal in Finder", action: onRevealInFinder)
        }
    }

    private func chip(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 11.5))
            }
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func dotColor(for source: Transcription.SourceType) -> Color {
        switch source {
        case .meeting: return IslandPalette.ready
        case .youtube: return Color(red: 0.44, green: 0.71, blue: 0.88)
        case .file:    return Color(red: 0.78, green: 0.61, blue: 0.88)
        }
    }

    private func durationLabel(_ ms: Int?) -> String {
        guard let ms, ms > 0 else { return "" }
        let totalMinutes = ms / 60_000
        if totalMinutes < 60 { return "\(max(1, totalMinutes)) min" }
        return String(format: "%dh %02d", totalMinutes / 60, totalMinutes % 60)
    }
}

private struct RecentRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0))
            )
    }
}

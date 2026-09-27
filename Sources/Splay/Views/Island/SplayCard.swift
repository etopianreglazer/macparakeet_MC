import AppKit
import SwiftUI
import SplayCore

// The card is Splay's *second* surface (design handoff:
// docs/design/splay-island-handoff/README.md, "Screen 2 — The card"). One
// centred modal over a dimmed scrim, reused for every message the app delivers:
// first run, permissions, alerts, recent recordings, settings. The island stays
// an indicator; anything that needs words or controls is a card.
//
// These colours/sizes are the design's final intent (fixed sRGB, not adaptive
// tokens): the card is always the light modal, so it does not follow the app's
// light/dark appearance. This file owns the reusable chrome + the five body
// blocks (destination list, permission row, key caps, recording list, toggle
// list); presentation (the scrim panel, Esc/click-away) lives in
// `SplayCardController`.

// MARK: - Palette (handoff §Design tokens)

enum SplayCardPalette {
    static let ink = rgb(0x24, 0x1F, 0x38)          // #241f38
    static let secondaryInk = rgb(0x2C, 0x23, 0x50) // #2c2350
    static let danger = rgb(0xB3, 0x35, 0x2F)       // #B3352F (card danger)
    static let warning = rgb(0xF4, 0xBE, 0x59)      // #F4BE59

    static let surface = Color(.sRGB, red: 252 / 255, green: 251 / 255, blue: 255 / 255, opacity: 0.98)
    static let scrim = Color(.sRGB, red: 36 / 255, green: 31 / 255, blue: 56 / 255, opacity: 0.20)

    /// The brand colour — themed by the user's accent choice (`SplayTheme`).
    @MainActor static var brand: Color { SplayTheme.shared.accent.brand }
    /// A low-alpha wash of the brand (selected rows, first-row highlight, dots).
    @MainActor static func brandTint(_ alpha: Double) -> Color { brand.opacity(alpha) }

    /// The card's tint (glyph tile, permission row) — brand by default, danger when flagged.
    @MainActor static func tileFill(danger: Bool) -> Color {
        danger ? rgba(179, 53, 47, 0.10) : brand.opacity(0.11)
    }
    @MainActor static func tint(danger: Bool) -> Color { danger ? danger_ : brand }
    private static let danger_ = rgb(0xB3, 0x35, 0x2F)

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
    static func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Double) -> Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: a)
    }
}

// MARK: - Card chrome spec

/// The fixed shell of a card: glyph tile, title, body, one or two buttons, and
/// optional progress dots. The body *block* (the five reusable content blocks)
/// is supplied separately as a view, so the same shell drives every card.
struct SplayCardChrome {
    var glyph: String
    var title: String
    var message: String
    var width: CGFloat
    var danger: Bool = false
    var primaryLabel: String
    /// When nil, the button row shows a single full-width primary button.
    var secondaryLabel: String? = nil
    /// First-run progress dots: (activeIndex, count). Nil hides the row.
    var dots: (index: Int, count: Int)? = nil
}

// MARK: - The card

/// One card: scrim-agnostic (the controller supplies the scrim). Generic over the
/// optional body block so callers pass any of the five blocks — or `EmptyView`.
struct SplayCardView<BodyBlock: View>: View {
    let chrome: SplayCardChrome
    /// Optional replacement for the glyph tile header (e.g. the menu card's tab
    /// strip). When nil, the card draws its standard glyph tile.
    let header: AnyView?
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    @ViewBuilder var bodyBlock: () -> BodyBlock

    init(
        chrome: SplayCardChrome,
        header: AnyView? = nil,
        onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void = {},
        @ViewBuilder bodyBlock: @escaping () -> BodyBlock = { EmptyView() }
    ) {
        self.chrome = chrome
        self.header = header
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        self.bodyBlock = bodyBlock
    }

    var body: some View {
        VStack(spacing: 0) {
            if let header { header } else { glyphTile }
            Text(chrome.title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(SplayCardPalette.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text(chrome.message)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            let block = bodyBlock()
            if !(block is EmptyView) {
                block.padding(.top, 16)
            }

            buttonRow.padding(.top, 20)

            if let dots = chrome.dots {
                dotRow(index: dots.index, count: dots.count).padding(.top, 16)
            }
        }
        .padding(EdgeInsets(top: 26, leading: 24, bottom: 20, trailing: 24))
        .frame(width: chrome.width)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SplayCardPalette.surface)
                // Two soft layers, macOS-panel style: a faint contact shadow for
                // the near edge + a low-opacity ambient for lift. Deliberately
                // subtle (was a heavy radius-35 / 0.35 slab that read as a grey band).
                .shadow(color: SplayCardPalette.rgba(28, 20, 55, 0.10), radius: 3, y: 1)
                .shadow(color: SplayCardPalette.rgba(28, 20, 55, 0.14), radius: 22, y: 11)
        )
        // Swallow taps that land on the card so a click-away (in the margin) only
        // fires outside it. Entry/exit motion is owned by `SplayCardFloat`.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { }
    }

    private var glyphTile: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(SplayCardPalette.tileFill(danger: chrome.danger))
            .frame(width: 46, height: 46)
            .overlay(
                Text(chrome.glyph)
                    .font(.system(size: 19))
                    .foregroundStyle(SplayCardPalette.tint(danger: chrome.danger))
            )
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            if let secondary = chrome.secondaryLabel {
                SplayCardButton(label: secondary, prominent: false, danger: chrome.danger, action: onSecondary)
            }
            SplayCardButton(label: chrome.primaryLabel, prominent: true, danger: chrome.danger, action: onPrimary)
        }
    }

    private func dotRow(index: Int, count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? SplayCardPalette.brand : SplayCardPalette.rgba(36, 31, 56, 0.15))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Interactive feedback

/// Every actionable control gets a "this is interface" feel: a pointer cursor +
/// a subtle hover lift and a press dip. `SplayCardButton` is the card's button;
/// `SplayPressStyle` supplies the press scale/opacity for any button.

private struct SplayPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct SplayCardButton: View {
    let label: String
    let prominent: Bool
    let danger: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(prominent ? Color.white : SplayCardPalette.secondaryInk)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(prominent
                              ? SplayCardPalette.tint(danger: danger)
                              : SplayCardPalette.rgba(36, 31, 56, 0.07))
                        // Hover lift: prominent brightens; secondary deepens a touch.
                        .brightness(hovering && prominent ? 0.06 : 0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(hovering && !prominent ? 0.04 : 0))
                        )
                        .animation(.easeOut(duration: 0.12), value: hovering)
                )
                // A hair of hover growth so the button feels like it "answers".
                .scaleEffect(hovering ? 1.012 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(SplayPressStyle())
        .onHover { hovering = $0; SplayHoverCursor.apply($0) }
    }
}

/// Centralised pointer-cursor toggle for hoverable card controls.
enum SplayHoverCursor {
    static func apply(_ inside: Bool) {
        if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }
}

// MARK: - Accent picker (the seven colour options)

/// A row of seven colour swatches. Picking one sets `SplayTheme.shared.accent`,
/// which recolours the brand across the island and cards live (and persists).
struct SplayAccentPicker: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(SplayAccent.all) { accent in
                SplayAccentSwatch(
                    accent: accent,
                    selected: accent.id == SplayTheme.shared.accent.id,
                    onPick: { withAnimation(.easeInOut(duration: 0.22)) { SplayTheme.shared.accent = accent } }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SplayAccentSwatch: View {
    let accent: SplayAccent
    let selected: Bool
    let onPick: () -> Void
    @State private var hovering = false

    var body: some View {
        Circle()
            .fill(accent.brand)
            .frame(width: 22, height: 22)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(selected ? 1 : 0)
            )
            // Selection ring sits just outside the swatch.
            .overlay(
                Circle()
                    .strokeBorder(accent.brand.opacity(0.55), lineWidth: selected ? 2 : 0)
                    .padding(-3)
            )
            .scaleEffect(selected ? 1.0 : (hovering ? 1.14 : 1.0))
            .shadow(color: accent.brand.opacity(selected || hovering ? 0.5 : 0), radius: 5)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selected)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(Circle())
            .onTapGesture(perform: onPick)
            .onHover { hovering = $0; SplayHoverCursor.apply($0) }
            .help(accent.name)
            .accessibilityLabel(accent.name)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Body block 1 — destination list

struct SplayDestination: Identifiable {
    var id: String { name }
    let glyph: String
    let name: String
    let sub: String
}

struct SplayDestinationList: View {
    let destinations: [SplayDestination]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 7) {
            ForEach(Array(destinations.enumerated()), id: \.element.id) { index, dest in
                SplayDestinationRow(dest: dest, selected: index == selectedIndex) { onSelect(index) }
            }
        }
    }
}

private struct SplayDestinationRow: View {
    let dest: SplayDestination
    let selected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.75))
                .frame(width: 26, height: 26)
                .overlay(Text(dest.glyph).font(.system(size: 13)).foregroundStyle(SplayCardPalette.brand))
            VStack(alignment: .leading, spacing: 2) {
                Text(dest.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(SplayCardPalette.secondaryInk)
                Text(dest.sub).font(.system(size: 11)).foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.5))
            }
            Spacer(minLength: 6)
            if selected {
                Text("Default").font(.system(size: 11, weight: .medium)).foregroundStyle(SplayCardPalette.brand)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected
                      ? SplayCardPalette.brandTint(0.11)
                      : SplayCardPalette.rgba(36, 31, 56, hovering ? 0.07 : 0.04))   // hover highlight
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? SplayCardPalette.brand : SplayCardPalette.rgba(36, 31, 56, 0.08),
                                      lineWidth: selected ? 1.5 : 1)
                )
        )
        .scaleEffect(hovering && !selected ? 1.01 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering = $0; SplayHoverCursor.apply($0) }
    }
}

// MARK: - Body block 2 — permission row

struct SplayPermissionInfo {
    let glyph: String
    let name: String
    let sub: String
    let state: String
    var danger: Bool = false
}

struct SplayPermissionRow: View {
    let info: SplayPermissionInfo

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white)
                .frame(width: 32, height: 32)
                .overlay(Text(info.glyph).font(.system(size: 15)).foregroundStyle(SplayCardPalette.tint(danger: info.danger)))
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(SplayCardPalette.secondaryInk)
                Text(info.sub).font(.system(size: 11)).foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.5))
            }
            Spacer(minLength: 8)
            Text(info.state).font(.system(size: 11.5, weight: .medium)).foregroundStyle(SplayCardPalette.tint(danger: info.danger))
        }
        .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(SplayCardPalette.tileFill(danger: info.danger))
        )
    }
}

// MARK: - Body block 3 — key caps

struct SplayKeyCaps: View {
    let caps: [String]

    var body: some View {
        HStack(spacing: 20) {
            ForEach(caps, id: \.self) { cap in
                Text(cap)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(SplayCardPalette.secondaryInk)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(SplayCardPalette.rgba(36, 31, 56, 0.06))
                    )
            }
        }
    }
}

// MARK: - Body block 4 — recording list

struct SplayRecordingRow: Identifiable {
    let id: UUID
    let time: String
    let duration: String
    let title: String
    /// The transcript text this row copies to the clipboard (clean, else raw).
    /// Empty when the recording has no transcript yet.
    let transcript: String
    /// An fn dictation (from the `dictations` table) rather than a recording file.
    var isDictation = false
    /// Sort key for interleaving recordings and dictations.
    var createdAt = Date.distantPast
    /// Set when the job did not produce a transcript: it failed (with its
    /// reason) or was cancelled. The row says so instead of sitting blank.
    var problem: Problem?
    /// A file transcription (menu ▸ Transcribe File / icon drop), whose
    /// transcript lives in the Transcriptions folder rather than Meetings.
    var isFileImport = false

    enum Problem: Equatable {
        case failed(reason: String?)
        case cancelled

        var label: String {
            switch self {
            case .failed: return "Failed"
            case .cancelled: return "Cancelled"
            }
        }

        var detail: String {
            switch self {
            case .failed(let reason): return reason.map { "Failed: \($0)" } ?? "Transcription failed"
            case .cancelled: return "Cancelled before it finished"
            }
        }
    }

    /// The newest `limit` recordings and dictations, interleaved newest first.
    /// Dictations are here so one that pasted into the wrong place is never lost;
    /// failed or empty ones are left out (there is nothing to copy).
    static func recents(
        transcriptions: [Transcription],
        dictations: [Dictation],
        limit: Int,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [SplayRecordingRow] {
        let keptDictations = dictations.filter {
            $0.status == .completed
                && !$0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let rows = transcriptions.map { from($0, now: now, calendar: calendar) }
            + keptDictations.map { from($0, now: now, calendar: calendar) }
        return Array(rows.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    /// Build a row from an fn dictation: titled by its own words (one line),
    /// copying the stored text exactly.
    static func from(_ d: Dictation, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> SplayRecordingRow {
        let transcript = d.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = transcript.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        return SplayRecordingRow(
            id: d.id,
            time: timeLabel(for: d.createdAt, now: now, calendar: calendar),
            duration: durationLabel(ms: d.durationMs),
            title: title,
            transcript: transcript,
            isDictation: true,
            createdAt: d.createdAt
        )
    }

    /// Build a row from a stored transcription (the newest files in ~/Splay).
    static func from(_ t: Transcription, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> SplayRecordingRow {
        let title: String = {
            if let derived = t.derivedTitle, !derived.trimmingCharacters(in: .whitespaces).isEmpty { return derived }
            let base = (t.fileName as NSString).deletingPathExtension
            return base.isEmpty ? t.fileName : base
        }()
        let transcript = (t.cleanTranscript ?? t.rawTranscript ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let problem: Problem? = switch t.status {
        case .error: .failed(reason: t.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines))
        case .cancelled: .cancelled
        case .completed, .processing: nil
        }
        return SplayRecordingRow(
            id: t.id,
            time: timeLabel(for: t.createdAt, now: now, calendar: calendar),
            duration: durationLabel(ms: t.durationMs),
            title: title,
            transcript: transcript,
            createdAt: t.createdAt,
            problem: problem,
            isFileImport: t.sourceType == .file
        )
    }

    private static func timeLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
        }
        if calendar.isDateInYesterday(date) { return "Yest." }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 {
            let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: date)
        }
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: date)
    }

    private static func durationLabel(ms: Int?) -> String {
        guard let ms, ms > 0 else { return "—" }
        let total = ms / 1000
        let m = total / 60, s = total % 60
        if m >= 60 { return String(format: "%d:%02d:%02d", m / 60, m % 60, s) }
        return String(format: "%d:%02d", m, s)
    }
}

struct SplayRecordingList: View {
    let rows: [SplayRecordingRow]
    let footer: String
    /// Copy this row's transcript to the clipboard. The folder stays the archive;
    /// this saves the trip there for the common "grab what I just said" case.
    let onCopy: (SplayRecordingRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                SplayRecordingRowView(row: row, firstRow: index == 0) { onCopy(row) }
            }

            Divider()
                .overlay(SplayCardPalette.rgba(36, 31, 56, 0.1))
                .padding(.top, 10)
            Text(footer)
                .font(.system(size: 11.5))
                .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 11)
        }
    }
}

/// One recents row. The whole row copies its transcript (bigger target than the
/// icon alone); the trailing clipboard glyph is the affordance and flashes a
/// checkmark on copy. Hover highlights the row + pops the glyph so it reads as
/// interactive rather than a static list entry.
private struct SplayRecordingRowView: View {
    let row: SplayRecordingRow
    let firstRow: Bool
    let onCopy: () -> Void
    @State private var hovering = false
    @State private var copied = false

    private var canCopy: Bool { !row.transcript.isEmpty }

    var body: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.time).font(.system(size: 12)).foregroundStyle(SplayCardPalette.secondaryInk)
                Text(row.duration).font(.system(size: 10.5)).foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.42))
            }
            .frame(width: 52, alignment: .leading)
            .monospacedDigit()

            if row.isDictation {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.42))
                    .help("Dictation")
            }
            if let problem = row.problem {
                Text(problem.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(problemTint(problem))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(problemTint(problem).opacity(0.1)))
            }
            Text(row.title)
                .font(.system(size: 12.5))
                .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, row.problem == nil ? 0.72 : 0.45))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let problem = row.problem, !canCopy {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(problemTint(problem).opacity(0.7))
                    .frame(width: 16, alignment: .center)
            } else {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(copied
                                     ? SplayCardPalette.brand
                                     : SplayCardPalette.brandTint(canCopy ? (hovering ? 0.95 : 0.5) : 0.22))
                    .frame(width: 16, alignment: .center)
                    .scaleEffect(hovering && canCopy ? 1.16 : 1)
                    .animation(.easeOut(duration: 0.12), value: hovering)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: copied)
            }
        }
        .padding(EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 11))
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(rowFill)
        )
        .scaleEffect(hovering && canCopy ? 1.008 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canCopy else { return }
            onCopy()
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
        }
        .onHover { hovering = $0 && canCopy; SplayHoverCursor.apply(hovering) }
        .help(canCopy ? "Copy transcript" : (row.problem?.detail ?? "No transcript yet"))
        .accessibilityElement()
        .accessibilityLabel("\(row.isDictation ? "Dictation: " : "")\(row.problem.map { "\($0.label): " } ?? "")\(row.title), \(row.time)")
        .accessibilityHint(canCopy ? "Copies the transcript" : (row.problem?.detail ?? "No transcript yet"))
        .accessibilityAddTraits(.isButton)
    }

    private func problemTint(_ problem: SplayRecordingRow.Problem) -> Color {
        switch problem {
        case .failed: return SplayCardPalette.danger
        case .cancelled: return SplayCardPalette.rgba(36, 31, 56, 0.55)
        }
    }

    private var rowFill: Color {
        if firstRow { return SplayCardPalette.brandTint(hovering ? 0.14 : 0.09) }
        return SplayCardPalette.rgba(36, 31, 56, hovering ? 0.05 : 0)
    }
}

// MARK: - Body block 5 — toggle list

struct SplayToggle: Identifiable {
    var id: String { label }
    let label: String
    let isOn: Binding<Bool>
}

struct SplayToggleList: View {
    let toggles: [SplayToggle]
    var footer: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toggles) { toggle in
                HStack {
                    Text(toggle.label)
                        .font(.system(size: 12.5))
                        .foregroundStyle(SplayCardPalette.ink)
                    Spacer(minLength: 12)
                    SplaySwitch(isOn: toggle.isOn)
                }
                .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(SplayCardPalette.rgba(36, 31, 56, 0.035))
                )
            }
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 3)
            }
        }
    }
}

// MARK: - Gesture legend

/// What each `fn` gesture does (Settings). Read-only: the gestures are fixed,
/// so this explains them rather than offering a switch. Rows match the toggle
/// list's shape; the key column uses the key-cap fill.
struct SplayGestureLegend: View {
    struct Row: Identifiable {
        var id: String { keys }
        let keys: String
        let meaning: String
    }

    static let rows: [Row] = [
        Row(keys: "fn", meaning: "Record from your mic"),
        Row(keys: "fn fn", meaning: "Dictate into the text field you're in"),
        Row(keys: "fn fn fn", meaning: "Record a call — mic and system audio"),
        Row(keys: "esc", meaning: "Throw a dictation away — fn within \(DictationFlowTiming.cancelCountdownSeconds) s keeps it")
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Self.rows) { row in
                HStack(spacing: 12) {
                    Text(row.keys)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(SplayCardPalette.secondaryInk)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(SplayCardPalette.rgba(36, 31, 56, 0.07))
                        )
                        .frame(width: 78, alignment: .leading)
                    Text(row.meaning)
                        .font(.system(size: 12.5))
                        .foregroundStyle(SplayCardPalette.ink)
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 8, leading: 13, bottom: 8, trailing: 13))
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(SplayCardPalette.rgba(36, 31, 56, 0.035))
                )
                .accessibilityElement(children: .combine)
            }
            Text("Tap fn again to stop.")
                .font(.system(size: 11.5))
                .foregroundStyle(SplayCardPalette.rgba(36, 31, 56, 0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 3)
        }
    }
}

/// The design's 38×22 pill switch (handoff §Toggle list) — a compact custom
/// control so it matches the card exactly rather than the stock macOS toggle.
struct SplaySwitch: View {
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isOn ? SplayCardPalette.brand : SplayCardPalette.rgba(36, 31, 56, 0.16))
            .frame(width: 38, height: 22)
            // Hover lift so the switch reads as a control, not a label.
            .brightness(hovering && isOn ? 0.06 : 0)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .padding(3)
                    .frame(maxWidth: .infinity, alignment: isOn ? .trailing : .leading)
            )
            .scaleEffect(hovering ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(Rectangle())
            .onTapGesture {
                if reduceMotion { isOn.toggle() }
                else { withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) { isOn.toggle() } }
            }
            .onHover { hovering = $0; SplayHoverCursor.apply($0) }
            .accessibilityElement()
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isButton)
    }
}

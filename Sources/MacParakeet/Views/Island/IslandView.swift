import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

// MARK: - Visual states

/// The discrete visual forms the ambient island morphs through. Distinct from
/// `MeetingRecordingPillViewModel.PillState` because several recording-flow
/// states collapse onto one island form (e.g. `.paused` reuses the recording
/// form; `.completing` reuses transcribing), and idle splits into collapsed vs.
/// hover. The AppKit tracker and the SwiftUI view derive sizes from the same
/// `IslandLayout`, so their hit-rects never drift from what's drawn.
enum IslandVisual: Equatable {
    case hidden
    case idleCollapsed
    case idleHover
    case recording
    case transcribing
    case done
    /// The Spotlight-style card — the same pill, morphed large. Rendered in the
    /// same panel so it grows out of the nub with the identical `.smooth` curve.
    case expanded
}

// MARK: - Shared layout (single source of truth for view + tracker)

enum IslandLayout {
    /// The panel is a fixed, generous stage; the pill morphs *within* it,
    /// horizontally centered and anchored a fixed distance above the bottom.
    /// Nothing resizes the panel, so the morph stays smooth and the Dock gap
    /// is constant.
    // The stage must be tall/wide enough to contain the expanded card, which
    // grows upward from the bottom-center. The pill morphs *within* it.
    static let panelWidth: CGFloat = 520
    static let panelHeight: CGFloat = 460
    static let bottomInset: CGFloat = 16

    static let expandedSize = CGSize(width: 452, height: 412)

    static func pillSize(for visual: IslandVisual) -> CGSize {
        switch visual {
        case .hidden:        return .zero
        // Idle is a deliberately tiny, understated nub (close to the original
        // app's 48×10) — it should barely register until you reach for it.
        case .idleCollapsed: return CGSize(width: 56, height: 11)
        case .idleHover:     return CGSize(width: 252, height: 44)
        case .recording:     return CGSize(width: 170, height: 34)
        case .transcribing:  return CGSize(width: 206, height: 38)
        case .done:          return CGSize(width: 196, height: 40)
        case .expanded:      return expandedSize
        }
    }

    /// Width of the right-edge stop-button hit zone inside the recording pill.
    static let stopHitWidth: CGFloat = 38

    /// Interaction rect for the AppKit tracker — same as the drawn pill except
    /// the tiny idle nub, which gets an enlarged invisible target so it stays
    /// easy to hover/click despite barely showing.
    static func hitRect(for visual: IslandVisual) -> CGRect {
        guard visual == .idleCollapsed else { return pillRect(for: visual) }
        let w: CGFloat = 88
        let h: CGFloat = 30
        return CGRect(x: (panelWidth - w) / 2, y: bottomInset - 2, width: w, height: h)
    }

    /// Map recording-flow state (+ idle chrome) onto a visual form. The expanded
    /// card wins over everything while it's open.
    static func visual(
        for state: MeetingRecordingPillViewModel.PillState,
        hovered: Bool,
        idleVisible: Bool,
        expanded: Bool = false
    ) -> IslandVisual {
        if expanded { return .expanded }
        switch state {
        case .idle:
            guard idleVisible else { return .hidden }
            return hovered ? .idleHover : .idleCollapsed
        case .recording, .paused:
            return .recording
        case .completing, .transcribing:
            return .transcribing
        case .completed, .error:
            return .done
        }
    }

    /// The pill's frame in panel (AppKit, bottom-left origin) coordinates.
    static func pillRect(for visual: IslandVisual) -> CGRect {
        let size = pillSize(for: visual)
        return CGRect(
            x: (panelWidth - size.width) / 2,
            y: bottomInset,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Local chrome model (idle hover + visibility)

/// Lightweight, app-target-local state for the island's idle chrome. The
/// recording lifecycle lives on the shared `MeetingRecordingPillViewModel`;
/// this only carries hover + the user's "show idle pill" preference.
@MainActor @Observable
final class IslandChromeModel {
    var isHovered = false
    var idleVisible = true
    /// The expanded card is open. Wins over idle/recording in `visual`.
    var isExpanded = false
    init() {}
}

// MARK: - Island view

/// The ambient island at bottom-center. One persistent glass capsule whose
/// frame *morphs* between state sizes (Dynamic-Island style) while the foreground
/// content cross-fades — never a hard view swap, which is what reads as "chunky".
///
/// Display-only: all interaction is routed through `IslandController`'s AppKit
/// tracking layer (hover/click on a non-activating panel can't go through
/// SwiftUI). Forced into dark vibrancy so the glass reads the same over any
/// desktop.
struct IslandView: View {
    @Bindable var pill: MeetingRecordingPillViewModel
    @Bindable var chrome: IslandChromeModel

    // Expanded ("Spotlight card") dependencies. Rendered as a morphed state of
    // this same pill so it grows out of the nub with the identical animation.
    @Bindable var expandedModel: ExpandedIslandModel
    @Bindable var library: TranscriptionLibraryViewModel
    var onRecord: () -> Void
    var onSelect: (Transcription) -> Void
    var onOpenSettings: () -> Void
    var onOpenLibrary: () -> Void
    var onRevealInFinder: () -> Void
    var onCollapse: () -> Void

    @FocusState private var searchFocused: Bool

    private var visual: IslandVisual {
        IslandLayout.visual(
            for: pill.state,
            hovered: chrome.isHovered,
            idleVisible: chrome.idleVisible,
            expanded: chrome.isExpanded
        )
    }

    var body: some View {
        let size = IslandLayout.pillSize(for: visual)
        // Capsule for small states, ~20pt rounded rect when large — one shape
        // whose radius morphs as the height grows.
        let radius = min(size.height / 2, 20)
        ZStack(alignment: .bottom) {
            Color.clear
            if visual != .hidden {
                ZStack {
                    roundedBackground(radius: radius)
                    foreground
                        .id(visual)                       // identity flips → cross-fade
                        .transition(.opacity)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(
                    color: .black.opacity(visual == .idleCollapsed ? 0.18 : 0.3),
                    radius: visual == .idleCollapsed ? 4 : (visual == .expanded ? 26 : 11),
                    y: visual == .idleCollapsed ? 2 : (visual == .expanded ? 16 : 6)
                )
                .padding(.bottom, IslandLayout.bottomInset)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // A single smooth (no-bounce) curve drives the morph + cross-fade.
        .animation(.smooth(duration: 0.36), value: visual)
        // Interactive only when expanded (search field + buttons); otherwise
        // display-only, with the AppKit tracker owning hover/click.
        .allowsHitTesting(visual == .expanded)
        .environment(\.colorScheme, .dark)
        .onChange(of: chrome.isExpanded) { _, expanded in
            if expanded {
                DispatchQueue.main.async { searchFocused = true }
            } else {
                searchFocused = false
            }
        }
    }

    // MARK: Foreground content (no background — the shared shape provides it)

    @ViewBuilder private var foreground: some View {
        switch visual {
        case .hidden, .idleCollapsed:
            Color.clear
        case .idleHover:
            hoverContent
        case .recording:
            recordingContent
        case .transcribing:
            transcribingContent
        case .done:
            doneContent
        case .expanded:
            ExpandedIslandView(
                model: expandedModel,
                library: library,
                searchFocused: $searchFocused,
                onRecord: onRecord,
                onSelect: onSelect,
                onOpenSettings: onOpenSettings,
                onOpenLibrary: onOpenLibrary,
                onRevealInFinder: onRevealInFinder,
                onEscape: onCollapse
            )
        }
    }

    private var hoverContent: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(IslandPalette.ready)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                (Text("Press ") + Text("fn").foregroundColor(IslandPalette.ready).fontWeight(.bold) + Text(" to record"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Double-tap for calls · Click to open")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 15)
        .fixedSize()
    }

    private var recordingContent: some View {
        let paused = pill.isPaused
        return HStack(spacing: 9) {
            Circle()
                .fill(IslandPalette.rec)
                .frame(width: 8, height: 8)
                .modifier(PulseModifier(active: !paused))

            if paused {
                Text("Paused")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                IslandWaveform()
                    .frame(width: 30, height: 14)
            }

            Text(pill.formattedElapsed)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 40, alignment: .leading)

            stopGlyph
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .fixedSize()
    }

    private var stopGlyph: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.white)
            .frame(width: 22, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(IslandPalette.rec)
                    .frame(width: 8, height: 8)
            )
    }

    private var transcribingContent: some View {
        HStack(spacing: 11) {
            IslandSpinner()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(pill.state == .completing ? "Wrapping up…" : "Transcribing…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                IslandProgressBar()
                    .frame(width: 124, height: 3.5)
            }
        }
        .padding(.horizontal, 15)
        .fixedSize()
    }

    private var doneContent: some View {
        let isError: Bool = { if case .error = pill.state { return true } else { return false } }()
        return HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(isError ? IslandPalette.rec : IslandPalette.accent)
                    .frame(width: 21, height: 21)
                Image(systemName: isError ? "exclamationmark" : "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(isError ? "Couldn't save" : "Saved")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(isError ? "tap fn to retry" : "· \(pill.formattedElapsed)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            if !isError {
                Text("Open")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, isError ? 14 : 9)
        .fixedSize()
    }

    // MARK: Background

    /// Flat, dark, understated — matching the original app's pill rather than
    /// the lookbook's frosted glass. Idle nub is a soft grey so it barely
    /// registers; active states + the expanded card deepen to near-black.
    private func roundedBackground(radius: CGFloat) -> some View {
        let fill: Color = {
            switch visual {
            case .idleCollapsed: return Color(white: 0.24, opacity: 0.85)
            case .expanded:      return Color(white: 0.13, opacity: 0.98)
            default:             return Color.black.opacity(0.74)
            }
        }()
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(visual == .idleCollapsed ? 0.08 : 0.12), lineWidth: 0.5)
            )
    }
}

// MARK: - Palette

enum IslandPalette {
    static let accent = DesignSystem.Colors.accent
    static let ready = Color(red: 0.357, green: 0.859, blue: 0.341)   // #5BDB57
    static let rec = Color(red: 1.0, green: 0.353, blue: 0.322)       // #FF5A52
}

// MARK: - Decorative waveform (self-animating, not real levels)

/// The lookbook's recording waveform is decorative motion, not metered audio —
/// so this animates on its own timeline and needs no level feed.
private struct IslandWaveform: View {
    private let bars = 7
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<bars, id: \.self) { i in
                    let phase = t * 6 + Double(i) * 0.7
                    let h = 0.35 + 0.65 * (0.5 + 0.5 * sin(phase))
                    Capsule()
                        .fill(IslandPalette.ready)
                        .frame(width: 2.5, height: 16 * h)
                }
            }
            .frame(height: 16)
        }
    }
}

private struct IslandSpinner: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [IslandPalette.ready.opacity(0), IslandPalette.ready]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1) * 360))
        }
    }
}

/// Indeterminate progress: we don't have a real % on the pill VM, so a sweeping
/// highlight conveys "working" honestly rather than faking a number.
private struct IslandProgressBar: View {
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let w = geo.size.width
                let segment = w * 0.4
                let travel = (w + segment)
                let x = (t.truncatingRemainder(dividingBy: 1.3) / 1.3) * travel - segment
                Capsule()
                    .fill(.white.opacity(0.14))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(IslandPalette.ready)
                            .frame(width: segment)
                            .offset(x: x)
                    }
                    .clipShape(Capsule())
            }
        }
    }
}

private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(active ? (on ? 0.35 : 1.0) : 0.6)
            .animation(active ? .easeInOut(duration: 0.65).repeatForever(autoreverses: true) : .default, value: on)
            .onAppear { if active { on = true } }
    }
}

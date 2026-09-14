import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// The island. Straight from the v5 mock: compact = glyph left, bars right;
// expanded = one 84-pt row (glyph · word · level · time · control); Lock Screen
// = the same row. No light, no subtitles. SF Symbols throughout.

private enum Palette {
    static let rec = Color(red: 1.0, green: 0.42, blue: 0.37)      // #FF6B5E
    static let amber = Color(red: 0.965, green: 0.784, blue: 0.42) // #F6C86B
    static let green = Color(red: 0.373, green: 0.851, blue: 0.627)// #5FD9A0
    static let fail = Color(red: 1.0, green: 0.478, blue: 0.431)   // #FF7A6E
    static let lav = Color(red: 0.663, green: 0.608, blue: 0.961)  // #A99BF5
    static let onFill = Color(red: 0.043, green: 0.031, blue: 0.075)
}

struct SplayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SplayActivityAttributes.self) { context in
            LockScreenRow(state: context.state)
                .activityBackgroundTint(.black.opacity(0.78))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LeadingGlyph(state: context.state, large: true)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 12) {
                        Text(context.state.phase.title)
                            .font(.system(size: 17, weight: .semibold))
                        Bars(state: context.state, count: 18)
                            .frame(maxWidth: .infinity, maxHeight: 28)
                        ElapsedText(state: context.state)
                            .font(.system(size: 19, weight: .medium, design: .monospaced))
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ControlButton(state: context.state)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            } compactLeading: {
                LeadingGlyph(state: context.state, large: false)
            } compactTrailing: {
                TrailingGlyph(state: context.state)
            } minimal: {
                LeadingGlyph(state: context.state, large: false)
            }
            .keylineTint(Palette.tint(for: context.state.phase).opacity(0.55))
        }
    }
}

extension Palette {
    /// The state colour: the same hue drives the key line, the bars, the glyphs.
    static func tint(for phase: SplayActivityAttributes.ContentState.Phase) -> Color {
        switch phase {
        case .recording: rec
        case .paused, .inputDead, .finishing: amber
        case .saved: green
        case .failed: fail
        }
    }
}

// MARK: - Pieces

private struct LeadingGlyph: View {
    let state: SplayActivityAttributes.ContentState
    let large: Bool

    var body: some View {
        let size: CGFloat = large ? 22 : 16
        switch state.phase {
        case .recording:
            Circle().fill(Palette.rec).frame(width: large ? 10 : 8, height: large ? 10 : 8)
        case .inputDead:
            Circle().fill(Palette.amber).frame(width: large ? 10 : 8, height: large ? 10 : 8)
        case .paused:
            Image(systemName: "pause.fill").font(.system(size: large ? 16 : 12, weight: .bold)).foregroundStyle(Palette.amber)
        case .finishing:
            SplayMark().frame(width: size, height: size)
        case .saved:
            Image(systemName: "checkmark.circle.fill").font(.system(size: size)).foregroundStyle(Palette.onFill, Palette.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: size)).foregroundStyle(Palette.onFill, Palette.fail)
        }
    }
}

private struct TrailingGlyph: View {
    let state: SplayActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording, .paused, .inputDead, .finishing:
            Bars(state: state, count: 4).frame(width: 18, height: 16)
        case .saved:
            Image(systemName: "doc.on.doc").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.green)
        case .failed:
            Image(systemName: "waveform").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.fail)
        }
    }
}

/// Level bars. WidgetKit cannot run a continuous animation, so the recording
/// bars use a phase-driven timeline (a gentle pulse), amber phases pulse
/// slower, and dead/paused are flat. The live mic level would need per-frame
/// updates, which Live Activities do not allow (HIG: update only on change).
private struct Bars: View {
    let state: SplayActivityAttributes.ContentState
    let count: Int

    var body: some View {
        let color = Palette.tint(for: state.phase)
        let flat = state.phase == .paused || state.phase == .inputDead
        TimelineView(.periodic(from: .now, by: state.phase == .recording ? 0.45 : 1.3)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    let h: CGFloat = flat ? 3 : 4 + 10 * abs(sin(t * 2.1 + Double(i) * 0.9)) * (state.phase == .recording ? 1 : 0.6)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: 3, height: h)
                        .opacity(flat ? 0.7 : 0.95)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: t)
        }
    }
}

private struct ElapsedText: View {
    let state: SplayActivityAttributes.ContentState

    var body: some View {
        if let origin = state.timerOrigin, state.phase == .recording || state.phase == .inputDead {
            // Counts on its own; no per-second activity updates (HIG).
            Text(timerInterval: origin...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        } else {
            Text(SplayActivityAttributes.ContentState.format(state.finalSeconds ?? state.elapsed()))
                .monospacedDigit()
        }
    }
}

/// The one control. Filled 44-pt circle, symbol only (HIG). Red = the accent
/// action (Resume), white = neutral (Pause, Retry). Finishing and Saved have none.
private struct ControlButton: View {
    let state: SplayActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording, .inputDead:
            circle(intent: PauseRecordingIntent(), symbol: "pause.fill", fill: .white)
        case .paused:
            circle(intent: ResumeRecordingIntent(), symbol: "play.fill", fill: Palette.rec)
        case .failed where state.canRetry:
            circle(intent: RetryTranscriptionIntent(), symbol: "arrow.clockwise", fill: .white)
        case .failed, .finishing, .saved:
            EmptyView()
        }
    }

    private func circle(intent: some AppIntent, symbol: String, fill: Color) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.onFill)
                .frame(width: 44, height: 44)
                .background(fill, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct LockScreenRow: View {
    let state: SplayActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            LeadingGlyph(state: state, large: true)
            Text(state.phase.title).font(.system(size: 17, weight: .semibold))
            Bars(state: state, count: 22).frame(maxWidth: .infinity, maxHeight: 28)
            ElapsedText(state: state).font(.system(size: 19, weight: .medium, design: .monospaced))
            ControlButton(state: state)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 84)
    }
}

/// The Splay mark: a ring with a centre dot, lavender, no container (HIG: logo
/// marks without a container).
private struct SplayMark: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(Palette.lav, lineWidth: 2)
            Circle().fill(Palette.lav).scaleEffect(0.36)
        }
    }
}

import Foundation

/// What a resolved bare-`fn` gesture asks for in `.tapDoubleTripleToggle`.
/// See docs/plans/fn-dictation-double-tap.md.
public enum FnCaptureKind: Equatable, Sendable {
    /// Tap: mic-only recording → transcript file.
    case microphoneRecording
    /// Double-tap: dictation, pasted into the field focused at stop.
    case dictation
    /// Triple-tap: mic + system audio recording → transcript file.
    case meeting
}

/// Pure controller for hotkey gesture flow.
/// Owns gesture semantics and timer directives, but no OS event-tap wiring.
public final class HotkeyGestureController {
    public enum Mode: Equatable, Sendable {
        case doubleTapAndHold
        case doubleTapOnly
        case holdOnly
        case singleTapToggle
        /// MacParakeet-MC fork: single bare tap toggles a mic-only recording,
        /// double tap toggles a mic+system recording. No hold semantics. The
        /// app routes both outputs to the meeting coordinator's `toggleRecording`,
        /// which decides start vs stop. See docs/fork-product-model.md.
        case singleAndDoubleTapToggle
        /// Splay Fn: tap = mic recording, double-tap = dictation, triple-tap =
        /// meeting. While a capture is active (`isCaptureActive`), every tap is
        /// an immediate stop with no window wait. No hold semantics.
        case tapDoubleTripleToggle
    }

    public enum Output: Equatable, Sendable {
        case startRecording(mode: FnKeyStateMachine.RecordingMode)
        case stopRecording
        case cancelRecording
        case discardRecording(showReadyPill: Bool)
        case showReadyForSecondTap
        case escapeWhileIdle
        case scheduleStartupDebounce(milliseconds: Int)
        case scheduleHoldWindow(milliseconds: Int)
        case cancelStartupDebounce
        case cancelHoldWindow
        /// Toggle a recording with the given audio source (fork single/double-tap Fn).
        case toggleRecording(source: MeetingAudioSourceMode)
        /// Start a capture (`.tapDoubleTripleToggle`, resolved gesture).
        case startCapture(FnCaptureKind)
        /// Stop whatever capture is active (`.tapDoubleTripleToggle`).
        case stopCapture
    }

    public let tapThresholdMs: Int
    public let startupDebounceMs: Int

    private enum HoldOnlyState: Equatable {
        case idle
        case pressed
        case active
        case cancelWindow
        case blocked
    }

    private enum SingleTapState: Equatable {
        case idle
        case active
        case cancelWindow
        case blocked
    }

    /// State for `.singleAndDoubleTapToggle`: after the first bare tap we wait
    /// `tapThresholdMs` for a possible second tap before resolving single vs double.
    private enum SingleDoubleTapState: Equatable {
        case idle
        case awaitingSecondTap
    }

    /// State for `.tapDoubleTripleToggle`: each bare tap re-arms a
    /// `tapThresholdMs` window; the window elapsing resolves the tap count.
    private enum TapCountState: Equatable {
        case idle
        case awaitingSecondTap
        case awaitingThirdTap
    }

    /// `.tapDoubleTripleToggle` only: queried at each tap. `true` turns the tap
    /// into `.stopCapture`. Queried rather than mirrored so it cannot go stale.
    public var isCaptureActive: () -> Bool = { false }

    private let mode: Mode
    private let stateMachine: FnKeyStateMachine
    private var holdOnlyState: HoldOnlyState = .idle
    private var singleTapState: SingleTapState = .idle
    private var singleDoubleState: SingleDoubleTapState = .idle
    private var tapCountState: TapCountState = .idle
    private var suppressedUntilReset = false

    public init(
        mode: Mode = .doubleTapAndHold,
        tapThresholdMs: Int = FnKeyStateMachine.defaultTapThresholdMs,
        startupDebounceMs: Int = FnKeyStateMachine.defaultStartupDebounceMs
    ) {
        let clampedTapThreshold = FnKeyStateMachine.clampTapThresholdMs(tapThresholdMs)
        self.mode = mode
        self.tapThresholdMs = clampedTapThreshold
        self.startupDebounceMs = min(clampedTapThreshold, max(0, startupDebounceMs))
        self.stateMachine = FnKeyStateMachine(tapThresholdMs: clampedTapThreshold)
    }

    public func triggerPressed(timestampMs: UInt64) -> [Output] {
        guard !suppressedUntilReset else { return [] }

        if mode == .holdOnly {
            switch holdOnlyState {
            case .idle:
                holdOnlyState = .pressed
                return [.scheduleStartupDebounce(milliseconds: startupDebounceMs)]
            case .cancelWindow, .blocked:
                holdOnlyState = .blocked
                return []
            case .pressed, .active:
                return []
            }
        }

        if mode == .singleTapToggle {
            switch singleTapState {
            case .idle:
                singleTapState = .active
                return [.startRecording(mode: .persistent)]
            case .active:
                singleTapState = .idle
                return [.stopRecording]
            case .cancelWindow, .blocked:
                singleTapState = .blocked
                return []
            }
        }

        // `.singleAndDoubleTapToggle`: the manager routes each completed bare tap
        // here (via the release path, like `.singleTapToggle`). First tap arms the
        // double-tap window; a second tap inside it resolves to mic+system.
        if mode == .singleAndDoubleTapToggle {
            switch singleDoubleState {
            case .idle:
                singleDoubleState = .awaitingSecondTap
                return [.scheduleHoldWindow(milliseconds: tapThresholdMs)]
            case .awaitingSecondTap:
                singleDoubleState = .idle
                return [.cancelHoldWindow, .toggleRecording(source: .microphoneAndSystem)]
            }
        }

        if mode == .tapDoubleTripleToggle {
            switch tapCountState {
            case .idle:
                if isCaptureActive() { return [.stopCapture] }
                tapCountState = .awaitingSecondTap
                return [.scheduleHoldWindow(milliseconds: tapThresholdMs)]
            case .awaitingSecondTap:
                tapCountState = .awaitingThirdTap
                return [.cancelHoldWindow, .scheduleHoldWindow(milliseconds: tapThresholdMs)]
            case .awaitingThirdTap:
                tapCountState = .idle
                return [.cancelHoldWindow, .startCapture(.meeting)]
            }
        }

        let action = stateMachine.fnDown(timestampMs: timestampMs)
        var results = outputs(for: action)
        if mode == .doubleTapAndHold, action == .none, stateMachine.state == .waitingForSecondTap {
            results.append(.scheduleStartupDebounce(milliseconds: startupDebounceMs))
            results.append(.scheduleHoldWindow(milliseconds: tapThresholdMs))
        }
        return results
    }

    public func triggerReleased(timestampMs: UInt64) -> [Output] {
        guard !suppressedUntilReset else { return [] }

        var results: [Output] = [.cancelStartupDebounce, .cancelHoldWindow]
        if mode == .holdOnly {
            switch holdOnlyState {
            case .pressed:
                holdOnlyState = .idle
            case .active:
                holdOnlyState = .idle
                results.append(.stopRecording)
            case .blocked:
                holdOnlyState = .cancelWindow
            case .idle, .cancelWindow:
                break
            }
            return results
        }

        if mode.actsOnReleaseTap {
            return []
        }

        let action = stateMachine.fnUp(timestampMs: timestampMs)
        results.append(contentsOf: outputs(for: action))
        if action == .none, stateMachine.state == .waitingForSecondTap {
            results.append(.showReadyForSecondTap)
        }
        return results
    }

    public func nonBareTriggerReleased() -> [Output] {
        guard !suppressedUntilReset else { return [] }

        var results: [Output] = [.cancelStartupDebounce, .cancelHoldWindow]

        if mode == .holdOnly {
            switch holdOnlyState {
            case .pressed:
                holdOnlyState = .idle
            case .active:
                holdOnlyState = .idle
                results.append(.cancelRecording)
            case .blocked:
                holdOnlyState = .cancelWindow
            case .idle, .cancelWindow:
                break
            }
            return results
        }

        if mode.actsOnReleaseTap {
            return []
        }

        switch stateMachine.state {
        case .holdToTalk:
            // Non-bare releases bypass outputs(for:) so the hotkey returns to idle
            // immediately before we propagate the explicit cancel side effect.
            stateMachine.reset()
            results.append(.cancelRecording)
        case .waitingForSecondTap:
            results.append(contentsOf: outputs(for: stateMachine.interruptWaitingForSecondTap()))
        default:
            break
        }

        return results
    }

    public func interrupted() -> [Output] {
        guard !suppressedUntilReset else { return [] }

        if mode == .holdOnly {
            return nonBareTriggerReleased()
        }

        if mode.actsOnReleaseTap {
            return []
        }

        var results: [Output] = [.cancelStartupDebounce, .cancelHoldWindow]
        switch stateMachine.state {
        case .waitingForSecondTap:
            results.append(contentsOf: outputs(for: stateMachine.interruptWaitingForSecondTap()))
            return results
        case .holdToTalk:
            stateMachine.reset()
            results.append(.cancelRecording)
            return results
        default:
            return []
        }
    }

    public func escapePressed() -> [Output] {
        guard !suppressedUntilReset else { return [] }

        if mode == .holdOnly {
            var results: [Output] = [.cancelStartupDebounce, .cancelHoldWindow]
            switch holdOnlyState {
            case .pressed:
                holdOnlyState = .idle
            case .active:
                holdOnlyState = .cancelWindow
                results.append(.cancelRecording)
            case .cancelWindow, .blocked:
                holdOnlyState = .idle
                results.append(.cancelRecording)
            case .idle:
                return [.escapeWhileIdle]
            }
            return results
        }

        if mode == .singleTapToggle {
            switch singleTapState {
            case .active:
                singleTapState = .cancelWindow
                return [.cancelRecording]
            case .cancelWindow, .blocked:
                singleTapState = .idle
                return [.cancelRecording]
            case .idle:
                return [.escapeWhileIdle]
            }
        }

        if mode == .singleAndDoubleTapToggle {
            if singleDoubleState == .awaitingSecondTap {
                singleDoubleState = .idle
                return [.cancelHoldWindow]
            }
            return []
        }

        if mode == .tapDoubleTripleToggle {
            if tapCountState != .idle {
                tapCountState = .idle
                return [.cancelHoldWindow]
            }
            // No gesture pending: the app decides (a dictation starts its undo
            // countdown; a recording ignores it; idle dismisses a lingering face).
            return [.cancelRecording]
        }

        let wasWaitingForSecondTap = stateMachine.state == .waitingForSecondTap
        let action = stateMachine.escapePressed()

        if action == .none {
            if wasWaitingForSecondTap {
                stateMachine.reset()
                return [.cancelStartupDebounce, .cancelHoldWindow]
            }
            return [.escapeWhileIdle]
        }

        var results: [Output] = [.cancelStartupDebounce, .cancelHoldWindow]
        results.append(contentsOf: outputs(for: action))
        return results
    }

    public func startupDebounceElapsed() -> [Output] {
        guard !suppressedUntilReset else { return [] }

        if mode == .doubleTapOnly { return [] }
        if mode.actsOnReleaseTap { return [] }
        if mode == .holdOnly {
            guard holdOnlyState == .pressed else { return [] }
            holdOnlyState = .active
            return [.startRecording(mode: .holdToTalk)]
        }
        return outputs(for: stateMachine.startupTimerFired())
    }

    public func holdWindowElapsed() -> [Output] {
        guard !suppressedUntilReset else { return [] }

        if mode == .doubleTapOnly { return [] }
        if mode == .singleTapToggle { return [] }
        if mode == .holdOnly { return [] }
        if mode == .singleAndDoubleTapToggle {
            guard singleDoubleState == .awaitingSecondTap else { return [] }
            singleDoubleState = .idle
            return [.toggleRecording(source: .microphoneOnly)]
        }
        if mode == .tapDoubleTripleToggle {
            let resolved = tapCountState
            tapCountState = .idle
            switch resolved {
            case .idle: return []
            case .awaitingSecondTap: return [.startCapture(.microphoneRecording)]
            case .awaitingThirdTap: return [.startCapture(.dictation)]
            }
        }
        return outputs(for: stateMachine.holdTimerFired())
    }

    public func suppressUntilReset() {
        suppressedUntilReset = true
        holdOnlyState = .idle
        singleTapState = .idle
        singleDoubleState = .idle
        tapCountState = .idle
        stateMachine.reset()
    }

    public func notifyCancelledByUI() {
        // The dictation flow resets all managers when the cancel window exits.
        // Until then, every dictation trigger stays blocked, even if it did not
        // start the recording that was cancelled.
        suppressedUntilReset = false
        if mode == .holdOnly {
            holdOnlyState = .cancelWindow
            return
        }
        if mode == .singleTapToggle {
            singleTapState = .cancelWindow
            return
        }
        if mode == .singleAndDoubleTapToggle {
            singleDoubleState = .idle
            return
        }
        if mode == .tapDoubleTripleToggle {
            tapCountState = .idle
            return
        }
        stateMachine.blockUntilReset()
    }

    public func resumeRecording(mode: FnKeyStateMachine.RecordingMode) {
        suppressedUntilReset = false
        if self.mode == .holdOnly {
            holdOnlyState = mode == .holdToTalk ? .active : .idle
            return
        }
        if self.mode == .singleTapToggle {
            singleTapState = mode == .persistent ? .active : .idle
            return
        }
        if self.mode == .singleAndDoubleTapToggle {
            singleDoubleState = .idle
            return
        }
        if self.mode == .tapDoubleTripleToggle {
            tapCountState = .idle
            return
        }
        stateMachine.resumeRecording(mode: mode)
    }

    public func reset() {
        suppressedUntilReset = false
        holdOnlyState = .idle
        singleTapState = .idle
        singleDoubleState = .idle
        tapCountState = .idle
        stateMachine.reset()
    }

    private func outputs(for action: FnKeyStateMachine.Action) -> [Output] {
        switch action {
        case .none:
            return []
        case .startRecording(let mode):
            return [.startRecording(mode: mode)]
        case .stopRecording:
            return [.stopRecording]
        case .cancelRecording:
            return [.cancelRecording]
        case .discardRecording(let showReadyPill):
            return [.discardRecording(showReadyPill: showReadyPill)]
        }
    }
}

extension HotkeyGestureController.Mode {
    /// Modes whose completed bare *tap* is delivered on release (the manager
    /// routes it through `triggerPressed`), rather than press/hold semantics.
    public var actsOnReleaseTap: Bool {
        switch self {
        case .singleTapToggle, .singleAndDoubleTapToggle, .tapDoubleTripleToggle:
            return true
        case .doubleTapAndHold, .doubleTapOnly, .holdOnly:
            return false
        }
    }
}

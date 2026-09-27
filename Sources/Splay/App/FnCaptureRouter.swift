import SplayCore

/// Routes resolved bare-`fn` gestures (`HotkeyGestureController`
/// `.tapDoubleTripleToggle`) to the two capture flows, and answers the one
/// question the gesture needs at each tap: is anything running? Dictation and
/// recordings share the mic and the island, so `fn` only ever drives one of
/// them at a time. See docs/plans/fn-dictation-double-tap.md.
@MainActor
struct FnCaptureRouter {
    let isDictationBusy: () -> Bool
    let isMeetingBusy: () -> Bool
    let startDictation: () -> Void
    let stopDictation: () -> Void
    let startRecording: (MeetingAudioSourceMode) -> Void
    /// Stops a recording; does nothing while it is transcribing / showing its
    /// result; on a held failure, opens the failure's card (the app's wiring
    /// decides).
    let stopRecording: () -> Void
    /// Escape during a dictation: upstream's 3-2-1 undo countdown.
    let cancelDictation: () -> Void
    /// Whether Escape may cancel the dictation now (capturing or counting down;
    /// never while it transcribes).
    let isDictationCancellable: () -> Bool

    static let inert = FnCaptureRouter(
        isDictationBusy: { false },
        isMeetingBusy: { false },
        startDictation: {},
        stopDictation: {},
        startRecording: { _ in },
        stopRecording: {},
        cancelDictation: {},
        isDictationCancellable: { false }
    )

    var isCaptureActive: Bool { isDictationBusy() || isMeetingBusy() }

    func start(_ kind: FnCaptureKind) {
        // The gesture resolved up to two tap windows after its first tap;
        // something else (menu bar, island click) may have started since.
        guard !isCaptureActive else { return }
        switch kind {
        case .microphoneRecording: startRecording(.microphoneOnly)
        case .dictation: startDictation()
        case .meeting: startRecording(.microphoneAndSystem)
        }
    }

    /// Escape with no fn gesture pending. Cancels a capturing (or counting-down)
    /// dictation; a transcribing dictation, a recording or a meeting ignores it
    /// (a stray Escape must never throw one away). Returns false when nothing
    /// runs, so the app's idle-Escape handling can apply.
    func escape() -> Bool {
        if isDictationCancellable() {
            cancelDictation()
            return true
        }
        return isCaptureActive
    }

    func stop() {
        if isDictationBusy() {
            stopDictation()
        } else if isMeetingBusy() {
            stopRecording()
        }
    }
}

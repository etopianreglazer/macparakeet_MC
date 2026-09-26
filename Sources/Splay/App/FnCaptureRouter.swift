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
    /// Stops a recording, or does nothing while it is transcribing / showing
    /// its result (the meeting flow decides).
    let stopRecording: () -> Void

    static let inert = FnCaptureRouter(
        isDictationBusy: { false },
        isMeetingBusy: { false },
        startDictation: {},
        stopDictation: {},
        startRecording: { _ in },
        stopRecording: {}
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

    func stop() {
        if isDictationBusy() {
            stopDictation()
        } else if isMeetingBusy() {
            stopRecording()
        }
    }
}

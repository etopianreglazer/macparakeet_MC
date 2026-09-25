import Foundation

/// Result of waiting on a one-shot callback with a deadline.
public enum BoundedCallbackOutcome<Value: Sendable>: Sendable {
    case completed(Value)
    case timedOut
}

/// Waits for a one-shot completion callback, but never longer than `timeout`.
///
/// Framework callbacks (ScreenCaptureKit start/stop, `AVAssetWriter.finishWriting`)
/// normally fire, but when one never does, an unbounded `withCheckedContinuation`
/// hangs Stop forever — the island stays amber and `fn` goes dead. Whichever of the
/// callback or the deadline comes first wins; a callback that arrives after the
/// deadline is handed to `onLate` (e.g. to stop a stream whose start landed late).
public func awaitBoundedCallback<Value: Sendable>(
    timeout: TimeInterval,
    onLate: (@Sendable (Value) -> Void)? = nil,
    _ register: (@escaping @Sendable (Value) -> Void) -> Void
) async -> BoundedCallbackOutcome<Value> {
    let gate = OneShotGate()
    return await withCheckedContinuation { (continuation: CheckedContinuation<BoundedCallbackOutcome<Value>, Never>) in
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, timeout)) {
            if gate.claim() {
                continuation.resume(returning: .timedOut)
            }
        }
        register { value in
            if gate.claim() {
                continuation.resume(returning: .completed(value))
            } else {
                onLate?(value)
            }
        }
    }
}

private final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// Returns `true` exactly once.
    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}

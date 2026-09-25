import XCTest
@testable import SplayCore

/// A framework callback that never fires must not hang Stop: the deadline wins,
/// and a callback that arrives late goes to `onLate` instead of the caller.
final class BoundedCallbackTests: XCTestCase {
    func testCallbackBeforeDeadlineCompletes() async {
        let outcome: BoundedCallbackOutcome<Int> = await awaitBoundedCallback(timeout: 5) { done in
            DispatchQueue.global().async { done(42) }
        }
        guard case .completed(let value) = outcome else {
            return XCTFail("expected completion, got \(outcome)")
        }
        XCTAssertEqual(value, 42)
    }

    func testSynchronousCallbackCompletes() async {
        let outcome: BoundedCallbackOutcome<Int> = await awaitBoundedCallback(timeout: 5) { done in
            done(7)
        }
        guard case .completed(7) = outcome else {
            return XCTFail("expected completion, got \(outcome)")
        }
    }

    func testCallbackThatNeverFiresTimesOut() async {
        let started = Date()
        let outcome: BoundedCallbackOutcome<Int> = await awaitBoundedCallback(timeout: 0.1) { _ in }
        guard case .timedOut = outcome else {
            return XCTFail("expected timeout, got \(outcome)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testLateCallbackGoesToOnLate() async {
        let late = expectation(description: "late callback delivered to onLate")
        let outcome: BoundedCallbackOutcome<Int> = await awaitBoundedCallback(
            timeout: 0.05,
            onLate: { value in
                XCTAssertEqual(value, 9)
                late.fulfill()
            }
        ) { done in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { done(9) }
        }
        guard case .timedOut = outcome else {
            return XCTFail("expected timeout, got \(outcome)")
        }
        await fulfillment(of: [late], timeout: 2)
    }
}

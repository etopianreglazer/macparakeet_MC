import XCTest
@testable import Splay

/// The recording meter's math (`SplayMeter`, `MeterEnvelope`) and the recording
/// face's hit geometry (bars = menu, timer = stop). Pure functions, no AppKit.
@MainActor
final class IslandMeterTests: XCTestCase {
    // MARK: Shaping — dead ≠ silent starts here: room hiss must stay flat.

    func testLevelsAtOrBelowTheGateStayFlat() {
        XCTAssertEqual(SplayMeter.shaped(0), 0)
        XCTAssertEqual(SplayMeter.shaped(SplayMeterTuning.gate), 0)
        XCTAssertEqual(SplayMeter.shaped(-1), 0)
    }

    func testShapingIsMonotonicAndClamped() {
        var previous = -1.0
        for step in 0...20 {
            let v = SplayMeter.shaped(Double(step) / 20)
            XCTAssertGreaterThanOrEqual(v, previous)
            XCTAssertLessThanOrEqual(v, 1)
            previous = v
        }
        XCTAssertEqual(SplayMeter.shaped(5), 1)
    }

    func testQuietSpeechStillMovesTheBars() {
        // A soft voice (micLevel ~0.15) should drive the meter well past a sliver.
        XCTAssertGreaterThan(SplayMeter.shaped(0.15), 0.35)
    }

    // MARK: Bar heights

    func testSilentMeterRestsAtSilentHeight() {
        for phase in [nil, 0.0, 1.3] as [Double?] {
            let heights = SplayMeter.barHeights(level: 0, phase: phase)
            XCTAssertEqual(heights.count, SplayMeterTuning.barCount)
            XCTAssertTrue(heights.allSatisfy { $0 == SplayMeterTuning.silentHeight })
        }
    }

    func testStillFullMeterPeaksInTheCentre() {
        let heights = SplayMeter.barHeights(level: 1, phase: nil)
        let centre = SplayMeterTuning.barCount / 2
        XCTAssertEqual(heights[centre], SplayMeterTuning.maxHeight)
        XCTAssertLessThan(heights[0], heights[centre])
        XCTAssertEqual(heights.first, heights.last)
        XCTAssertTrue(heights.allSatisfy { $0 >= SplayMeterTuning.silentHeight && $0 <= SplayMeterTuning.maxHeight })
    }

    // MARK: Envelope — fast up, short fall

    func testEnvelopeRisesFastAndFallsWithinHalfASecond() {
        let env = MeterEnvelope()
        var t = 100.0
        _ = env.advance(to: 0, at: t)
        for _ in 0..<6 { t += 1.0 / 60; _ = env.advance(to: 1, at: t) }   // 100 ms
        XCTAssertGreaterThan(env.level, 0.95)
        for _ in 0..<30 { t += 1.0 / 60; _ = env.advance(to: 0, at: t) }  // 500 ms
        XCTAssertLessThan(env.level, 0.1)
    }

    func testEnvelopeSurvivesAFrameGap() {
        let env = MeterEnvelope()
        _ = env.advance(to: 1, at: 10)
        // A 5 s stall (timeline paused) is clamped, not a NaN or an overshoot.
        let v = env.advance(to: 1, at: 15)
        XCTAssertTrue(v.isFinite)
        XCTAssertLessThanOrEqual(v, 1)
    }

    // MARK: Timer

    func testTimerFormat() {
        XCTAssertEqual(SplayIslandTimer.format(0), "0:00")
        XCTAssertEqual(SplayIslandTimer.format(4), "0:04")
        XCTAssertEqual(SplayIslandTimer.format(65), "1:05")
        XCTAssertEqual(SplayIslandTimer.format(3725), "62:05")
        XCTAssertEqual(SplayIslandTimer.format(-3), "0:00")
    }

    // MARK: Recording hit geometry

    func testRecordingTimerIsTheStopControlAndBarsOpenTheMenu() {
        for notchAttached in [false, true] {
            let pill = IslandLayout.pillRect(for: .recording, notchAttached: notchAttached)
            let y = pill.midY
            // The timer is right-aligned at the 14pt face padding; probe both ends of "0:04".
            for x in [pill.maxX - 16, pill.maxX - 14 - 26] {
                XCTAssertEqual(
                    IslandLayout.control(at: CGPoint(x: x, y: y), visual: .recording, notchAttached: notchAttached),
                    .stop, "x=\(x) notch=\(notchAttached)"
                )
            }
            // The bars (14pt pad, ~16pt wide) are no longer a card button; a
            // click there still stops (`clickAction`), it just doesn't pop.
            let barsX = pill.minX + 14 + SplayMeterTuning.width / 2
            XCTAssertEqual(
                IslandLayout.control(at: CGPoint(x: barsX, y: y), visual: .recording, notchAttached: notchAttached),
                .none
            )
            let stop = IslandLayout.controlRect(for: .recording, notchAttached: notchAttached)
            XCTAssertLessThanOrEqual(stop.maxX, pill.maxX)
        }
    }

    func testNonRecordingControlRectsAreUnchanged() {
        let pill = IslandLayout.pillRect(for: .done, notchAttached: false)
        let rect = IslandLayout.controlRect(for: .done, notchAttached: false)
        XCTAssertEqual(rect.width, IslandLayout.controlHitWidth)
        XCTAssertEqual(rect.midX, pill.maxX - 18)
    }
}

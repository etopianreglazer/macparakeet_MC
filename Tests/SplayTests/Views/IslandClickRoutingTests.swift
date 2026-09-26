import XCTest
import SplayViewModels
@testable import Splay

/// Click routing on the island tracker is pure geometry (`IslandLayout`), so the
/// rules are testable without AppKit. The island is an indicator with no mark
/// (owner, tuner round 2026-09-26): an idle click anywhere opens the card (the
/// fallback when the menu bar icon is hidden), a click on a running capture
/// stops it, the done pill opens the card.
final class IslandClickRoutingTests: XCTestCase {
    /// The revealed pill is wider than the nub, so without the reveal-aware
    /// gate a click on the part the user saw grow would be swallowed.
    func testRevealedPillEscapesDormantHitRect() {
        for notchAttached in [false, true] {
            let revealed = IslandLayout.hitRect(for: .idleHover, notchAttached: notchAttached)
            let dormant = IslandLayout.hitRect(for: .idleCollapsed, notchAttached: notchAttached)
            XCTAssertFalse(dormant.contains(revealed))
        }
    }

    func testRacingClickOnRevealedEdgeResolvesToRevealedPill() {
        for notchAttached in [false, true] {
            let revealed = IslandLayout.hitRect(for: .idleHover, notchAttached: notchAttached)
            let point = CGPoint(x: revealed.minX + 3, y: revealed.midY)
            let visual = IslandLayout.clickVisual(
                for: .idleCollapsed, at: point,
                notchAttached: notchAttached, recentlyRevealed: true
            )
            XCTAssertEqual(visual, .idleHover)
            XCTAssertTrue(IslandLayout.hitRect(for: visual, notchAttached: notchAttached).contains(point))
            XCTAssertEqual(IslandLayout.clickAction(visual: visual, control: .none), .openCard)
        }
    }

    func testColdDormantClickIsNeverRerouted() {
        let dormant = IslandLayout.hitRect(for: .idleCollapsed, notchAttached: false)
        let point = CGPoint(x: dormant.midX, y: dormant.midY)
        let visual = IslandLayout.clickVisual(
            for: .idleCollapsed, at: point, notchAttached: false, recentlyRevealed: false
        )
        XCTAssertEqual(visual, .idleCollapsed)
        XCTAssertEqual(IslandLayout.clickAction(visual: visual, control: .none), .openCard)
    }

    func testClickOutsideRevealedGeometryStaysDormant() {
        let revealed = IslandLayout.hitRect(for: .idleHover, notchAttached: false)
        let outside = CGPoint(x: revealed.minX - 10, y: revealed.midY)
        let visual = IslandLayout.clickVisual(
            for: .idleCollapsed, at: outside, notchAttached: false, recentlyRevealed: true
        )
        XCTAssertEqual(visual, .idleCollapsed)
        XCTAssertFalse(IslandLayout.hitRect(for: visual, notchAttached: false).contains(outside))
    }

    func testNonIdleVisualsAreNeverRerouted() {
        let revealed = IslandLayout.hitRect(for: .idleHover, notchAttached: false)
        let point = CGPoint(x: revealed.midX, y: revealed.midY)
        for visual in [IslandVisual.recording, .transcribing, .done, .idleHover] {
            XCTAssertEqual(
                IslandLayout.clickVisual(for: visual, at: point, notchAttached: false, recentlyRevealed: true),
                visual
            )
        }
    }

    func testIdleIslandHasNoControlsToPop() {
        for notchAttached in [false, true] {
            for visual in [IslandVisual.idleCollapsed, .idleHover] {
                let rect = IslandLayout.hitRect(for: visual, notchAttached: notchAttached)
                for x in stride(from: rect.minX + 1, to: rect.maxX, by: 8) {
                    let p = CGPoint(x: x, y: rect.midY)
                    XCTAssertEqual(IslandLayout.control(at: p, visual: visual, notchAttached: notchAttached), .none)
                }
            }
        }
    }

    func testRecordingStopsFromTheTimerAndTheWholeBar() {
        for notchAttached in [false, true] {
            let stop = IslandLayout.controlRect(for: .recording, notchAttached: notchAttached)
            XCTAssertEqual(
                IslandLayout.control(at: CGPoint(x: stop.midX, y: stop.midY), visual: .recording, notchAttached: notchAttached),
                .stop
            )
            // The left meter is no longer a card button.
            let pill = IslandLayout.hitRect(for: .recording, notchAttached: notchAttached)
            XCTAssertEqual(
                IslandLayout.control(at: CGPoint(x: pill.minX + 20, y: pill.midY), visual: .recording, notchAttached: notchAttached),
                .none
            )
        }
        XCTAssertEqual(IslandLayout.clickAction(visual: .recording, control: .none), .stop)
        XCTAssertEqual(IslandLayout.clickAction(visual: .recording, control: .stop), .stop)
    }

    func testTranscribingIgnoresClicksAndDoneOpensTheCard() {
        let pill = IslandLayout.hitRect(for: .transcribing, notchAttached: false)
        XCTAssertEqual(
            IslandLayout.control(at: CGPoint(x: pill.minX + 20, y: pill.midY), visual: .transcribing, notchAttached: false),
            .none
        )
        XCTAssertEqual(IslandLayout.clickAction(visual: .transcribing, control: .none), .none)
        XCTAssertEqual(IslandLayout.clickAction(visual: .done, control: .none), .openCard)
        XCTAssertEqual(IslandLayout.clickAction(visual: .done, control: .open), .openCard)
        XCTAssertEqual(IslandLayout.clickAction(visual: .hidden, control: .none), .none)
    }
}

import XCTest
@testable import Splay

/// Click routing on the island tracker is pure geometry (`IslandLayout`), so the
/// hover-race rule is testable without AppKit: a click aimed at the *revealed*
/// pill resolves against the revealed geometry while hover is (or was just)
/// active — and a cold dormant click is never rerouted, keeping the resting
/// nub's click-anywhere-records behavior and its pass-through surroundings.
final class IslandClickRoutingTests: XCTestCase {
    /// Documents the bug the rule fixes: the revealed mark region is NOT fully
    /// contained in the dormant nub's hit rect, so without the reveal-aware
    /// gate + router a racing mark click is silently swallowed or misrouted.
    func testRevealedMarkRegionEscapesDormantHitRect() {
        for notchAttached in [false, true] {
            let mark = IslandLayout.markRect(for: .idleHover, notchAttached: notchAttached)
            let dormant = IslandLayout.hitRect(for: .idleCollapsed, notchAttached: notchAttached)
            XCTAssertFalse(
                dormant.contains(mark),
                "if the nub ever grows to cover the revealed mark, clickVisual's rule is redundant"
            )
        }
    }

    func testRacingClickOnRevealedMarkResolvesToMenu() {
        for notchAttached in [false, true] {
            let mark = IslandLayout.markRect(for: .idleHover, notchAttached: notchAttached)
            let point = CGPoint(x: mark.midX, y: mark.midY)

            let visual = IslandLayout.clickVisual(
                for: .idleCollapsed, at: point,
                notchAttached: notchAttached, recentlyRevealed: true
            )
            XCTAssertEqual(visual, .idleHover)
            XCTAssertTrue(IslandLayout.hitRect(for: visual, notchAttached: notchAttached).contains(point))
            XCTAssertEqual(IslandLayout.control(at: point, visual: visual, notchAttached: notchAttached), .menu)
        }
    }

    func testRacingClickOnRevealedRecordDotResolvesToRecord() {
        let dot = IslandLayout.controlRect(for: .idleHover, notchAttached: false)
        let point = CGPoint(x: dot.midX, y: dot.midY)

        let visual = IslandLayout.clickVisual(
            for: .idleCollapsed, at: point, notchAttached: false, recentlyRevealed: true
        )
        XCTAssertEqual(visual, .idleHover)
        XCTAssertEqual(IslandLayout.control(at: point, visual: visual, notchAttached: false), .record)
    }

    /// A cold dormant click (no recent hover) must never be rerouted — a click
    /// on the resting nub records, even where the revealed mark would overlap
    /// it. This is the previously-fixed "dormant nub click opened the card"
    /// bug staying fixed.
    func testColdDormantClickIsNeverRerouted() {
        let mark = IslandLayout.markRect(for: .idleHover, notchAttached: false)
        let dormant = IslandLayout.hitRect(for: .idleCollapsed, notchAttached: false)
        let overlap = mark.intersection(dormant)
        XCTAssertFalse(overlap.isEmpty, "geometry drifted: mark no longer overlaps the nub")
        let point = CGPoint(x: overlap.midX, y: overlap.midY)

        let visual = IslandLayout.clickVisual(
            for: .idleCollapsed, at: point, notchAttached: false, recentlyRevealed: false
        )
        XCTAssertEqual(visual, .idleCollapsed)
        XCTAssertEqual(IslandLayout.control(at: point, visual: visual, notchAttached: false), .none)
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
        let mark = IslandLayout.markRect(for: .idleHover, notchAttached: false)
        let point = CGPoint(x: mark.midX, y: mark.midY)

        for visual in [IslandVisual.recording, .transcribing, .done, .idleHover] {
            XCTAssertEqual(
                IslandLayout.clickVisual(for: visual, at: point, notchAttached: false, recentlyRevealed: true),
                visual
            )
        }
    }
}

import XCTest
@testable import Splay

final class IslandPlacementTests: XCTestCase {
    func testAutomaticUsesNotchOnlyWithPublicTopSafeArea() {
        XCTAssertEqual(IslandPlacementPreference.resolved(.automatic, safeAreaTop: 32), .notch)
        XCTAssertEqual(IslandPlacementPreference.resolved(.automatic, safeAreaTop: 0), .bottom)
        XCTAssertEqual(IslandPlacementPreference.resolved(.notch, safeAreaTop: 0), .bottom)
    }

    func testNotchOriginIsCenteredAndLiftedIntoSafeArea() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let size = CGSize(width: 520, height: 460)
        let notch = IslandPlacementPreference.panelOrigin(screenFrame: screen, visibleFrame: visible, safeAreaTop: 32, panelSize: size, preference: .automatic)
        let bottom = IslandPlacementPreference.panelOrigin(screenFrame: screen, visibleFrame: visible, safeAreaTop: 0, panelSize: size, preference: .automatic)
        XCTAssertEqual(notch.x, 496)
        XCTAssertEqual(notch.y, 530)
        XCTAssertEqual(bottom.y, 480)
    }
}

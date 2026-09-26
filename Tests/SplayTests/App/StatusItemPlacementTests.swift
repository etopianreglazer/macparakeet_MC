import XCTest
@testable import Splay

@MainActor
final class StatusItemPlacementTests: XCTestCase {
    // Positions are points from the screen's right edge (AppKit's
    // "NSStatusItem Preferred Position" defaults value).
    func testPositionBehindTheNotchIsMovedRightOfIt() {
        // 1728pt built-in screen, 774pt of menu bar right of the notch; the
        // item was remembered at 781 → x≈947, under the camera.
        XCTAssertEqual(MenuBarCoordinator.correctedStatusItemPosition(stored: 781, rightOfNotchWidth: 774), 387)
    }

    func testNoRememberedPositionOnANotchedScreenStartsRightOfIt() {
        XCTAssertEqual(MenuBarCoordinator.correctedStatusItemPosition(stored: nil, rightOfNotchWidth: 774), 387)
    }

    func testAVisiblePositionTheUserChoseIsKept() {
        XCTAssertNil(MenuBarCoordinator.correctedStatusItemPosition(stored: 400, rightOfNotchWidth: 774))
    }

    func testNoNotchMeansNoCorrection() {
        XCTAssertNil(MenuBarCoordinator.correctedStatusItemPosition(stored: 781, rightOfNotchWidth: nil))
    }
}

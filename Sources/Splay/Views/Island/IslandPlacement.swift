import AppKit
import Foundation

enum IslandPlacementPreference: String, CaseIterable, Identifiable {
    case automatic
    case notch
    case bottom

    static let defaultsKey = "splay.islandPlacement"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .notch: return "Notch"
        case .bottom: return "Below menu bar"
        }
    }

    static func resolved(_ preference: IslandPlacementPreference, safeAreaTop: CGFloat, hasAuxiliaryTopArea: Bool = false, isBuiltIn: Bool = false) -> IslandPlacementPreference {
        let supportsNotchRest = safeAreaTop > 0 || hasAuxiliaryTopArea || isBuiltIn
        switch preference {
        case .automatic: return supportsNotchRest ? .notch : .bottom
        case .notch: return supportsNotchRest ? .notch : .bottom
        case .bottom: return .bottom
        }
    }

    static func panelOrigin(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat, panelSize: CGSize, preference: IslandPlacementPreference) -> CGPoint {
        let resolved = resolved(preference, safeAreaTop: safeAreaTop)
        let x = screenFrame.midX - panelSize.width / 2
        // In Notch mode, lift the stage eight points into the public safe area:
        // its idle top edge is physically occluded, while the 30pt hit target
        // remains below the cut-out. The broad panel itself remains pass-through.
        let y = resolved == .notch
            ? screenFrame.maxY - panelSize.height + 8
            : visibleFrame.maxY - panelSize.height - 10
        return CGPoint(x: x, y: y)
    }
    static func cameraHousing(screenFrame: CGRect, safeAreaTop: CGFloat, left: CGRect?, right: CGRect?) -> CGRect {
        if let left, let right, right.minX > left.maxX {
            return CGRect(x: left.maxX, y: screenFrame.maxY - max(safeAreaTop, left.height, right.height), width: right.minX - left.maxX, height: max(safeAreaTop, left.height, right.height))
        }
        let height = max(safeAreaTop, 32)
        return CGRect(x: screenFrame.midX - 90, y: screenFrame.maxY - height, width: 180, height: height)
    }
}

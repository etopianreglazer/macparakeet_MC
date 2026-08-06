import SwiftUI

/// All user-facing island content lives in this one router. The top-center
/// pill is `.idle`; every other destination is rendered by the same long-lived
/// `IslandPanel` as an expanded state, never by a second panel or main window.
@MainActor
@Observable
final class IslandRouteModel {
    enum Route: Equatable {
        case idle
        case home
        case library
        case settings
        case transcript(UUID)
    }

    var route: Route = .idle

    var isExpanded: Bool { route != .idle }

    func open(_ route: Route) { self.route = route }
    func close() { route = .idle }
    func back() { route = .home }
}

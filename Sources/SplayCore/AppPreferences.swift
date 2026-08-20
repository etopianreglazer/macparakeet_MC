import Foundation

public enum AppPreferences {
    public static let appearanceModeKey = "appearanceMode"
    public static let menuBarOnlyModeKey = "menuBarOnlyMode"
    public static let telemetryEnabledKey = "telemetryEnabled"

    public static func appearanceMode(defaults: UserDefaults = .standard) -> AppAppearanceMode {
        AppAppearanceMode.current(defaults: defaults)
    }

    public static func isMenuBarOnlyModeEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: menuBarOnlyModeKey) as? Bool ?? false
    }

    /// Telemetry is **opt-in** in Splay, not opt-out as it is upstream. The reporting
    /// endpoint this code still targets is upstream MacParakeet's server, so a default
    /// of `true` would have every Splay install report into another project's
    /// infrastructure. Nothing is sent unless the user explicitly turns this on — and
    /// before it can be turned on meaningfully, the endpoint has to become Splay's own
    /// or the reporting has to be removed. See docs/launch-checklist.md (A4).
    public static func isTelemetryEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: telemetryEnabledKey) as? Bool ?? false
    }
}

public enum AppAppearanceMode: String, CaseIterable, Hashable, Sendable {
    case system
    case light
    case dark

    public var displayTitle: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    public var detail: String {
        switch self {
        case .system:
            return "Follow your macOS appearance."
        case .light:
            return "Keep MacParakeet in light mode."
        case .dark:
            return "Keep MacParakeet in dark mode."
        }
    }

    public static func current(defaults: UserDefaults = .standard) -> AppAppearanceMode {
        guard let raw = defaults.string(forKey: AppPreferences.appearanceModeKey),
              let mode = AppAppearanceMode(rawValue: raw) else {
            return .system
        }
        return mode
    }
}

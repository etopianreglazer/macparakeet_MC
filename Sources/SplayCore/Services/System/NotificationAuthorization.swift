import Foundation
import OSLog
import UserNotifications

/// User-facing notifications rely on `UNUserNotificationCenter`. Without a prior
/// `requestAuthorization` call, macOS silently drops every notification we post —
/// the user sees nothing and concludes the feature is broken. This helper
/// centralizes the request so every caller flows through one path.
public enum NotificationAuthorization {
    private static let logger = Logger(subsystem: "com.macparakeet", category: "Notifications")

    /// `UNUserNotificationCenter.current()` requires a host bundle with a
    /// proper `bundleIdentifier` and crashes inside `xctest` (the test
    /// helper has no UN-eligible bundle). This guard makes the helper
    /// safe to call from anywhere — production paths are unaffected
    /// because the app bundle always has an identifier.
    private static var isHostBundleEligible: Bool {
        Bundle.main.bundleIdentifier?.isEmpty == false
            && Bundle.main.bundleIdentifier?.hasPrefix("com.apple.dt.xctest") == false
    }

    /// Request `.alert` authorization (no `.sound` — notifications are
    /// silent by design so they don't fight the user's own audio). No-op
    /// when status is already `.authorized` or `.provisional`.
    @discardableResult
    public static func requestIfNeeded() async -> Bool {
        guard isHostBundleEligible else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            logger.warning("Notification authorization previously denied — notifications will not deliver")
            return false
        case .notDetermined, .ephemeral:
            fallthrough
        @unknown default:
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                logger.info("Notification authorization request \(granted ? "granted" : "denied", privacy: .public)")
                return granted
            } catch {
                logger.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }

    /// Cheap status check callers can use before posting a notification.
    public static func isAuthorized() async -> Bool {
        guard isHostBundleEligible else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        default: return false
        }
    }
}

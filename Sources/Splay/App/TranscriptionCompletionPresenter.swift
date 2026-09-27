import AppKit
import SplayCore
import SplayViewModels
import OSLog
import UserNotifications

/// Turns a file job's outcome into what the user hears and reads: a chime
/// (success) or the soft error sound (failure), plus a silent banner — shown
/// **even when Splay is frontmost** (the open panel just made it so), because
/// it is the only place that says where the transcript went or why it failed.
/// Clicking a banner reveals its transcript (or a batch's folder) in Finder.
/// See docs/plans/file-transcription-feedback.md.
///
/// Banners are silent (`content.sound = nil`) because `SoundManager` owns the
/// audible cue. Without notification permission only the sound and the island
/// remain.
@MainActor
enum TranscriptionCompletionPresenter {
    private static let logger = Logger(subsystem: "com.macparakeet", category: "TranscriptionNotifications")
    nonisolated static let revealPathKey = "splayRevealPath"

    enum Sound { case success, failure, none }

    static func present(_ content: TranscriptionCompletionNotifier.Content, sound: Sound = .success) {
        switch sound {
        case .success: SoundManager.shared.play(.transcriptionComplete)
        case .failure: SoundManager.shared.play(.errorSoft)
        case .none: break
        }
        postBanner(content)
    }

    private static func postBanner(_ content: TranscriptionCompletionNotifier.Content) {
        SplayNotificationDelegate.installIfNeeded()
        Task {
            guard await NotificationAuthorization.requestIfNeeded() else {
                logger.info("Banner skipped — notifications not authorized")
                return
            }
            let notification = UNMutableNotificationContent()
            notification.title = content.title
            notification.body = content.body
            notification.sound = nil  // SoundManager owns the audible cue
            if let reveal = content.revealURL {
                notification.userInfo = [revealPathKey: reveal.path]
            }
            let request = UNNotificationRequest(
                identifier: "macparakeet.transcription.\(UUID().uuidString)",
                content: notification,
                trigger: nil  // Deliver immediately
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                logger.error("Banner failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Shows Splay's banners while Splay is frontmost and reveals the saved
/// transcript when one is clicked.
final class SplayNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private static let shared = SplayNotificationDelegate()
    @MainActor private static var installed = false

    @MainActor static func installIfNeeded() {
        guard !installed, Bundle.main.bundleIdentifier?.isEmpty == false else { return }
        installed = true
        UNUserNotificationCenter.current().delegate = shared
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let path = response.notification.request.content.userInfo[TranscriptionCompletionPresenter.revealPathKey] as? String
        DispatchQueue.main.async {
            if let path { Self.reveal(URL(fileURLWithPath: path)) }
            completionHandler()
        }
    }

    /// A transcript is selected in its folder; a folder (a batch) is opened.
    private static func reveal(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

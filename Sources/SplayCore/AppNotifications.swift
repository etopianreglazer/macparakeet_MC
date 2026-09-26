import Foundation

public extension Notification.Name {
    static let macParakeetOpenOnboarding = Notification.Name("macparakeet.openOnboarding")
    static let macParakeetHotkeyTriggerDidChange = Notification.Name("macparakeet.hotkeyTriggerDidChange")
    static let macParakeetPushToTalkHotkeyTriggerDidChange = Notification.Name("macparakeet.pushToTalkHotkeyTriggerDidChange")
    static let macParakeetMeetingHotkeyTriggerDidChange = Notification.Name("macparakeet.meetingHotkeyTriggerDidChange")
    static let macParakeetFileTranscriptionHotkeyTriggerDidChange = Notification.Name("macparakeet.fileTranscriptionHotkeyTriggerDidChange")
    static let macParakeetAppearanceModeDidChange = Notification.Name("macparakeet.appearanceModeDidChange")
    static let macParakeetMenuBarOnlyModeDidChange = Notification.Name("macparakeet.menuBarOnlyModeDidChange")
    static let macParakeetShowIdlePillDidChange = Notification.Name("macparakeet.showIdlePillDidChange")
    /// Posted by the Mac mic platform when the input route may have changed
    /// (upstream MacParakeet v0.8.7). Nothing in Splay observes it yet.
    static let macParakeetMicrophoneSelectionDidChange = Notification.Name("macparakeet.microphoneSelectionDidChange")
}

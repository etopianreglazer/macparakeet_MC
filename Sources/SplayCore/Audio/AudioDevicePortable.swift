import Foundation

// Cross-platform slice of the Core Audio device model. The HAL itself
// (`AudioDeviceManager` proper, `AudioObject*`) is macOS-only; iOS routes input
// through AVAudioSession and never resolves a device ID. What both platforms
// share is the persisted-UID normalisation and the `AudioDeviceID` spelling
// that `MeetingInputDeviceAttempt` carries for API parity.
// See docs/plans/splay-ios-utility-layer.md (slice 1).

#if !os(macOS)
/// `AudioDeviceID` (a `UInt32` `AudioObjectID`) is declared by Core Audio's
/// HAL headers, which the iOS SDK does not ship. The device-attempt chain is
/// always empty on iOS, so no value of this type is ever meaningful there.
public typealias AudioDeviceID = UInt32

public enum AudioDeviceManager {}
#endif

extension AudioDeviceManager {
    /// Normalizes persisted CoreAudio device UIDs, treating nil and whitespace as absent.
    public static func normalizedUID(_ uid: String?) -> String? {
        let trimmed = uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

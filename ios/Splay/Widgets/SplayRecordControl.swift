import AppIntents
import SwiftUI
import WidgetKit

/// The Control Center control. Assign it to the Action Button (Settings ›
/// Action Button › Controls › Splay) and the button becomes: press to record,
/// press to stop. It runs `ToggleRecordingIntent` in the app process; the
/// Live Activity the intent starts is what lets iOS record in the background.
struct SplayRecordControl: ControlWidget {
    static let kind = "com.macparakeet.mc.ios.record"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleRecordingIntent()) {
                Label("Record", systemImage: "record.circle")
            }
        }
        .displayName("Splay")
        .description("Record and transcribe on this phone.")
    }
}

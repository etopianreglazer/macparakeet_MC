import SwiftUI
import WidgetKit

@main
struct SplayWidgetBundle: WidgetBundle {
    var body: some Widget {
        SplayLiveActivity()
        SplayRecordControl()
    }
}

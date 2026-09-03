import SwiftUI
import WidgetKit

/// MarginRun's widget extension.
///
/// It carries exactly one member: the Labor Timer Live Activity. No Home
/// Screen or Lock Screen widgets are declared here, because nothing else in
/// MarginRun has a live surface worth showing outside the app.
@main
struct MarginRunWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LaborTimerLiveActivity()
    }
}

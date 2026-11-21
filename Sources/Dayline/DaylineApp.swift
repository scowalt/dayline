import DaylineKit
import SwiftUI

@main
struct DaylineApp: App {
    @State private var model = AppModel(launchArguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task { await model.start() }
        }
        .backgroundTask(.appRefresh(AppModel.drainTaskIdentifier)) {
            await model.drainInBackground()
        }
    }
}

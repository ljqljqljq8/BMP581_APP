import SwiftUI

@main
struct AirPressureApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(appModel)
        }
    }
}

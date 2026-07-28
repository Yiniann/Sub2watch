import SwiftUI

@main
struct Sub2WatchApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.configuration == nil && !model.isDemoMode {
                SetupView(mode: .initial)
            } else {
                DashboardView()
            }
        }
    }
}

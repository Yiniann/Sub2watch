import SwiftUI

@main
struct Sub2WatchPhoneApp: App {
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        PhoneBackgroundRefreshCoordinator.shared.register(model: model)
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(model)
        }
    }
}

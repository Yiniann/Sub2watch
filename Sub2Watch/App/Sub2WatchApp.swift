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
            if !model.hasUsableConfiguration {
                PhoneSyncWaitingView()
            } else {
                DashboardView()
            }
        }
    }
}

private struct PhoneSyncWaitingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: model.isCompanionReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(model.isCompanionReachable ? .blue : .secondary)

                Text("请在 iPhone 配置")
                    .font(.headline)

                Text("登录并刷新后，额度会自动同步到手表")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    model.requestPhoneRefresh()
                } label: {
                    Label("同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .navigationTitle("Sub2Watch")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

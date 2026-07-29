import SwiftUI

struct PhoneRootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.configuration == nil && !model.isDemoMode {
                PhoneSetupView()
            } else {
                PhoneDashboardView()
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.refreshDashboardIfStale(olderThan: 2 * 60)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                await model.refreshDashboard()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                PhoneBackgroundRefreshCoordinator.shared.schedule()
            }
        }
    }
}

private struct PhoneSetupView: View {
    private enum AuthenticationChoice: String, CaseIterable, Identifiable {
        case account
        case adminKey

        var id: String { rawValue }
        var title: String { self == .account ? "账号" : "管理密钥" }
    }

    @EnvironmentObject private var model: AppModel
    @State private var baseURL = "https://"
    @State private var authenticationChoice: AuthenticationChoice = .account
    @State private var email = ""
    @State private var password = ""
    @State private var adminAPIKey = ""
    @State private var twoFactorCode = ""
    @State private var allowsInsecureHTTP = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sub2API 服务") {
                    TextField("https://example.com", text: $baseURL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    if usesHTTP {
                        Toggle("允许不安全的 HTTP", isOn: $allowsInsecureHTTP)
                    }
                }

                if model.pendingTwoFactorEmail == nil {
                    Section("登录方式") {
                        Picker("登录方式", selection: $authenticationChoice) {
                            ForEach(AuthenticationChoice.allCases) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)

                        if authenticationChoice == .account {
                            TextField("邮箱", text: $email)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                            SecureField("密码", text: $password)
                                .textContentType(.password)
                        } else {
                            SecureField("管理员密钥", text: $adminAPIKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } else {
                    Section("安全验证") {
                        if let maskedEmail = model.pendingTwoFactorEmail {
                            Label(maskedEmail, systemImage: "envelope.badge.shield.half.filled")
                                .foregroundStyle(.secondary)
                        }
                        TextField("6 位验证码", text: $twoFactorCode)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)

                        Button("返回登录") {
                            twoFactorCode = ""
                            model.cancelTwoFactorLogin()
                        }
                    }
                }

                if let error = model.connectionError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if model.isConnecting {
                                ProgressView()
                            } else {
                                Label(actionTitle, systemImage: "arrow.right.circle.fill")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit || model.isConnecting)
                }
            }
            .navigationTitle("Sub2Watch")
        }
    }

    private func submit() {
        Task {
            let saved: Bool
            if model.pendingTwoFactorEmail != nil {
                saved = await model.completeTwoFactorLogin(code: twoFactorCode)
            } else if authenticationChoice == .adminKey {
                saved = await model.connectAndSave(
                    baseURL: baseURL,
                    adminAPIKey: adminAPIKey,
                    allowsInsecureHTTP: allowsInsecureHTTP
                )
            } else {
                saved = await model.loginAndSave(
                    baseURL: baseURL,
                    email: email,
                    password: password,
                    allowsInsecureHTTP: allowsInsecureHTTP
                )
            }
            if saved {
                password = ""
                adminAPIKey = ""
                await model.refreshDashboard()
            }
        }
    }

    private var usesHTTP: Bool {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("http://")
    }

    private var canSubmit: Bool {
        if model.pendingTwoFactorEmail != nil {
            return twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines).count == 6
        }
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host() != nil,
              scheme != "http" || allowsInsecureHTTP else { return false }
        if authenticationChoice == .adminKey {
            return !adminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var actionTitle: String {
        model.pendingTwoFactorEmail == nil ? "登录并同步" : "验证并同步"
    }
}

struct PhoneSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsDisconnectConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("连接") {
                    LabeledContent("服务器", value: model.configuration?.apiBaseURL.host() ?? "-")
                    LabeledContent("登录", value: model.signedInUser?.email ?? "管理员密钥")
                }

                Section("Apple Watch") {
                    Label(
                        model.isCompanionReachable ? "当前可达" : "数据会在系统允许时后台同步",
                        systemImage: model.isCompanionReachable ? "checkmark.circle.fill" : "clock.arrow.circlepath"
                    )
                    .foregroundStyle(model.isCompanionReachable ? .green : .secondary)
                }

                Section {
                    Button("退出并清除凭据", role: .destructive) {
                        showsDisconnectConfirmation = true
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog(
                "退出并清除凭据",
                isPresented: $showsDisconnectConfirmation,
                titleVisibility: .visible
            ) {
                Button("退出", role: .destructive) {
                    model.disconnect()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

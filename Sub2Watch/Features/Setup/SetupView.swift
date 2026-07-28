import SwiftUI

struct SetupView: View {
    private enum AuthenticationChoice: String, CaseIterable, Identifiable {
        case account
        case adminKey

        var id: String { rawValue }
        var title: String { self == .account ? "账号" : "管理密钥" }
        var systemImage: String {
            self == .account ? "person.crop.circle.fill" : "key.fill"
        }
    }

    enum Mode {
        case initial
        case settings
    }

    let mode: Mode

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = "https://"
    @State private var authenticationChoice: AuthenticationChoice = .account
    @State private var email = ""
    @State private var password = ""
    @State private var twoFactorCode = ""
    @State private var adminAPIKey = ""
    @State private var allowsInsecureHTTP = false
    @State private var showsAuthenticationChoice = false
    @State private var showsCredentialEntry = false
    @State private var opensCredentialEntryOnAppear = false
    @State private var showsDisconnectConfirmation = false

    init(mode: Mode) {
        self.mode = mode
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let storedBaseURL = UserDefaults.standard.string(forKey: "debug-setup-base-url")
        let initialBaseURL = environment["SUB2WATCH_BASE_URL"] ?? storedBaseURL ?? "https://"
        _baseURL = State(initialValue: initialBaseURL)
        _adminAPIKey = State(initialValue: environment["SUB2WATCH_ADMIN_KEY"] ?? "")
        _allowsInsecureHTTP = State(initialValue: initialBaseURL.lowercased().hasPrefix("http://"))
        let setupStep = environment["SUB2WATCH_SETUP_STEP"]
        _showsAuthenticationChoice = State(
            initialValue: setupStep == "authentication" || setupStep == "credentials"
        )
        _opensCredentialEntryOnAppear = State(initialValue: setupStep == "credentials")
#endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if mode == .initial {
                    connectionEditor
                } else {
                    settingsList
                }
            }
            .onAppear {
                loadExistingConfiguration()
            }
#if DEBUG
            .onChange(of: baseURL) { _, value in
                UserDefaults.standard.set(value, forKey: "debug-setup-base-url")
            }
#endif
        }
    }

    private var connectionEditor: some View {
        List {
            Section("服务地址") {
                TextField("https://example.com", text: $baseURL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if usesHTTP {
                    Toggle("允许 HTTP", isOn: $allowsInsecureHTTP)

                    Label(
                        allowsInsecureHTTP ? "连接未加密" : "需要允许 HTTP",
                        systemImage: "exclamationmark.shield.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    model.connectionError = nil
                    showsAuthenticationChoice = true
                } label: {
                    HStack {
                        Spacer()
                        Label("下一步", systemImage: "arrow.right.circle.fill")
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinueFromServer)
                .listRowBackground(Color.clear)
            }

#if DEBUG
            if mode == .initial {
                demoSection
            }
#endif
        }
        .navigationTitle(mode == .initial ? "Sub2Watch" : "服务地址")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsAuthenticationChoice) {
            authenticationEditor
        }
        .onChange(of: showsAuthenticationChoice) { _, isPresented in
            if !isPresented {
                showsCredentialEntry = false
                cancelPendingTwoFactorLogin()
            }
        }
    }

    private var authenticationEditor: some View {
        List {
            Section("登录方式") {
                ForEach(AuthenticationChoice.allCases) { choice in
                    Button {
                        authenticationChoice = choice
                    } label: {
                        HStack {
                            Label(choice.title, systemImage: choice.systemImage)
                            Spacer()
                            if authenticationChoice == choice {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        authenticationChoice == choice ? .isSelected : []
                    )
                }
            }

            Section {
                Button {
                    model.connectionError = nil
                    showsCredentialEntry = true
                } label: {
                    HStack {
                        Spacer()
                        Label("下一步", systemImage: "arrow.right.circle.fill")
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("登录方式")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsCredentialEntry) {
            credentialsEditor
        }
        .onAppear {
            if opensCredentialEntryOnAppear {
                opensCredentialEntryOnAppear = false
                showsCredentialEntry = true
            }
        }
        .onChange(of: showsCredentialEntry) { _, isPresented in
            if !isPresented {
                cancelPendingTwoFactorLogin()
            }
        }
        .onChange(of: authenticationChoice) { _, _ in
            model.connectionError = nil
        }
    }

    private var credentialsEditor: some View {
        List {
            if let maskedEmail = model.pendingTwoFactorEmail {
                Section("安全验证") {
                    Label(maskedEmail, systemImage: "envelope.badge.shield.half.filled")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField("6 位验证码", text: $twoFactorCode)
                        .textContentType(.oneTimeCode)

                    Button {
                        twoFactorCode = ""
                        model.cancelTwoFactorLogin()
                    } label: {
                        Label("返回登录", systemImage: "chevron.left")
                    }
                }
            } else if authenticationChoice == .account {
                Section("账号登录") {
                    TextField("邮箱", text: $email)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } else {
                Section("管理密钥") {
                    SecureField("管理员密钥", text: $adminAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if let error = model.connectionError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    submitConnection()
                } label: {
                    HStack {
                        Spacer()
                        if model.isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(actionTitle, systemImage: "arrow.right.circle.fill")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || model.isConnecting)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(model.pendingTwoFactorEmail == nil ? "登录" : "安全验证")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settingsList: some View {
        List {
            Section("当前连接") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectionTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(authenticationSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: model.isDemoMode ? "play.rectangle.fill" : "server.rack")
                        .foregroundStyle(.blue)
                }

                NavigationLink {
                    connectionEditor
                } label: {
                    Label("修改连接", systemImage: "slider.horizontal.3")
                }
            }

            if model.isAdministrator {
                notificationSection
            }

#if DEBUG
            demoSection
#endif

            Section {
                Button(role: .destructive) {
                    showsDisconnectConfirmation = true
                } label: {
                    Label(disconnectTitle, systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("关闭设置")
            }
        }
        .confirmationDialog(
            disconnectTitle,
            isPresented: $showsDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button(disconnectTitle, role: .destructive) {
                model.disconnect()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机保存的连接信息将被移除")
        }
    }

    private var notificationSection: some View {
        Section("额度提醒") {
            Toggle(
                "重置后通知",
                isOn: Binding(
                    get: { model.quotaResetNotificationsEnabled },
                    set: { enabled in
                        Task {
                            await model.setQuotaResetNotificationsEnabled(enabled)
                        }
                    }
                )
            )

            if model.notificationAuthorizationStatus == .denied {
                Label("通知权限未开启", systemImage: "bell.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Label("额度恢复至 90% 时提醒", systemImage: "bell.badge.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

#if DEBUG
            Button {
                Task { await model.sendTestQuotaResetNotification() }
            } label: {
                Label("测试提醒", systemImage: "bell.badge.fill")
            }
#endif
        }
    }

#if DEBUG
    private var demoSection: some View {
        Section("开发") {
            Button {
                model.startDemo()
            } label: {
                Label("管理员模拟数据", systemImage: "chart.bar.xaxis")
            }
            Button {
                model.startUserDemo()
            } label: {
                Label("普通用户模拟数据", systemImage: "person.crop.circle")
            }
        }
    }
#endif

    private func cancelPendingTwoFactorLogin() {
        guard model.pendingTwoFactorEmail != nil else { return }
        twoFactorCode = ""
        model.cancelTwoFactorLogin()
    }

    private func submitConnection() {
        Task {
            let saved: Bool
            if authenticationChoice == .adminKey {
                saved = await model.connectAndSave(
                    baseURL: baseURL,
                    adminAPIKey: adminAPIKey,
                    allowsInsecureHTTP: allowsInsecureHTTP
                )
            } else if model.pendingTwoFactorEmail != nil {
                saved = await model.completeTwoFactorLogin(code: twoFactorCode)
            } else {
                saved = await model.loginAndSave(
                    baseURL: baseURL,
                    email: email,
                    password: password,
                    allowsInsecureHTTP: allowsInsecureHTTP
                )
            }
            if saved && mode == .settings {
                dismiss()
            }
        }
    }

    private func loadExistingConfiguration() {
        guard let configuration = model.configuration else { return }
        baseURL = configuration.apiBaseURL.absoluteString
            .replacingOccurrences(of: "/api/v1", with: "")
        allowsInsecureHTTP = configuration.allowsInsecureHTTP
        authenticationChoice = configuration.authenticationMode == .accountSession
            ? .account
            : .adminKey
        email = configuration.user?.email ?? ""
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
        guard canContinueFromServer else { return false }
        if authenticationChoice == .adminKey {
            return !adminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var canContinueFromServer: Bool {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host() != nil else {
            return false
        }
        return scheme != "http" || allowsInsecureHTTP
    }

    private var connectionTitle: String {
        if model.isDemoMode { return "模拟数据" }
        guard let configuration = model.configuration else { return "未连接" }
        return configuration.apiBaseURL.host() ?? configuration.apiBaseURL.absoluteString
    }

    private var authenticationSummary: String {
        if model.isDemoMode {
            return model.isAdministrator ? "管理员模式" : "普通用户模式"
        }
        if let user = model.signedInUser {
            return user.email
        }
        return model.configuration?.authenticationMode == .adminAPIKey ? "管理密钥" : "账号登录"
    }

    private var disconnectTitle: String {
        if model.isDemoMode { return "退出模拟" }
        return model.configuration?.authenticationMode == .accountSession ? "退出登录" : "移除配置"
    }

    private var actionTitle: String {
        if model.pendingTwoFactorEmail != nil { return "验证并登录" }
        if mode == .settings { return "更新连接" }
        return authenticationChoice == .adminKey ? "连接" : "登录"
    }
}

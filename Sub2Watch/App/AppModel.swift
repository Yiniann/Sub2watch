import Foundation
import Combine
@preconcurrency import UserNotifications
@preconcurrency import Network
import WidgetKit

enum ModelStatsPeriod: String, CaseIterable, Identifiable {
    case last24Hours
    case today
    case yesterday
    case last7Days
    case last30Days
    case thisMonth
    case lastMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last24Hours: "近 24 小时"
        case .today: "今天"
        case .yesterday: "昨天"
        case .last7Days: "近 7 天"
        case .last30Days: "近 30 天"
        case .thisMonth: "本月"
        case .lastMonth: "上月"
        }
    }

    var trendGranularity: String {
        switch self {
        case .last24Hours, .today, .yesterday: "hour"
        case .last7Days, .last30Days, .thisMonth, .lastMonth: "day"
        }
    }

    func dateRange(now: Date = Date(), calendar: Calendar = .current) -> (start: String, end: String) {
        let today = calendar.startOfDay(for: now)
        let start: Date
        let end: Date

        switch self {
        case .last24Hours:
            start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            end = today
        case .today:
            start = today
            end = today
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            start = yesterday
            end = yesterday
        case .last7Days:
            start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            end = today
        case .last30Days:
            start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            end = today
        case .thisMonth:
            start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
            end = today
        case .lastMonth:
            let thisMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: today)
            ) ?? today
            start = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
            end = calendar.date(byAdding: .day, value: -1, to: thisMonth) ?? thisMonth
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: end))
    }
}

struct ProviderQuotaWindowSummary: Identifiable {
    let id: String
    let label: String
    let summary: AggregateQuotaWindow
    let metrics: UsageWindowMetrics?
}

struct ProviderQuotaGroup: Identifiable {
    let id: String
    let displayName: String
    let accounts: [CodexAccount]
    let reportingAccountCount: Int
    let queryableAccountCount: Int
    let windows: [ProviderQuotaWindowSummary]
}

@MainActor
final class AppModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
    }

    @Published private(set) var configuration: ServerConfiguration?
    @Published private(set) var accounts: [CodexAccount] = []
    @Published private(set) var liveSnapshots: [Int: AccountQuotaSnapshot] = [:]
    @Published private(set) var providerSnapshots: [Int: ProviderQuotaSnapshot] = [:]
    @Published private(set) var accountUsageWindows: [Int: AccountUsageWindows] = [:]
    @Published private(set) var usageStats: DashboardUsageStats?
    @Published private(set) var openAITokenStats: OpenAITokenStatsResponse?
    @Published private(set) var modelUsageStats: ModelUsageStatsResponse?
    @Published private(set) var usageTrend: UsageTrendResponse?
    @Published private(set) var userPlatformQuotas: [UserPlatformQuota] = []
    @Published private(set) var userAPIKeys: [UserAPIKey] = []
    @Published private(set) var userSubscriptions: [UserSubscriptionSummary] = []
    @Published private(set) var modelStatsPeriod: ModelStatsPeriod = .last24Hours
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var refreshingAccountIDs: Set<Int> = []
    @Published private(set) var isRefreshingUsage = false
    @Published private(set) var isRefreshingModelStats = false
    @Published var errorMessage: String?
    @Published var usageErrorMessage: String?
    @Published var modelStatsErrorMessage: String?
    @Published var usageTrendErrorMessage: String?
    @Published var connectionError: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var pendingTwoFactorEmail: String?
    @Published private(set) var isDemoMode = false
#if DEBUG
    @Published private(set) var demoSignedInUser: AuthenticatedUser?
#endif
    @Published private(set) var quotaResetNotificationsEnabled = true
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    private let client = Sub2APIClient()
    private let keychain = ConfigurationKeychain()
    private let cache = DashboardCacheStore()
    private let quotaResetNotifications = QuotaResetNotificationManager()
    private var etag: String?
    private var pendingTwoFactorToken: String?
    private var pendingTwoFactorBaseURL: URL?
    private var pendingTwoFactorAllowsHTTP = false
    private var refreshTask: Task<RefreshTokenResult, Error>?

    var isAdministrator: Bool {
#if DEBUG
        if demoSignedInUser != nil { return false }
#endif
        return configuration?.isAdministrator ?? true
    }
    var signedInUser: AuthenticatedUser? {
#if DEBUG
        demoSignedInUser ?? configuration?.user
#else
        configuration?.user
#endif
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: QuotaResetNotificationManager.enabledDefaultsKey) != nil {
            quotaResetNotificationsEnabled = defaults.bool(
                forKey: QuotaResetNotificationManager.enabledDefaultsKey
            )
        }
        configuration = try? keychain.load()
        if let configuration, let cached = cache.load(scope: configuration.cacheScopeIdentifier) {
            accounts = cached.accounts
            liveSnapshots = cached.liveSnapshots
            providerSnapshots = cached.providerSnapshots ?? [:]
            accountUsageWindows = cached.accountUsageWindows ?? [:]
            usageStats = cached.usageStats
            openAITokenStats = cached.openAITokenStats
            modelUsageStats = cached.modelUsageStats
            usageTrend = cached.usageTrend
            userPlatformQuotas = cached.userPlatformQuotas ?? []
            userAPIKeys = cached.userAPIKeys ?? []
            userSubscriptions = cached.userSubscriptions ?? []
            modelStatsPeriod = cached.modelStatsPeriodRawValue
                .flatMap(ModelStatsPeriod.init(rawValue:)) ?? .last24Hours
            etag = cached.accountScopeVersion == 2 ? cached.etag : nil
            loadState = accounts.isEmpty && configuration.isAdministrator ? .idle : .loaded
        }
#if DEBUG
        if ProcessInfo.processInfo.environment["SUB2WATCH_DEMO"] == "1" {
            configuration = nil
            isDemoMode = true
            seedDemoData()
        }
#endif
        if !accounts.isEmpty {
            persistWidgetSummary()
        }
    }

    func connectAndSave(
        baseURL: String,
        adminAPIKey: String,
        allowsInsecureHTTP: Bool
    ) async -> Bool {
        guard !isConnecting else { return false }
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        do {
            let candidate = try ServerConfiguration.validated(
                baseURLText: baseURL,
                adminAPIKey: adminAPIKey,
                allowsInsecureHTTP: allowsInsecureHTTP
            )
            let result = try await client.listAccounts(configuration: candidate)
            clearCurrentIdentityData()
            try keychain.save(candidate)
            configuration = candidate
            isDemoMode = false
            accounts = result.accounts ?? []
            liveSnapshots = liveSnapshots.filter { id, _ in
                accounts.contains(where: { $0.id == id })
            }
            providerSnapshots = providerSnapshots.filter { id, _ in
                accounts.contains(where: { $0.id == id })
            }
            accountUsageWindows = accountUsageWindows.filter { id, _ in
                accounts.contains(where: { $0.id == id })
            }
            etag = result.etag
            loadState = .loaded
            errorMessage = nil
            persistCache()
            await synchronizeQuotaResetNotifications()
            return true
        } catch {
            if let apiError = error as? Sub2APIError,
               case .transport = apiError {
                let diagnostic = await connectionDiagnostic()
                connectionError = "\(error.localizedDescription)\n\(diagnostic)"
            } else {
                connectionError = error.localizedDescription
            }
            return false
        }
    }

    func loginAndSave(
        baseURL: String,
        email: String,
        password: String,
        allowsInsecureHTTP: Bool
    ) async -> Bool {
        guard !isConnecting else { return false }
        isConnecting = true
        connectionError = nil
        pendingTwoFactorEmail = nil
        pendingTwoFactorToken = nil
        defer { isConnecting = false }

        do {
            let apiBaseURL = try ServerConfiguration.normalizedAPIBaseURL(
                baseURLText: baseURL,
                allowsInsecureHTTP: allowsInsecureHTTP
            )
            let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedEmail.isEmpty else { throw ConfigurationError.missingEmail }
            guard !password.isEmpty else { throw ConfigurationError.missingPassword }
            let result = try await client.login(
                apiBaseURL: apiBaseURL,
                email: normalizedEmail,
                password: password
            )
            if result.requires2FA {
                guard let token = result.tempToken else { throw Sub2APIError.invalidPayload }
                pendingTwoFactorToken = token
                pendingTwoFactorBaseURL = apiBaseURL
                pendingTwoFactorAllowsHTTP = allowsInsecureHTTP
                pendingTwoFactorEmail = result.userEmailMasked ?? normalizedEmail
                return false
            }
            try await adoptLoginResult(
                result,
                apiBaseURL: apiBaseURL,
                allowsInsecureHTTP: allowsInsecureHTTP
            )
            return true
        } catch {
            await reportConnectionError(error)
            return false
        }
    }

    func completeTwoFactorLogin(code: String) async -> Bool {
        guard !isConnecting,
              let token = pendingTwoFactorToken,
              let apiBaseURL = pendingTwoFactorBaseURL else { return false }
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }
        do {
            let result = try await client.completeTwoFactorLogin(
                apiBaseURL: apiBaseURL,
                temporaryToken: token,
                code: code.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try await adoptLoginResult(
                result,
                apiBaseURL: apiBaseURL,
                allowsInsecureHTTP: pendingTwoFactorAllowsHTTP
            )
            pendingTwoFactorToken = nil
            pendingTwoFactorBaseURL = nil
            pendingTwoFactorEmail = nil
            return true
        } catch {
            await reportConnectionError(error)
            return false
        }
    }

    func cancelTwoFactorLogin() {
        pendingTwoFactorEmail = nil
        pendingTwoFactorToken = nil
        pendingTwoFactorBaseURL = nil
        pendingTwoFactorAllowsHTTP = false
        connectionError = nil
    }

    private func adoptLoginResult(
        _ result: LoginResult,
        apiBaseURL: URL,
        allowsInsecureHTTP: Bool
    ) async throws {
        guard let accessToken = result.accessToken, let user = result.user else {
            throw Sub2APIError.invalidPayload
        }
        let candidate = ServerConfiguration(
            apiBaseURL: apiBaseURL,
            allowsInsecureHTTP: allowsInsecureHTTP,
            accessToken: accessToken,
            refreshToken: result.refreshToken,
            accessTokenExpiresAt: result.expiresIn.map {
                Date().addingTimeInterval(TimeInterval($0))
            },
            user: user
        )

        clearCurrentIdentityData()
        try keychain.save(candidate)
        configuration = candidate
        isDemoMode = false
        loadState = candidate.isAdministrator ? .idle : .loaded
        errorMessage = nil
        persistCache()
    }

    private func reportConnectionError(_ error: Error) async {
        if let apiError = error as? Sub2APIError, case .transport = apiError {
            connectionError = "\(error.localizedDescription)\n\(await connectionDiagnostic())"
        } else {
            connectionError = error.localizedDescription
        }
    }

    private func validConfiguration(forceRefresh: Bool = false) async -> ServerConfiguration? {
        guard let current = configuration else { return nil }
        guard current.authenticationMode == .accountSession else { return current }
        let expiresSoon = current.accessTokenExpiresAt.map {
            $0 <= Date().addingTimeInterval(60)
        } ?? false
        if !forceRefresh && !expiresSoon {
            return current
        }
        guard let refreshToken = current.refreshToken else {
            connectionError = "登录已过期，请重新登录"
            return nil
        }

        if refreshTask == nil {
            let client = client
            let apiBaseURL = current.apiBaseURL
            refreshTask = Task {
                try await client.refreshSession(
                    apiBaseURL: apiBaseURL,
                    refreshToken: refreshToken
                )
            }
        }
        guard let task = refreshTask else { return nil }
        do {
            let tokens = try await task.value
            refreshTask = nil
            guard configuration?.cacheScopeIdentifier == current.cacheScopeIdentifier else {
                return configuration
            }
            let refreshed = current.replacingTokens(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresIn: tokens.expiresIn
            )
            try keychain.save(refreshed)
            configuration = refreshed
            return refreshed
        } catch {
            refreshTask = nil
            connectionError = "登录续期失败：\(error.localizedDescription)"
            return nil
        }
    }

    private func authenticatedRequest<Value>(
        configuration initialConfiguration: ServerConfiguration,
        operation: (ServerConfiguration) async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation(initialConfiguration)
        } catch let error as Sub2APIError {
            guard case .unauthorized = error,
                  initialConfiguration.authenticationMode == .accountSession else {
                throw error
            }

            if let latest = configuration,
               latest.accessToken != initialConfiguration.accessToken {
                return try await operation(latest)
            }
            guard let refreshed = await validConfiguration(forceRefresh: true) else {
                throw error
            }
            return try await operation(refreshed)
        }
    }

    private func connectionDiagnostic() async -> String {
        async let path = networkPathSummary()
        async let apple = probeConnection(
            URL(string: "https://www.apple.com/library/test/success.html")!
        )
        async let cloudflare = probeConnection(
            URL(string: "https://1.1.1.1/cdn-cgi/trace")!
        )
        return await "网络：\(path)\nApple：\(apple) / Cloudflare：\(cloudflare)"
    }

    private func networkPathSummary() async -> String {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()

                let status: String
                switch path.status {
                case .satisfied: status = "可用"
                case .requiresConnection: status = "等待连接"
                case .unsatisfied: status = "不可用"
                @unknown default: status = "未知"
                }

                let interface: String
                if path.usesInterfaceType(.wifi) {
                    interface = "Wi-Fi"
                } else if path.usesInterfaceType(.cellular) {
                    interface = "蜂窝"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    interface = "有线"
                } else if path.usesInterfaceType(.loopback) {
                    interface = "回环"
                } else {
                    interface = "其他"
                }

                var capabilities: [String] = []
                if path.supportsIPv4 { capabilities.append("IPv4") }
                if path.supportsIPv6 { capabilities.append("IPv6") }
                if path.supportsDNS { capabilities.append("DNS") }
                let capabilityText = capabilities.isEmpty
                    ? "无 IP/DNS"
                    : capabilities.joined(separator: "/")
                continuation.resume(
                    returning: "\(status) · \(interface) · \(capabilityText)"
                )
            }
            monitor.start(queue: DispatchQueue(label: "Sub2Watch.NetworkPath"))
        }
    }

    private func probeConnection(_ url: URL) async -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { return "响应异常" }
            return "HTTP \(response.statusCode)"
        } catch let error as URLError {
            return "错误 \(error.code.rawValue)"
        } catch {
            return "失败"
        }
    }

    func refreshAccounts() async {
#if DEBUG
        if isDemoMode {
            loadState = .loading
            try? await Task.sleep(for: .milliseconds(350))
            if demoSignedInUser != nil {
                seedDemoUserData()
            } else {
                seedDemoData()
            }
            return
        }
#endif
        guard let configuration = await validConfiguration(), loadState != .loading else { return }
        if !configuration.isAdministrator {
            await refreshUserOwnedData(configuration: configuration)
            return
        }
        if accounts.isEmpty { loadState = .loading }
        errorMessage = nil
        defer { loadState = accounts.isEmpty ? .idle : .loaded }

        do {
            let result = try await authenticatedRequest(configuration: configuration) {
                try await client.listAccounts(configuration: $0, etag: etag)
            }
            if let refreshedAccounts = result.accounts {
                accounts = refreshedAccounts
                liveSnapshots = liveSnapshots.filter { id, _ in
                    refreshedAccounts.contains(where: { $0.id == id })
                }
                providerSnapshots = providerSnapshots.filter { id, _ in
                    refreshedAccounts.contains(where: { $0.id == id })
                }
                accountUsageWindows = accountUsageWindows.filter { id, _ in
                    refreshedAccounts.contains(where: { $0.id == id })
                }
            }
            etag = result.etag ?? etag
            persistCache()
            await synchronizeQuotaResetNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshUserOwnedData(configuration: ServerConfiguration) async {
        loadState = .loading
        errorMessage = nil
        defer { loadState = .loaded }

        async let profile = capture {
            try await authenticatedRequest(configuration: configuration) {
                try await client.userProfile(configuration: $0)
            }
        }
        async let quotas = capture {
            try await authenticatedRequest(configuration: configuration) {
                try await client.userPlatformQuotas(configuration: $0)
            }
        }
        async let keys = capture {
            try await authenticatedRequest(configuration: configuration) {
                try await client.userAPIKeys(configuration: $0)
            }
        }
        async let subscriptions = capture {
            try await authenticatedRequest(configuration: configuration) {
                try await client.userSubscriptionSummary(configuration: $0)
            }
        }
        let results = await (profile, quotas, keys, subscriptions)
        var failures: [String] = []
        switch results.0 {
        case let .success(value):
            let refreshedConfiguration = (self.configuration ?? configuration).replacingUser(value)
            try? keychain.save(refreshedConfiguration)
            self.configuration = refreshedConfiguration
        case let .failure(message): failures.append("账户：\(message)")
        }
        switch results.1 {
        case let .success(value): userPlatformQuotas = value
        case let .failure(message): failures.append("平台额度：\(message)")
        }
        switch results.2 {
        case let .success(value): userAPIKeys = value
        case let .failure(message): failures.append("API Key：\(message)")
        }
        switch results.3 {
        case let .success(value): userSubscriptions = value
        case let .failure(message): failures.append("订阅：\(message)")
        }
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        persistCache()
    }

    func refreshDashboard(includeLiveQuotas: Bool = true) async {
        await refreshAccounts()
        if includeLiveQuotas && isAdministrator {
            await refreshAllQuotas()
        }
        await refreshUsageData()
    }

    var providerQuotaGroups: [ProviderQuotaGroup] {
        Dictionary(grouping: accounts, by: \.providerID)
            .map { providerID, groupedAccounts in
                let sortedAccounts = groupedAccounts.sorted { lhs, rhs in
                    let lhsHealth = lhs.health(snapshot: providerSnapshot(for: lhs))
                    let rhsHealth = rhs.health(snapshot: providerSnapshot(for: rhs))
                    if lhsHealth != rhsHealth { return lhsHealth > rhsHealth }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                let snapshots = sortedAccounts.compactMap(providerSnapshot(for:))
                var orderedWindowIDs: [String] = []
                var labels: [String: String] = [:]
                for snapshot in snapshots {
                    for window in snapshot.windows where !orderedWindowIDs.contains(window.id) {
                        orderedWindowIDs.append(window.id)
                        labels[window.id] = window.label
                    }
                }
                let windows = orderedWindowIDs.map { windowID in
                    let matching = snapshots.compactMap { snapshot in
                        snapshot.windows.first(where: { $0.id == windowID })
                    }
                    let metrics = matching.compactMap(\.metrics)
                    return ProviderQuotaWindowSummary(
                        id: windowID,
                        label: labels[windowID] ?? windowID,
                        summary: AggregateQuotaWindow(
                            windows: matching.map(\.quota),
                            totalAccountCount: sortedAccounts.count
                        ),
                        metrics: metrics.isEmpty ? nil : UsageWindowMetrics(summing: metrics)
                    )
                }
                return ProviderQuotaGroup(
                    id: providerID,
                    displayName: sortedAccounts.first?.providerDisplayName ?? providerID.capitalized,
                    accounts: sortedAccounts,
                    reportingAccountCount: snapshots.filter { !$0.windows.isEmpty }.count,
                    queryableAccountCount: sortedAccounts.filter(\.supportsProviderUsage).count,
                    windows: windows
                )
            }
            .sorted { lhs, rhs in
                if lhs.id == "codex" { return true }
                if rhs.id == "codex" { return false }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    func usageWindows(for account: CodexAccount) -> AccountUsageWindows? {
        accountUsageWindows[account.id]
    }

    func snapshot(for account: CodexAccount) -> AccountQuotaSnapshot? {
        liveSnapshots[account.id] ?? account.cachedQuotaSnapshot()
    }

    func providerSnapshot(for account: CodexAccount) -> ProviderQuotaSnapshot? {
        if !account.supportsCodexQuota {
            return providerSnapshots[account.id]
        }
        guard let snapshot = snapshot(for: account) else { return nil }
        let usage = usageWindows(for: account)
        let windows = [
            snapshot.fiveHour.map {
                ProviderQuotaWindow(id: "5h", label: "5h", quota: $0, metrics: usage?.fiveHour)
            },
            snapshot.sevenDay.map {
                ProviderQuotaWindow(id: "7d", label: "7d", quota: $0, metrics: usage?.sevenDay)
            },
        ].compactMap { $0 }
        return ProviderQuotaSnapshot(
            accountID: account.id,
            providerID: account.providerID,
            providerName: account.providerDisplayName,
            planType: snapshot.planType,
            resetCredits: snapshot.resetCredits,
            windows: windows,
            fetchedAt: snapshot.fetchedAt,
            error: nil
        )
    }

    func refreshQuota(for account: CodexAccount) async {
#if DEBUG
        if isDemoMode {
            guard !refreshingAccountIDs.contains(account.id) else { return }
            refreshingAccountIDs.insert(account.id)
            try? await Task.sleep(for: .milliseconds(350))
            seedDemoData()
            refreshingAccountIDs.remove(account.id)
            return
        }
#endif
        guard let configuration = await validConfiguration(),
              !refreshingAccountIDs.contains(account.id) else { return }
        if !account.supportsCodexQuota {
            guard account.supportsProviderUsage else { return }
            refreshingAccountIDs.insert(account.id)
            defer { refreshingAccountIDs.remove(account.id) }
            do {
                let usage = try await authenticatedRequest(configuration: configuration) {
                    try await client.providerUsage(for: account.id, configuration: $0)
                }
                providerSnapshots[account.id] = usage.snapshot(for: account)
                errorMessage = usage.error
                persistCache()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }
        refreshingAccountIDs.insert(account.id)
        errorMessage = nil
        defer { refreshingAccountIDs.remove(account.id) }

        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)
        async let quotaUsage = try? await authenticatedRequest(configuration: configuration) {
            try await client.quota(for: account.id, configuration: $0)
        }
        async let recentLogs = try? await authenticatedRequest(configuration: configuration) {
            try await client.recentUsageLogs(
                for: account.id,
                since: fiveHoursAgo,
                through: now,
                configuration: $0
            )
        }
        async let weeklyStats = try? await authenticatedRequest(configuration: configuration) {
            try await client.accountUsageStats(
                for: account.id,
                period: "week",
                configuration: $0
            )
        }
        let (quota, logs, week) = await (quotaUsage, recentLogs, weeklyStats)

        if let quota {
            liveSnapshots[account.id] = quota.snapshot(for: account)
        }
        let previousUsage = accountUsageWindows[account.id]
        let refreshedUsage = AccountUsageWindows(
            fiveHour: logs.map { UsageWindowMetrics(logs: $0, since: fiveHoursAgo) },
            sevenDay: week.map(UsageWindowMetrics.init(stats:))
        )
        if refreshedUsage.fiveHour != nil || refreshedUsage.sevenDay != nil {
            accountUsageWindows[account.id] = AccountUsageWindows(
                fiveHour: refreshedUsage.fiveHour ?? previousUsage?.fiveHour,
                sevenDay: refreshedUsage.sevenDay ?? previousUsage?.sevenDay
            )
        }
        if quota == nil || (refreshedUsage.fiveHour == nil && refreshedUsage.sevenDay == nil) {
            errorMessage = "部分账号数据未能实时更新，已保留缓存数据"
        }
        persistCache()
        await synchronizeQuotaResetNotifications()
    }

    func refreshAllQuotas() async {
#if DEBUG
        if isDemoMode {
            refreshingAccountIDs = Set(accounts.map(\.id))
            try? await Task.sleep(for: .milliseconds(350))
            seedDemoData()
            refreshingAccountIDs = []
            return
        }
#endif
        guard let configuration = await validConfiguration(),
              !accounts.isEmpty,
              refreshingAccountIDs.isEmpty else { return }
        let accountsToRefresh = accounts.filter(\.supportsCodexQuota)
        let providerAccountsToRefresh = accounts.filter {
            !$0.supportsCodexQuota && $0.supportsProviderUsage
        }
        let client = client
        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)
        refreshingAccountIDs.formUnion(accountsToRefresh.map(\.id))
        refreshingAccountIDs.formUnion(providerAccountsToRefresh.map(\.id))
        errorMessage = nil

        var iterator = accountsToRefresh.makeIterator()
        var failedCount = 0
        await withTaskGroup(
            of: (Int, AccountQuotaSnapshot?, AccountUsageWindows).self
        ) { group in
            for _ in 0..<min(2, accountsToRefresh.count) {
                guard let account = iterator.next() else { break }
                group.addTask {
                    async let quotaUsage = try? await client.quota(
                        for: account.id,
                        configuration: configuration
                    )
                    async let recentLogs = try? await client.recentUsageLogs(
                        for: account.id,
                        since: fiveHoursAgo,
                        through: now,
                        configuration: configuration
                    )
                    async let weeklyStats = try? await client.accountUsageStats(
                        for: account.id,
                        period: "week",
                        configuration: configuration
                    )
                    let (quota, logs, week) = await (quotaUsage, recentLogs, weeklyStats)
                    return (
                        account.id,
                        quota?.snapshot(for: account),
                        AccountUsageWindows(
                            fiveHour: logs.map {
                                UsageWindowMetrics(logs: $0, since: fiveHoursAgo)
                            },
                            sevenDay: week.map(UsageWindowMetrics.init(stats:))
                        )
                    )
                }
            }

            while let (accountID, snapshot, usageWindows) = await group.next() {
                refreshingAccountIDs.remove(accountID)
                if let snapshot {
                    liveSnapshots[accountID] = snapshot
                }
                let previousUsage = accountUsageWindows[accountID]
                if usageWindows.fiveHour != nil || usageWindows.sevenDay != nil {
                    accountUsageWindows[accountID] = AccountUsageWindows(
                        fiveHour: usageWindows.fiveHour ?? previousUsage?.fiveHour,
                        sevenDay: usageWindows.sevenDay ?? previousUsage?.sevenDay
                    )
                }
                if snapshot == nil || (
                    usageWindows.fiveHour == nil && usageWindows.sevenDay == nil
                ) {
                    failedCount += 1
                }
                if let nextAccount = iterator.next() {
                    group.addTask {
                        async let quotaUsage = try? await client.quota(
                            for: nextAccount.id,
                            configuration: configuration
                        )
                        async let recentLogs = try? await client.recentUsageLogs(
                            for: nextAccount.id,
                            since: fiveHoursAgo,
                            through: now,
                            configuration: configuration
                        )
                        async let weeklyStats = try? await client.accountUsageStats(
                            for: nextAccount.id,
                            period: "week",
                            configuration: configuration
                        )
                        let (quota, logs, week) = await (quotaUsage, recentLogs, weeklyStats)
                        return (
                            nextAccount.id,
                            quota?.snapshot(for: nextAccount),
                            AccountUsageWindows(
                                fiveHour: logs.map {
                                    UsageWindowMetrics(logs: $0, since: fiveHoursAgo)
                                },
                                sevenDay: week.map(UsageWindowMetrics.init(stats:))
                            )
                        )
                    }
                }
            }
        }
        refreshingAccountIDs.subtract(accountsToRefresh.map(\.id))
        var providerIterator = providerAccountsToRefresh.makeIterator()
        await withTaskGroup(of: (Int, ProviderQuotaSnapshot?).self) { group in
            for _ in 0..<min(2, providerAccountsToRefresh.count) {
                guard let account = providerIterator.next() else { break }
                group.addTask {
                    let usage = try? await client.providerUsage(
                        for: account.id,
                        configuration: configuration
                    )
                    return (account.id, usage?.snapshot(for: account))
                }
            }
            while let (accountID, snapshot) = await group.next() {
                refreshingAccountIDs.remove(accountID)
                if let snapshot {
                    providerSnapshots[accountID] = snapshot
                    if snapshot.windows.isEmpty { failedCount += 1 }
                } else {
                    failedCount += 1
                }
                if let account = providerIterator.next() {
                    group.addTask {
                        let usage = try? await client.providerUsage(
                            for: account.id,
                            configuration: configuration
                        )
                        return (account.id, usage?.snapshot(for: account))
                    }
                }
            }
        }
        refreshingAccountIDs.subtract(providerAccountsToRefresh.map(\.id))
        if failedCount > 0 {
            errorMessage = "\(failedCount) 个账号未能实时更新，已保留缓存数据"
        }
        persistCache()
        await synchronizeQuotaResetNotifications()
    }

    func prepareQuotaResetNotifications() async {
        guard quotaResetNotificationsEnabled else {
            notificationAuthorizationStatus = await quotaResetNotifications.authorizationStatus()
            return
        }

        let status = await quotaResetNotifications.requestAuthorizationIfNeeded()
        notificationAuthorizationStatus = status
        guard status.allowsNotifications else {
            quotaResetNotificationsEnabled = false
            UserDefaults.standard.set(
                false,
                forKey: QuotaResetNotificationManager.enabledDefaultsKey
            )
            quotaResetNotifications.removeScheduledNotifications()
            return
        }
        quotaResetNotifications.removeScheduledNotifications()
        await observeQuotaChanges(shouldNotify: false)
    }

    func setQuotaResetNotificationsEnabled(_ enabled: Bool) async {
        if !enabled {
            quotaResetNotificationsEnabled = false
            UserDefaults.standard.set(
                false,
                forKey: QuotaResetNotificationManager.enabledDefaultsKey
            )
            quotaResetNotifications.removeScheduledNotifications()
            notificationAuthorizationStatus = await quotaResetNotifications.authorizationStatus()
            return
        }

        quotaResetNotificationsEnabled = true
        UserDefaults.standard.set(
            true,
            forKey: QuotaResetNotificationManager.enabledDefaultsKey
        )
        await prepareQuotaResetNotifications()
    }

#if DEBUG
    func sendTestQuotaResetNotification() async {
        await setQuotaResetNotificationsEnabled(true)
        guard notificationAuthorizationStatus.allowsNotifications else { return }
        await quotaResetNotifications.scheduleTestNotification()
    }
#endif

    func refreshUsageData() async {
#if DEBUG
        if isDemoMode {
            isRefreshingUsage = true
            isRefreshingModelStats = true
            try? await Task.sleep(for: .milliseconds(250))
            seedDemoUsageData()
            isRefreshingUsage = false
            isRefreshingModelStats = false
            return
        }
#endif
        guard let configuration = await validConfiguration(), !isRefreshingUsage else { return }
        isRefreshingUsage = true
        isRefreshingModelStats = true
        usageErrorMessage = nil
        modelStatsErrorMessage = nil
        usageTrendErrorMessage = nil
        defer {
            isRefreshingUsage = false
            isRefreshingModelStats = false
        }

        let range = modelStatsPeriod.dateRange()

        async let dashboardResult = capture {
            try await authenticatedRequest(configuration: configuration) {
                try await client.dashboardStats(configuration: $0)
            }
        }
        async let modelsResult = capture {
            try await authenticatedRequest(configuration: configuration) {
                try await client.modelUsageStats(
                    configuration: $0,
                    startDate: range.start,
                    endDate: range.end,
                    timeZoneIdentifier: TimeZone.current.identifier
                )
            }
        }
        async let trendResult = capture {
            try await authenticatedRequest(configuration: configuration) {
                try await client.usageTrend(
                    configuration: $0,
                    startDate: range.start,
                    endDate: range.end,
                    timeZoneIdentifier: TimeZone.current.identifier,
                    granularity: modelStatsPeriod.trendGranularity
                )
            }
        }
        let (dashboard, models, trend) = await (dashboardResult, modelsResult, trendResult)

        var failures: [String] = []
        switch dashboard {
        case let .success(stats):
            usageStats = stats
        case let .failure(message):
            failures.append("全站统计：\(message)")
        }
        switch models {
        case let .success(stats):
            modelUsageStats = stats
        case let .failure(message):
            modelStatsErrorMessage = "模型统计不可用：\(message)"
        }
        switch trend {
        case let .success(stats):
            usageTrend = stats
        case let .failure(message):
            usageTrendErrorMessage = "Token 趋势不可用：\(message)"
        }
        usageErrorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        persistCache()
    }

    func selectModelStatsPeriod(_ period: ModelStatsPeriod) async {
        guard period != modelStatsPeriod, !isRefreshingModelStats else { return }
        modelStatsPeriod = period
        await refreshModelUsageStats()
    }

    func refreshModelUsageStats() async {
#if DEBUG
        if isDemoMode {
            guard !isRefreshingModelStats else { return }
            isRefreshingModelStats = true
            modelStatsErrorMessage = nil
            usageTrendErrorMessage = nil
            try? await Task.sleep(for: .milliseconds(220))
            seedDemoModelUsageData()
            seedDemoUsageTrendData()
            isRefreshingModelStats = false
            persistCache()
            return
        }
#endif
        guard let configuration = await validConfiguration(),
              !isRefreshingModelStats else { return }
        isRefreshingModelStats = true
        modelStatsErrorMessage = nil
        usageTrendErrorMessage = nil
        defer { isRefreshingModelStats = false }

        let range = modelStatsPeriod.dateRange()
        async let modelsResult = capture {
            try await authenticatedRequest(configuration: configuration) {
                try await client.modelUsageStats(
                    configuration: $0,
                    startDate: range.start,
                    endDate: range.end,
                    timeZoneIdentifier: TimeZone.current.identifier
                )
            }
        }
        async let trendResult = capture {
            try await authenticatedRequest(configuration: configuration) {
                try await client.usageTrend(
                    configuration: $0,
                    startDate: range.start,
                    endDate: range.end,
                    timeZoneIdentifier: TimeZone.current.identifier,
                    granularity: modelStatsPeriod.trendGranularity
                )
            }
        }
        let (models, trend) = await (modelsResult, trendResult)

        switch models {
        case let .success(stats):
            modelUsageStats = stats
        case let .failure(message):
            modelStatsErrorMessage = "模型统计不可用：\(message)"
        }
        switch trend {
        case let .success(stats):
            usageTrend = stats
        case let .failure(message):
            usageTrendErrorMessage = "Token 趋势不可用：\(message)"
        }
        persistCache()
    }

    func isRefreshing(account: CodexAccount) -> Bool {
        refreshingAccountIDs.contains(account.id)
    }

    func disconnect() {
        if let configuration {
            cache.clear(scope: configuration.cacheScopeIdentifier)
            let client = client
            Task { try? await client.logout(configuration: configuration) }
        }
        quotaResetNotifications.removeScheduledNotifications()
        quotaResetNotifications.clearObservedRemaining()
        WidgetQuotaSummaryStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
        try? keychain.delete()
        configuration = nil
        isDemoMode = false
        clearCurrentIdentityData()
        connectionError = nil
    }

    private func clearCurrentIdentityData() {
        refreshTask?.cancel()
        refreshTask = nil
        if let configuration {
            cache.clear(scope: configuration.cacheScopeIdentifier)
        }
        quotaResetNotifications.clearObservedRemaining()
        accounts = []
        liveSnapshots = [:]
        providerSnapshots = [:]
        accountUsageWindows = [:]
        usageStats = nil
        openAITokenStats = nil
        modelUsageStats = nil
        usageTrend = nil
        userPlatformQuotas = []
        userAPIKeys = []
        userSubscriptions = []
        modelStatsPeriod = .last24Hours
        etag = nil
        loadState = .idle
        errorMessage = nil
        usageErrorMessage = nil
        modelStatsErrorMessage = nil
        usageTrendErrorMessage = nil
        pendingTwoFactorEmail = nil
        pendingTwoFactorToken = nil
        pendingTwoFactorBaseURL = nil
#if DEBUG
        demoSignedInUser = nil
#endif
    }

#if DEBUG
    func startDemo() {
        clearCurrentIdentityData()
        configuration = nil
        demoSignedInUser = nil
        isDemoMode = true
        errorMessage = nil
        connectionError = nil
        seedDemoData()
    }

    func startUserDemo() {
        clearCurrentIdentityData()
        configuration = nil
        isDemoMode = true
        demoSignedInUser = AuthenticatedUser(
            id: 2001,
            email: "demo@example.com",
            username: "普通用户",
            role: .user,
            balance: 18.62,
            status: "active"
        )
        seedDemoUserData()
    }

    private func seedDemoUserData(now: Date = Date()) {
        accounts = []
        liveSnapshots = [:]
        providerSnapshots = [:]
        accountUsageWindows = [:]
        userPlatformQuotas = [
            UserPlatformQuota(
                platform: "openai",
                dailyUsageUSD: 1.84,
                dailyLimitUSD: 5,
                dailyWindowResetsAt: ISO8601DateFormatter().string(
                    from: now.addingTimeInterval(8 * 60 * 60)
                ),
                weeklyUsageUSD: 8.35,
                weeklyLimitUSD: 25,
                weeklyWindowResetsAt: ISO8601DateFormatter().string(
                    from: now.addingTimeInterval(4 * 24 * 60 * 60)
                ),
                monthlyUsageUSD: 21.7,
                monthlyLimitUSD: 80,
                monthlyWindowResetsAt: ISO8601DateFormatter().string(
                    from: now.addingTimeInterval(18 * 24 * 60 * 60)
                )
            ),
            UserPlatformQuota(
                platform: "anthropic",
                dailyUsageUSD: 0.72,
                dailyLimitUSD: 3,
                dailyWindowResetsAt: nil,
                weeklyUsageUSD: 4.1,
                weeklyLimitUSD: 15,
                weeklyWindowResetsAt: nil,
                monthlyUsageUSD: 12.8,
                monthlyLimitUSD: 50,
                monthlyWindowResetsAt: nil
            ),
        ]
        userAPIKeys = [
            UserAPIKey(
                id: 301,
                name: "生产环境",
                status: "active",
                quota: 50,
                quotaUsed: 17.46,
                rateLimit5h: 8,
                rateLimit1d: 20,
                rateLimit7d: 60,
                usage5h: 2.15,
                usage1d: 5.24,
                usage7d: 18.8,
                reset5hAt: nil,
                reset1dAt: nil,
                reset7dAt: nil
            ),
            UserAPIKey(
                id: 302,
                name: "测试环境",
                status: "active",
                quota: 10,
                quotaUsed: 2.31,
                rateLimit5h: 0,
                rateLimit1d: 5,
                rateLimit7d: 0,
                usage5h: 0,
                usage1d: 0.84,
                usage7d: 0,
                reset5hAt: nil,
                reset1dAt: nil,
                reset7dAt: nil
            ),
        ]
        userSubscriptions = [
            UserSubscriptionSummary(
                id: 401,
                groupID: 8,
                groupName: "Codex Pro",
                status: "active",
                dailyUsedUSD: 1.84,
                dailyLimitUSD: 5,
                weeklyUsedUSD: 8.35,
                weeklyLimitUSD: 25,
                monthlyUsedUSD: 21.7,
                monthlyLimitUSD: 80,
                expiresAt: ISO8601DateFormatter().string(
                    from: now.addingTimeInterval(40 * 24 * 60 * 60)
                )
            ),
        ]
        seedDemoUsageData(now: now)
        loadState = .loaded
        errorMessage = nil
    }

    private func seedDemoData(now: Date = Date()) {
        let demoAccounts = [
            CodexAccount(
                id: 1001,
                name: "主力账号",
                platform: "openai",
                type: "oauth",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1002,
                name: "团队账号",
                platform: "openai",
                type: "oauth",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1003,
                name: "高负载账号",
                platform: "openai",
                type: "oauth",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1004,
                name: "缓存账号",
                platform: "openai",
                type: "oauth",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1005,
                name: "暂停账号",
                platform: "openai",
                type: "oauth",
                status: "error",
                schedulable: false,
                errorMessage: "账号暂时不可调度",
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1006,
                name: "Claude 主账号",
                platform: "anthropic",
                type: "oauth",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1007,
                name: "Gemini Pro",
                platform: "gemini",
                type: "oauth",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1008,
                name: "Antigravity",
                platform: "antigravity",
                type: "oauth",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1009,
                name: "Grok Heavy",
                platform: "grok",
                type: "oauth",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1010,
                name: "Gemini AI Studio",
                platform: "gemini",
                type: "apikey",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1011,
                name: "Grok Free",
                platform: "grok",
                type: "oauth",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1012,
                name: "OpenAI API Key",
                platform: "openai",
                type: "apikey",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
            CodexAccount(
                id: 1013,
                name: "Claude API Key",
                platform: "anthropic",
                type: "apikey",
                status: "active",
                schedulable: true,
                errorMessage: nil,
                parentAccountID: nil,
                extra: nil
            ),
        ]

        accounts = demoAccounts
        liveSnapshots = [
            1001: demoSnapshot(
                account: demoAccounts[0],
                plan: "plus",
                fiveHourUsed: 37,
                sevenDayUsed: 61,
                fetchedAt: now
            ),
            1002: demoSnapshot(
                account: demoAccounts[1],
                plan: "team",
                fiveHourUsed: 84,
                sevenDayUsed: 72,
                fetchedAt: now
            ),
            1003: demoSnapshot(
                account: demoAccounts[2],
                plan: "pro",
                fiveHourUsed: 97,
                sevenDayUsed: 91,
                fetchedAt: now
            ),
            1004: demoSnapshot(
                account: demoAccounts[3],
                plan: "plus",
                fiveHourUsed: 46,
                sevenDayUsed: 55,
                fetchedAt: now.addingTimeInterval(-2 * 60 * 60),
                source: .cached
            ),
            1005: demoSnapshot(
                account: demoAccounts[4],
                plan: "plus",
                fiveHourUsed: 18,
                sevenDayUsed: 29,
                fetchedAt: now
            ),
        ]
        providerSnapshots = [
            1006: demoProviderSnapshot(
                account: demoAccounts[5],
                plan: "max",
                values: [
                    ("5h", "5h", 28),
                    ("7d", "7d", 63),
                    ("7d-sonnet", "7d S", 74),
                    ("7d-fable", "7d F", 16),
                ],
                fetchedAt: now
            ),
            1007: demoProviderSnapshot(
                account: demoAccounts[6],
                plan: "pro",
                values: [("shared-daily", "1d", 41), ("shared-minute", "1m", 12)],
                fetchedAt: now
            ),
            1008: demoProviderSnapshot(
                account: demoAccounts[7],
                plan: "PRO",
                values: [
                    ("claude-sonnet-4", "sonnet-4", 54),
                    ("gemini-2.5-pro", "2.5-pro", 31),
                    ("gemini-2.5-flash", "2.5-flash", 82),
                ],
                fetchedAt: now
            ),
            1009: demoProviderSnapshot(
                account: demoAccounts[8],
                plan: "SuperGrok Heavy",
                values: [("7d", "7d", 67)],
                fetchedAt: now
            ),
            1010: demoProviderSnapshot(
                account: demoAccounts[9],
                plan: "paid",
                values: [
                    ("pro-daily", "Pro 1d", 72),
                    ("flash-daily", "Flash 1d", 34),
                    ("pro-minute", "Pro 1m", 18),
                    ("flash-minute", "Flash 1m", 56),
                ],
                fetchedAt: now
            ),
            1011: demoProviderSnapshot(
                account: demoAccounts[10],
                plan: "free",
                values: [("free-24h", "24h", 39)],
                fetchedAt: now
            ),
        ]
        accountUsageWindows = [
            1001: demoAccountUsage(fiveHourRequests: 323, fiveHourTokens: 39_800_000, fiveHourCost: 37.57, sevenDayRequests: 2_740, sevenDayTokens: 318_600_000, sevenDayCost: 294.20),
            1002: demoAccountUsage(fiveHourRequests: 215, fiveHourTokens: 27_400_000, fiveHourCost: 25.82, sevenDayRequests: 1_930, sevenDayTokens: 241_800_000, sevenDayCost: 226.44),
            1003: demoAccountUsage(fiveHourRequests: 486, fiveHourTokens: 61_200_000, fiveHourCost: 58.31, sevenDayRequests: 3_860, sevenDayTokens: 492_100_000, sevenDayCost: 465.70),
            1004: demoAccountUsage(fiveHourRequests: 178, fiveHourTokens: 21_600_000, fiveHourCost: 20.05, sevenDayRequests: 1_420, sevenDayTokens: 176_400_000, sevenDayCost: 162.88),
            1005: demoAccountUsage(fiveHourRequests: 0, fiveHourTokens: 0, fiveHourCost: 0, sevenDayRequests: 68, sevenDayTokens: 7_800_000, sevenDayCost: 7.18),
        ]
        seedDemoUsageData(now: now)
        loadState = .loaded
        persistWidgetSummary()
    }

    private func seedDemoUsageData(now: Date = Date()) {
        usageStats = DashboardUsageStats(
            totalRequests: 184_267,
            todayRequests: 1_428,
            totalInputTokens: 824_600_000,
            todayInputTokens: 8_420_000,
            totalOutputTokens: 96_320_000,
            todayOutputTokens: 1_260_000,
            totalCacheCreationTokens: 12_840_000,
            todayCacheCreationTokens: 164_000,
            totalCacheReadTokens: 384_900_000,
            todayCacheReadTokens: 4_760_000,
            totalTokens: 1_318_660_000,
            todayTokens: 14_604_000,
            totalCost: 4_286.42,
            todayCost: 48.76,
            totalActualCost: 3_514.87,
            todayActualCost: 39.28,
            averageDurationMilliseconds: 3_284,
            requestsPerMinute: 18,
            tokensPerMinute: 186_400,
            totalAccounts: 12,
            normalAccounts: 10,
            errorAccounts: 1,
            rateLimitAccounts: 1,
            overloadAccounts: 0,
            statsUpdatedAt: ISO8601DateFormatter().string(from: now),
            statsStale: false
        )
        seedDemoModelUsageData(now: now)
        seedDemoUsageTrendData(now: now)
    }

    private func seedDemoModelUsageData(now: Date = Date()) {
        let range = modelStatsPeriod.dateRange(now: now)
        let scale: Double = switch modelStatsPeriod {
        case .last24Hours: 1
        case .today: 0.58
        case .yesterday: 0.83
        case .last7Days: 5.6
        case .last30Days: 22
        case .thisMonth: 14
        case .lastMonth: 24
        }

        func item(
            model: String,
            requests: Int64,
            tokens: Int64,
            actualCost: Double
        ) -> ModelUsageStat {
            let scaledTokens = Int64(Double(tokens) * scale)
            let scaledRequests = Int64(Double(requests) * scale)
            return ModelUsageStat(
                model: model,
                requests: scaledRequests,
                inputTokens: Int64(Double(scaledTokens) * 0.62),
                outputTokens: Int64(Double(scaledTokens) * 0.18),
                cacheCreationTokens: Int64(Double(scaledTokens) * 0.03),
                cacheReadTokens: Int64(Double(scaledTokens) * 0.17),
                totalTokens: scaledTokens,
                cost: actualCost * scale * 1.08,
                actualCost: actualCost * scale,
                accountCost: actualCost * scale * 0.82
            )
        }

        modelUsageStats = ModelUsageStatsResponse(
            models: [
                item(model: "gpt-5.6-sol", requests: 842, tokens: 8_384_000, actualCost: 75.00),
                item(model: "codex-auto-review", requests: 185, tokens: 971_000, actualCost: 7.52),
                item(model: "gpt-5.6-terra", requests: 20, tokens: 488_750, actualCost: 0.413),
                item(model: "gpt-5.6-luna", requests: 6, tokens: 264_140, actualCost: 0.220),
            ],
            startDate: range.start,
            endDate: range.end
        )
    }

    private func seedDemoUsageTrendData(now: Date = Date()) {
        let range = modelStatsPeriod.dateRange(now: now)
        let isHourly = modelStatsPeriod.trendGranularity == "hour"
        let pointCount: Int = switch modelStatsPeriod {
        case .last24Hours: 12
        case .today: 10
        case .yesterday: 12
        case .last7Days: 7
        case .last30Days: 15
        case .thisMonth: 14
        case .lastMonth: 15
        }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = isHourly ? "yyyy-MM-dd HH:00" : "yyyy-MM-dd"

        let points = (0..<pointCount).map { index in
            let offset = index - pointCount + 1
            let component: Calendar.Component = isHourly ? .hour : .day
            let step = isHourly ? 2 : max(1, modelStatsPeriod == .last30Days ? 2 : 1)
            let date = calendar.date(byAdding: component, value: offset * step, to: now) ?? now
            let wave = 0.68 + 0.32 * sin(Double(index) * 0.82) + Double(index) * 0.025
            let input = Int64(max(160_000, 2_900_000 * wave))
            let output = Int64(Double(input) * (0.13 + Double(index % 3) * 0.018))
            let cacheCreation = Int64(Double(input) * 0.025)
            let cacheRead = Int64(Double(input) * (0.42 + Double(index % 4) * 0.06))
            return UsageTrendPoint(
                date: formatter.string(from: date),
                requests: Int64(80 + index * 11),
                inputTokens: input,
                outputTokens: output,
                cacheCreationTokens: cacheCreation,
                cacheReadTokens: cacheRead,
                totalTokens: input + output + cacheCreation + cacheRead,
                cost: Double(input) / 100_000,
                actualCost: Double(input) / 125_000
            )
        }
        usageTrend = UsageTrendResponse(
            trend: points,
            startDate: range.start,
            endDate: range.end,
            granularity: modelStatsPeriod.trendGranularity
        )
    }

    private func demoAccountUsage(
        fiveHourRequests: Int64,
        fiveHourTokens: Int64,
        fiveHourCost: Double,
        sevenDayRequests: Int64,
        sevenDayTokens: Int64,
        sevenDayCost: Double
    ) -> AccountUsageWindows {
        AccountUsageWindows(
            fiveHour: UsageWindowMetrics(
                stats: AccountUsageStats(
                    totalRequests: fiveHourRequests,
                    totalInputTokens: fiveHourTokens,
                    totalOutputTokens: 0,
                    totalCacheCreationTokens: 0,
                    totalCacheReadTokens: 0,
                    totalTokens: fiveHourTokens,
                    totalActualCost: fiveHourCost
                )
            ),
            sevenDay: UsageWindowMetrics(
                stats: AccountUsageStats(
                    totalRequests: sevenDayRequests,
                    totalInputTokens: sevenDayTokens,
                    totalOutputTokens: 0,
                    totalCacheCreationTokens: 0,
                    totalCacheReadTokens: 0,
                    totalTokens: sevenDayTokens,
                    totalActualCost: sevenDayCost
                )
            )
        )
    }

    private func demoProviderSnapshot(
        account: CodexAccount,
        plan: String,
        values: [(id: String, label: String, usedPercent: Double)],
        fetchedAt: Date
    ) -> ProviderQuotaSnapshot {
        ProviderQuotaSnapshot(
            accountID: account.id,
            providerID: account.providerID,
            providerName: account.providerDisplayName,
            planType: plan,
            windows: values.enumerated().map { index, value in
                let metrics = account.providerID == "antigravity"
                    ? nil
                    : UsageWindowMetrics(
                        providerStats: ProviderWindowStats(
                            requests: Int64(32 + index * 17),
                            tokens: Int64(1_800_000 + index * 640_000),
                            cost: 1.25 + Double(index) * 0.78
                        )
                    )
                return ProviderQuotaWindow(
                    id: value.id,
                    label: value.label,
                    quota: QuotaWindow(
                        usedPercent: value.usedPercent,
                        resetsAt: fetchedAt.addingTimeInterval(Double(index + 1) * 3 * 60 * 60)
                    ),
                    metrics: metrics
                )
            },
            fetchedAt: fetchedAt,
            error: nil
        )
    }

    private func demoSnapshot(
        account: CodexAccount,
        plan: String,
        fiveHourUsed: Double,
        sevenDayUsed: Double,
        fetchedAt: Date,
        source: AccountQuotaSnapshot.Source = .live
    ) -> AccountQuotaSnapshot {
        AccountQuotaSnapshot(
            accountID: account.id,
            accountName: account.name,
            planType: plan,
            fiveHour: QuotaWindow(
                usedPercent: fiveHourUsed,
                resetsAt: Date().addingTimeInterval(2 * 60 * 60)
            ),
            sevenDay: QuotaWindow(
                usedPercent: sevenDayUsed,
                resetsAt: Date().addingTimeInterval(3 * 24 * 60 * 60)
            ),
            resetCredits: 2,
            fetchedAt: fetchedAt,
            source: source
        )
    }
#endif

    private func persistCache() {
        guard let configuration else {
            persistWidgetSummary()
            return
        }
        cache.save(
            DashboardCache(
                accounts: accounts,
                liveSnapshots: liveSnapshots,
                providerSnapshots: providerSnapshots,
                accountUsageWindows: accountUsageWindows,
                usageStats: usageStats,
                openAITokenStats: openAITokenStats,
                modelUsageStats: modelUsageStats,
                usageTrend: usageTrend,
                modelStatsPeriodRawValue: modelStatsPeriod.rawValue,
                etag: etag,
                accountScopeVersion: 2,
                userPlatformQuotas: userPlatformQuotas,
                userAPIKeys: userAPIKeys,
                userSubscriptions: userSubscriptions,
                savedAt: Date()
            ),
            scope: configuration.cacheScopeIdentifier
        )
        persistWidgetSummary()
    }

    private func persistWidgetSummary() {
        let groups = providerQuotaGroups
        let latestQuotaUpdate = accounts
            .compactMap(providerSnapshot(for:))
            .compactMap(\.fetchedAt)
            .max() ?? Date()
        WidgetQuotaSummaryStore.save(
            WidgetQuotaSummary(
                providers: groups.map { group in
                    WidgetProviderQuotaSummary(
                        id: group.id,
                        displayName: group.displayName,
                        accountCount: group.accounts.count,
                        reportingAccountCount: group.reportingAccountCount,
                        windows: group.windows.isEmpty
                            ? [
                                WidgetQuotaWindowSummary(
                                    id: "availability",
                                    label: "额度",
                                    remainingPercent: nil,
                                    requests: nil,
                                    tokens: nil
                                ),
                            ]
                            : group.windows.map { window in
                                WidgetQuotaWindowSummary(
                                    id: window.id,
                                    label: window.label,
                                    remainingPercent: window.summary.averageRemainingPercent,
                                    requests: window.metrics?.requestCount,
                                    tokens: window.metrics?.totalTokens
                                )
                            }
                    )
                },
                updatedAt: latestQuotaUpdate
            )
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func synchronizeQuotaResetNotifications() async {
        notificationAuthorizationStatus = await quotaResetNotifications.authorizationStatus()
        guard quotaResetNotificationsEnabled,
              notificationAuthorizationStatus.allowsNotifications else { return }
        quotaResetNotifications.removeScheduledNotifications()
        await observeQuotaChanges(shouldNotify: true)
    }

    private func observeQuotaChanges(shouldNotify: Bool) async {
        let snapshots = accounts.compactMap { account -> (CodexAccount, AccountQuotaSnapshot)? in
            guard let snapshot = snapshot(for: account) else { return nil }
            return (account, snapshot)
        }
        await quotaResetNotifications.observe(
            snapshots: snapshots,
            shouldNotify: shouldNotify
        )
    }
}

private extension UNAuthorizationStatus {
    var allowsNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }
}

@MainActor
private final class QuotaResetNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let enabledDefaultsKey = "quota-reset-notifications-enabled"

    private static let identifierPrefix = "sub2watch.quota-reset."
    private static let scheduledIdentifiersDefaultsKey = "quota-reset-notification-identifiers"
    private static let observedRemainingDefaultsKey = "quota-reset-observed-remaining"
    private static let minimumRecoveryIncrease = 0.5
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        let currentStatus = await authorizationStatus()
        guard currentStatus == .notDetermined else { return currentStatus }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    func observe(
        snapshots: [(account: CodexAccount, snapshot: AccountQuotaSnapshot)],
        shouldNotify: Bool
    ) async {
        var observedRemaining = loadObservedRemaining()
        var recoveredAccounts: [QuotaWindowKind: Set<String>] = [:]

        for item in snapshots {
            for (window, quota) in [
                (QuotaWindowKind.fiveHour, item.snapshot.fiveHour),
                (QuotaWindowKind.sevenDay, item.snapshot.sevenDay)
            ] {
                guard let quota else { continue }
                let key = "\(item.account.id).\(window.rawValue)"
                let remaining = quota.remainingPercent

                if shouldNotify,
                   let previous = observedRemaining[key],
                   remaining >= 90,
                   remaining - previous >= Self.minimumRecoveryIncrease {
                    recoveredAccounts[window, default: []].insert(item.account.name)
                }
                observedRemaining[key] = remaining
            }
        }

        UserDefaults.standard.set(
            observedRemaining,
            forKey: Self.observedRemainingDefaultsKey
        )

        guard shouldNotify else { return }
        for window in QuotaWindowKind.allCases {
            guard let names = recoveredAccounts[window], !names.isEmpty else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(window.title)额度已重置"
            if names.count == 1, let name = names.first {
                content.body = "\(name) 的 Codex 额度已经恢复"
            } else {
                content.body = "\(names.count) 个账号的 Codex 额度已经恢复至 90% 以上"
            }
            content.sound = .default
            content.threadIdentifier = "sub2watch.quota-reset.\(window.rawValue)"
            let request = UNNotificationRequest(
                identifier: "\(Self.identifierPrefix)confirmed.\(window.rawValue).\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    func removeScheduledNotifications() {
        let identifiers = UserDefaults.standard.stringArray(
            forKey: Self.scheduledIdentifiersDefaultsKey
        ) ?? []
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        UserDefaults.standard.removeObject(forKey: Self.scheduledIdentifiersDefaultsKey)
    }

    func clearObservedRemaining() {
        UserDefaults.standard.removeObject(forKey: Self.observedRemainingDefaultsKey)
    }

#if DEBUG
    func scheduleTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "5 小时额度已重置"
        content.body = "测试账号的 Codex 额度已经恢复"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(Self.identifierPrefix)test",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 4, repeats: false)
        )
        try? await center.add(request)
    }
#endif

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private func loadObservedRemaining() -> [String: Double] {
        let stored = UserDefaults.standard.dictionary(
            forKey: Self.observedRemainingDefaultsKey
        ) ?? [:]
        return stored.reduce(into: [:]) { result, item in
            if let value = item.value as? NSNumber {
                result[item.key] = value.doubleValue
            }
        }
    }
}

private enum QuotaWindowKind: String, CaseIterable, Hashable {
    case fiveHour = "5h"
    case sevenDay = "7d"

    var title: String {
        switch self {
        case .fiveHour: "5 小时"
        case .sevenDay: "7 天"
        }
    }
}

private enum CapturedResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)
}

private func capture<Value: Sendable>(
    _ operation: @Sendable () async throws -> Value
) async -> CapturedResult<Value> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error.localizedDescription)
    }
}

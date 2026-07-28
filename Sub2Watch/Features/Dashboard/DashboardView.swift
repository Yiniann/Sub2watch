import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsSettings = false
    @State private var selectedPage: DashboardPage = .total

    private var isRefreshingDashboard: Bool {
        model.loadState == .loading ||
            !model.refreshingAccountIDs.isEmpty ||
            model.isRefreshingUsage
    }

    init() {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let requestedPage = environment["SUB2WATCH_PAGE"]
            .flatMap(Int.init)
            .flatMap(DashboardPage.init(rawValue:))
        _selectedPage = State(initialValue: requestedPage ?? .total)
        _showsSettings = State(initialValue: environment["SUB2WATCH_SETTINGS"] == "1")
#endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.loadState == .loading && model.isAdministrator && model.accounts.isEmpty {
                    ProgressView("正在读取")
                } else if model.isAdministrator && model.accounts.isEmpty {
                    ContentUnavailableView(
                        "没有账号",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                } else {
                    TabView(selection: $selectedPage) {
                        UsageDashboardView()
                            .tag(DashboardPage.dashboard)

                        if model.isAdministrator {
                            TotalQuotaPage()
                                .tag(DashboardPage.total)

                            AccountQuotaPage(groups: model.providerQuotaGroups)
                                .tag(DashboardPage.accounts)
                        } else {
                            UserQuotaPage()
                                .tag(DashboardPage.total)

                            UserAPIKeysPage()
                                .tag(DashboardPage.accounts)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                }
            }
            .navigationTitle(selectedPage.title(isAdministrator: model.isAdministrator))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CodexAccount.self) { account in
                AccountDetailView(account: account)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshDashboard() }
                    } label: {
                        if isRefreshingDashboard {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel(isRefreshingDashboard ? "正在刷新" : "刷新")
                    .disabled(isRefreshingDashboard)
                }
            }
            .sheet(isPresented: $showsSettings) {
                SetupView(mode: .settings)
            }
            .task {
                await model.prepareQuotaResetNotifications()
                if (model.isAdministrator && model.accounts.isEmpty) ||
                    model.accountUsageWindows.isEmpty ||
                    model.usageStats == nil ||
                    model.modelUsageStats == nil {
                    await model.refreshDashboard()
                }
            }
        }
    }
}

private enum DashboardPage: Int, CaseIterable, Hashable {
    case dashboard
    case total
    case accounts

    func title(isAdministrator: Bool) -> String {
        if isAdministrator {
            switch self {
            case .dashboard: return "看板"
            case .total: return "额度"
            case .accounts: return "账号额度"
            }
        }
        switch self {
        case .dashboard: return "我的看板"
        case .total: return "我的额度"
        case .accounts: return "API Key"
        }
    }
}

private struct TotalQuotaPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(model.providerQuotaGroups) { group in
                    ProviderQuotaSummaryView(group: group)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .padding(.horizontal, 5)
        .safeAreaPadding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct UserQuotaPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if let user = model.signedInUser {
                    HStack(spacing: 9) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.username?.isEmpty == false ? user.username! : user.email)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(user.email)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        Spacer(minLength: 3)
                        Text(user.balance.compactCurrencyFormatted)
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(9)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ForEach(model.userPlatformQuotas) { quota in
                    VStack(alignment: .leading, spacing: 7) {
                        Label(
                            userProviderName(quota.platform),
                            systemImage: providerSymbolName(quota.platform)
                        )
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        UserLimitRow(label: "日", used: quota.dailyUsageUSD, limit: quota.dailyLimitUSD)
                        UserLimitRow(label: "周", used: quota.weeklyUsageUSD, limit: quota.weeklyLimitUSD)
                        UserLimitRow(label: "月", used: quota.monthlyUsageUSD, limit: quota.monthlyLimitUSD)
                    }
                    .padding(9)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ForEach(model.userSubscriptions) { subscription in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(subscription.groupName, systemImage: "calendar.badge.checkmark")
                                .font(.headline)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("订阅")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        UserLimitRow(
                            label: "日",
                            used: subscription.dailyUsedUSD,
                            limit: positiveLimit(subscription.dailyLimitUSD)
                        )
                        UserLimitRow(
                            label: "周",
                            used: subscription.weeklyUsedUSD,
                            limit: positiveLimit(subscription.weeklyLimitUSD)
                        )
                        UserLimitRow(
                            label: "月",
                            used: subscription.monthlyUsedUSD,
                            limit: positiveLimit(subscription.monthlyLimitUSD)
                        )
                    }
                    .padding(9)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if model.userPlatformQuotas.isEmpty && model.userSubscriptions.isEmpty {
                    ContentUnavailableView("暂无额度", systemImage: "gauge.with.dots.needle.0percent")
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 5)
        .safeAreaPadding(.top, 10)
    }
}

private struct UserLimitRow: View {
    let label: String
    let used: Double
    let limit: Double?

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .frame(width: 18, alignment: .leading)
                Spacer()
                if let limit, limit > 0 {
                    Text("\(used.compactCurrencyFormatted) / \(limit.compactCurrencyFormatted)")
                } else {
                    Text("已用 \(used.compactCurrencyFormatted)")
                }
            }
            .font(.caption2.monospacedDigit())
            if let limit, limit > 0 {
                ProgressView(value: min(max(used / limit, 0), 1))
                    .tint(used >= limit ? .red : .blue)
            }
        }
    }
}

private struct UserAPIKeysPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.userAPIKeys.isEmpty {
                ContentUnavailableView("暂无 API Key", systemImage: "key")
            }
            ForEach(model.userAPIKeys) { key in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(key.name)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Circle()
                            .fill(key.status == "active" ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                    }
                    if key.quota > 0 {
                        UserLimitRow(label: "总", used: key.quotaUsed, limit: key.quota)
                    }
                    if key.rateLimit5h > 0 {
                        UserLimitRow(label: "5h", used: key.usage5h, limit: key.rateLimit5h)
                    }
                    if key.rateLimit1d > 0 {
                        UserLimitRow(label: "1d", used: key.usage1d, limit: key.rateLimit1d)
                    }
                    if key.rateLimit7d > 0 {
                        UserLimitRow(label: "7d", used: key.usage7d, limit: key.rateLimit7d)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .refreshable { await model.refreshDashboard() }
    }
}

private func positiveLimit(_ value: Double) -> Double? {
    value > 0 ? value : nil
}

private func userProviderName(_ id: String) -> String {
    switch id.lowercased() {
    case "openai": return "OpenAI"
    case "anthropic", "claude": return "Claude"
    case "gemini", "google": return "Gemini"
    case "antigravity": return "Antigravity"
    case "grok": return "Grok"
    default: return id.capitalized
    }
}

private struct AccountQuotaPage: View {
    @EnvironmentObject private var model: AppModel
    let groups: [ProviderQuotaGroup]

    var body: some View {
        List {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            ForEach(groups) { group in
                Section(group.displayName) {
                    ForEach(group.accounts) { account in
                        NavigationLink(value: account) {
                            AccountRowView(
                                account: account,
                                snapshot: model.providerSnapshot(for: account)
                            )
                        }
                    }
                }
            }
        }
        .refreshable {
            await model.refreshDashboard()
        }
    }
}

private struct ProviderQuotaSummaryView: View {
    let group: ProviderQuotaGroup

    private var totalAccountCount: Int {
        group.accounts.count
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProviderIconView(providerID: group.id, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .allowsTightening(true)
                    Text("\(totalAccountCount) 个账号")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(2)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(group.reportingAccountCount)/\(totalAccountCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(group.reportingAccountCount > 0 ? Color.green : Color.secondary)
                    Text("已上报")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            if group.windows.isEmpty {
                Divider()
                Label(
                    group.queryableAccountCount > 0 ? "暂无额度数据" : "此账号类型不支持额度查询",
                    systemImage: "gauge.with.dots.needle.0percent"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Divider()
                ForEach(Array(group.windows.enumerated()), id: \.element.id) { index, window in
                    AggregateQuotaWindowRow(
                        label: window.label,
                        summary: window.summary,
                        metrics: window.metrics,
                        accent: quotaAccent(index: index)
                    )
                }
            }
        }
        .padding(.trailing, 5)
        .frame(maxWidth: .infinity)
    }
}

private func quotaAccent(index: Int) -> Color {
    [.purple, .mint, .blue, .orange, .cyan, .green][index % 6]
}

private struct AggregateQuotaWindowRow: View {
    let label: String
    let summary: AggregateQuotaWindow
    let metrics: UsageWindowMetrics?
    let accent: Color

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.body.monospaced().weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.17))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    AggregateMetricTag(
                        text: metrics.map { "\(totalQuotaNumber($0.requestCount)) req" } ?? "-- req"
                    )
                    AggregateMetricTag(
                        text: metrics.map { totalQuotaNumber($0.totalTokens) } ?? "--"
                    )
                    Spacer(minLength: 3)
                    Text(summary.averageRemainingPercent.map { "\(Int($0.rounded()))%" } ?? "--")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                ProgressView(value: summary.averageRemainingPercent ?? 0, total: 100)
                    .tint(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
    }
}

private struct AggregateMetricTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8.5).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .fixedSize(horizontal: true, vertical: false)
    }
}

private func totalQuotaNumber(_ value: Int64) -> String {
    value.formatted(.number.notation(.compactName))
}

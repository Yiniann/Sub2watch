import SwiftUI

struct PhoneDashboardView: View {
    private enum DashboardTab: String, Hashable {
        case usage
        case quota
        case accounts
    }

    @EnvironmentObject private var model: AppModel
    @State private var showsSettings = false
    @State private var selectedTab: DashboardTab = .quota

    init() {
#if DEBUG
        let requestedTab = ProcessInfo.processInfo.environment["SUB2WATCH_PHONE_TAB"]
            .flatMap(DashboardTab.init(rawValue:))
        _selectedTab = State(initialValue: requestedTab ?? .quota)
#endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboardPage(title: "用量") {
                usageSection
                PhoneUsageAnalyticsView()
            }
            .tag(DashboardTab.usage)
            .tabItem {
                Label("用量", systemImage: "chart.bar.fill")
            }

            if model.isAdministrator {
                dashboardPage(title: "总额度") {
                    connectionCard
                    quotaSection
                }
                .tag(DashboardTab.quota)
                .tabItem {
                    Label("总额度", systemImage: "gauge.with.dots.needle.50percent")
                }

                dashboardPage(title: "账号") {
                    PhoneAccountListView()
                }
                .tag(DashboardTab.accounts)
                .tabItem {
                    Label("账号", systemImage: "person.2.fill")
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            PhoneSettingsView()
        }
        .task {
            if model.accounts.isEmpty ||
                model.usageStats == nil ||
                model.modelUsageStats == nil ||
                model.usageTrend == nil {
                await model.refreshDashboard()
            }
        }
        .onChange(of: model.isAdministrator) { _, isAdministrator in
            if !isAdministrator, selectedTab != .usage {
                selectedTab = .usage
            }
        }
    }

    private func dashboardPage<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    if let errorSummary {
                        PhoneErrorBanner(message: errorSummary)
                    }
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable { await model.refreshDashboard() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshDashboard() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                    .accessibilityLabel("刷新")

                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
        }
    }

    private var connectionCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(watchStatusColor.opacity(0.14))
                Image(systemName: watchStatusIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(watchStatusColor)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(watchStatusTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .layoutPriority(1)
                    Circle()
                        .fill(watchStatusColor)
                        .frame(width: 7, height: 7)
                }
                HStack(spacing: 8) {
                    Text("\(serverName) · \(identityName)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(lastUpdateText)
                        .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhoneSectionHeader(title: "今日用量", trailing: statsUpdateLabel)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                spacing: 10
            ) {
                PhoneMetricCard(
                    title: "请求",
                    value: model.usageStats.map { compactNumber($0.todayRequests) } ?? "--",
                    footer: model.usageStats.map { "累计 \(compactNumber($0.totalRequests))" } ?? "累计 --",
                    symbol: "arrow.up.arrow.down",
                    tint: .blue
                )
                PhoneMetricCard(
                    title: "Token",
                    value: model.usageStats.map { compactNumber($0.todayTokens) } ?? "--",
                    footer: model.usageStats.map { "累计 \(compactNumber($0.totalTokens))" } ?? "累计 --",
                    symbol: "text.line.first.and.arrowtriangle.forward",
                    tint: .purple
                )
                PhoneMetricCard(
                    title: "实际费用",
                    value: model.usageStats.map { currency($0.todayActualCost) } ?? "--",
                    footer: model.usageStats.map { "累计 \(currency($0.totalActualCost))" } ?? "累计 --",
                    symbol: "dollarsign.circle.fill",
                    tint: .green
                )
                PhoneMetricCard(
                    title: "性能",
                    value: durationText,
                    footer: performanceFooter,
                    symbol: "gauge.with.dots.needle.50percent",
                    tint: .orange
                )
            }
        }
    }

    @ViewBuilder
    private var quotaSection: some View {
        if model.providerQuotaGroups.isEmpty {
            PhoneEmptyState(
                title: "暂无额度数据",
                message: "下拉刷新后会显示各平台的额度窗口。",
                symbol: "gauge.with.dots.needle.50percent"
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                PhoneSectionHeader(title: "平台额度", trailing: "\(model.accounts.count) 个账号")
                ForEach(model.providerQuotaGroups) { group in
                    PhoneProviderQuotaCard(group: group)
                }
            }
        }
    }

    private var isRefreshing: Bool {
        model.loadState == .loading || !model.refreshingAccountIDs.isEmpty || model.isRefreshingUsage
    }

    private var serverName: String {
        model.configuration?.apiBaseURL.host() ?? "-"
    }

    private var identityName: String {
        model.signedInUser?.email ?? "管理员密钥"
    }

    private var watchStatusTitle: String {
        if model.isCompanionReachable { return "Apple Watch 已连接" }
        if model.isCompanionAppInstalled { return "Apple Watch 后台同步" }
        return "Apple Watch 未安装"
    }

    private var watchStatusIcon: String {
        model.isCompanionReachable ? "applewatch.radiowaves.left.and.right" : "applewatch"
    }

    private var watchStatusColor: Color {
        if model.isCompanionReachable { return .green }
        if model.isCompanionAppInstalled { return .blue }
        return .orange
    }

    private var lastUpdateText: String {
        guard let date = model.lastDashboardRefreshAt else { return "等待更新" }
        return date.formatted(.dateTime.hour().minute()) + " 更新"
    }

    private var statsUpdateLabel: String? {
        model.usageStats?.statsStale == true ? "缓存数据" : nil
    }

    private var durationText: String {
        guard let milliseconds = model.usageStats?.averageDurationMilliseconds else { return "--" }
        if milliseconds < 1_000 {
            return "\(Int(milliseconds.rounded())) ms"
        }
        return (milliseconds / 1_000).formatted(.number.precision(.fractionLength(1))) + " s"
    }

    private var performanceFooter: String {
        guard let stats = model.usageStats else { return "RPM -- · TPM --" }
        return "RPM \(compactNumber(stats.requestsPerMinute)) · TPM \(compactNumber(stats.tokensPerMinute))"
    }

    private var errorSummary: String? {
        [
            model.errorMessage,
            model.usageErrorMessage,
            model.modelStatsErrorMessage,
            model.usageTrendErrorMessage,
        ]
            .compactMap { $0 }
            .first
    }
}

private struct PhoneSectionHeader: View {
    let title: String
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct PhoneMetricCard: View {
    let title: String
    let value: String
    let footer: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tint)
                .frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PhoneProviderQuotaCard: View {
    let group: ProviderQuotaGroup

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PhoneProviderIcon(providerID: group.id, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                        .font(.headline)
                    Text("\(group.reportingAccountCount)/\(group.accounts.count) 个账号已上报")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)

            ForEach(Array(group.windows.enumerated()), id: \.element.id) { index, window in
                Divider()
                    .padding(.leading, 14)
                PhoneQuotaRow(window: window)
                    .padding(.horizontal, 14)
                    .padding(.vertical, index == group.windows.count - 1 ? 14 : 12)
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PhoneQuotaRow: View {
    let window: ProviderQuotaWindowSummary

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(window.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(percentText)
                    .font(.headline)
                    .monospacedDigit()
            }

            ProgressView(value: window.summary.averageRemainingPercent ?? 0, total: 100)
                .tint(quotaColor(window.label))

            HStack(spacing: 10) {
                Text("覆盖 \(window.summary.reportingAccountCount)/\(window.summary.totalAccountCount)")
                Spacer()
                if let metrics = window.metrics {
                    Text("\(compactNumber(metrics.requestCount)) 请求")
                    Text("\(compactNumber(metrics.totalTokens)) Token")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private var percentText: String {
        window.summary.averageRemainingPercent.map { "\(Int($0.rounded()))%" } ?? "--"
    }
}

struct PhoneProviderIcon: View {
    let providerID: String
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(providerColor.opacity(0.16))
            Image(systemName: providerSymbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(providerColor)
        }
        .frame(width: size, height: size)
    }

    private var providerColor: Color {
        switch providerID.lowercased() {
        case "codex", "openai": .green
        case "claude", "anthropic": .orange
        case "gemini": .blue
        case "grok": .red
        case "antigravity": .purple
        default: .indigo
        }
    }

    private var providerSymbol: String {
        switch providerID.lowercased() {
        case "codex", "openai": "terminal.fill"
        case "claude", "anthropic": "sparkles"
        case "gemini": "diamond.fill"
        case "grok": "xmark"
        case "antigravity": "atom"
        default: "cpu.fill"
        }
    }
}

private struct PhoneErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PhoneEmptyState: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}

private func compactNumber(_ value: Int64) -> String {
    value.formatted(.number.notation(.compactName))
}

private func currency(_ value: Double) -> String {
    value.formatted(.currency(code: "USD").precision(.fractionLength(2...2)))
}

private func quotaColor(_ label: String) -> Color {
    let normalized = label.lowercased()
    if normalized.contains("5h") || normalized.contains("5 h") { return .pink }
    if normalized.contains("7d") || normalized.contains("7 d") { return .teal }
    if normalized.contains("month") || normalized.contains("月") { return .purple }
    if normalized.contains("day") || normalized.contains("日") { return .blue }
    return .indigo
}

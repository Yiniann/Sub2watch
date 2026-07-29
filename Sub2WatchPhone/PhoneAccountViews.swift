import Foundation
import SwiftUI

struct PhoneAccountListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.accounts.isEmpty {
            ContentUnavailableView(
                "暂无账号",
                systemImage: "person.2",
                description: Text("下拉刷新后会显示已接入的 AI 账号。")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(model.providerQuotaGroups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.displayName)
                                .font(.headline)
                            Spacer()
                            Text("\(group.reportingAccountCount)/\(group.accounts.count) 已上报")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 2)

                        ForEach(group.accounts) { account in
                            NavigationLink {
                                PhoneAccountDetailView(account: account)
                            } label: {
                                PhoneAccountQuotaCard(
                                    account: account,
                                    snapshot: model.providerSnapshot(for: account)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct PhoneAccountQuotaCard: View {
    let account: CodexAccount
    let snapshot: ProviderQuotaSnapshot?

    private var health: AccountHealth {
        account.health(snapshot: snapshot)
    }

    private var planText: String {
        guard let plan = snapshot?.planType, !plan.isEmpty else {
            return account.providerDisplayName
        }
        return "\(account.providerDisplayName) · \(plan.capitalized)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PhoneProviderIcon(providerID: account.providerID, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(planText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                HStack(spacing: 7) {
                    Text(phoneHealthLabel(health))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(phoneHealthColor(health))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(phoneHealthColor(health).opacity(0.12))
                        .clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            if let snapshot, !snapshot.windows.isEmpty {
                Divider()
                ForEach(Array(snapshot.windows.enumerated()), id: \.element.id) { index, window in
                    PhoneAccountWindowRow(
                        window: window,
                        accent: phoneAccountAccent(index)
                    )
                    if index < snapshot.windows.count - 1 {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            } else {
                Divider()
                Label(
                    snapshot?.error ??
                        (account.supportsProviderUsage ? "暂无额度数据" : "此账号类型不支持额度查询"),
                    systemImage: "gauge.with.dots.needle.0percent"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PhoneAccountWindowRow: View {
    let window: ProviderQuotaWindow
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(window.label)
                .font(.subheadline.monospaced().weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(width: 40, height: 42)
                .background(accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    PhoneAccountMetricTag(
                        title: "请求",
                        value: window.metrics.map { phoneAccountNumber($0.requestCount) } ?? "--"
                    )
                    PhoneAccountMetricTag(
                        title: "Token",
                        value: window.metrics.map { phoneAccountNumber($0.totalTokens) } ?? "--"
                    )
                    PhoneAccountMetricTag(
                        title: "费用",
                        value: window.metrics.map { phoneAccountCurrency($0.actualCost) } ?? "--"
                    )
                }

                HStack(spacing: 9) {
                    ProgressView(value: window.quota.remainingPercent, total: 100)
                        .tint(accent)
                    Text("\(Int(window.quota.remainingPercent.rounded()))%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .frame(width: 44, alignment: .trailing)
                    Text(phoneResetText(window.quota.resetsAt))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(minWidth: 48, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PhoneAccountMetricTag: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.monospacedDigit().weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct PhoneAccountDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedWindowID = ""
    let account: CodexAccount

    private var snapshot: ProviderQuotaSnapshot? {
        model.providerSnapshot(for: account)
    }

    private var health: AccountHealth {
        account.health(snapshot: snapshot)
    }

    private var selectedWindow: ProviderQuotaWindow? {
        snapshot?.windows.first(where: { $0.id == selectedWindowID }) ?? snapshot?.windows.first
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                metadataHeader
                quotaSection

                if let snapshot, !snapshot.windows.isEmpty {
                    usageSection(windows: snapshot.windows)
                }

                dataFooter

                if let error = account.errorMessage, !error.isEmpty {
                    PhoneAccountError(message: error, color: .red)
                }
                if let error = snapshot?.error, !error.isEmpty {
                    PhoneAccountError(message: error, color: .orange)
                }
                if let error = model.errorMessage, !error.isEmpty {
                    PhoneAccountError(message: error, color: .orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.refreshQuota(for: account) }
                } label: {
                    if model.isRefreshing(account: account) {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!account.supportsProviderUsage || model.isRefreshing(account: account))
                .accessibilityLabel("刷新账号")
            }
        }
        .onAppear {
            selectedWindowID = snapshot?.windows.first?.id ?? ""
        }
        .onChange(of: snapshot?.windows.map(\.id) ?? []) { _, windowIDs in
            if !windowIDs.contains(selectedWindowID) {
                selectedWindowID = windowIDs.first ?? ""
            }
        }
    }

    private var metadataHeader: some View {
        HStack(spacing: 12) {
            PhoneProviderIcon(providerID: account.providerID, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.providerDisplayName)
                    .font(.headline)
                Text(snapshot?.planType?.capitalized ?? account.type)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Label(phoneHealthLabel(health), systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(phoneHealthColor(health))
                if let resetCredits = snapshot?.resetCredits {
                    Label("可重置 \(resetCredits) 次", systemImage: "arrow.counterclockwise")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("剩余额度")
                .font(.headline)
                .padding(.horizontal, 2)

            if let snapshot, !snapshot.windows.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(Array(snapshot.windows.enumerated()), id: \.element.id) { index, window in
                        PhoneQuotaRing(window: window, accent: phoneAccountAccent(index))
                    }
                }
            } else {
                ContentUnavailableView(
                    account.supportsProviderUsage ? "暂无额度数据" : "不支持额度查询",
                    systemImage: "gauge.with.dots.needle.0percent"
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
    }

    private func usageSection(windows: [ProviderQuotaWindow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("用量详情")
                .font(.headline)
                .padding(.horizontal, 2)

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(windows) { window in
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                selectedWindowID = window.id
                            }
                        } label: {
                            Text(window.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedWindowID == window.id ? Color.white : .secondary)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(selectedWindowID == window.id ? Color.accentColor : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(4)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            PhoneAccountUsageGrid(
                metrics: selectedWindow?.metrics,
                showsTokenBreakdown: account.supportsCodexQuota
            )
        }
    }

    @ViewBuilder
    private var dataFooter: some View {
        if let fetchedAt = snapshot?.fetchedAt {
            HStack(spacing: 5) {
                Image(systemName: health == .stale ? "clock" : "bolt.fill")
                Text(health == .stale ? "缓存数据" : "实时数据")
                Spacer()
                Text(fetchedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
        }
    }
}

private struct PhoneQuotaRing: View {
    let window: ProviderQuotaWindow
    let accent: Color

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.13), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: window.quota.remainingPercent / 100)
                    .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(window.quota.remainingPercent.rounded()))%")
                    .font(.title3.monospacedDigit().bold())
            }
            .frame(width: 88, height: 88)

            Text(window.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)

            Text(phoneResetText(window.quota.resetsAt))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PhoneAccountUsageGrid: View {
    let metrics: UsageWindowMetrics?
    let showsTokenBreakdown: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            PhoneAccountUsageTile(
                title: "请求",
                symbol: "arrow.up.arrow.down",
                value: metrics.map { phoneAccountNumber($0.requestCount) } ?? "--",
                tint: .cyan
            )
            PhoneAccountUsageTile(
                title: "Token",
                symbol: "text.word.spacing",
                value: metrics.map { phoneAccountNumber($0.totalTokens) } ?? "--",
                tint: .indigo
            )
            PhoneAccountUsageTile(
                title: "实际费用",
                symbol: "dollarsign.circle",
                value: metrics.map { phoneAccountCurrency($0.actualCost) } ?? "--",
                tint: .orange
            )
            if showsTokenBreakdown {
                PhoneAccountUsageTile(
                    title: "输入",
                    symbol: "arrow.down.to.line",
                    value: metrics.map { phoneAccountNumber($0.inputTokens) } ?? "--",
                    tint: .blue
                )
                PhoneAccountUsageTile(
                    title: "输出",
                    symbol: "arrow.up.from.line",
                    value: metrics.map { phoneAccountNumber($0.outputTokens) } ?? "--",
                    tint: .green
                )
                PhoneAccountUsageTile(
                    title: "缓存",
                    symbol: "internaldrive",
                    value: metrics.map {
                        phoneAccountNumber($0.cacheCreationTokens + $0.cacheReadTokens)
                    } ?? "--",
                    tint: .mint
                )
            }
        }
    }
}

private struct PhoneAccountUsageTile: View {
    let title: String
    let symbol: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PhoneAccountError: View {
    let message: String
    let color: Color

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func phoneAccountAccent(_ index: Int) -> Color {
    [.purple, .mint, .blue, .orange, .cyan, .green][index % 6]
}

private func phoneHealthColor(_ health: AccountHealth) -> Color {
    switch health {
    case .healthy: .green
    case .warning: .orange
    case .critical, .error: .red
    case .stale, .unknown: .gray
    }
}

private func phoneHealthLabel(_ health: AccountHealth) -> String {
    switch health {
    case .healthy: "可用"
    case .warning: "注意"
    case .critical: "紧张"
    case .stale: "缓存"
    case .error: "停用"
    case .unknown: "未知"
    }
}

private func phoneAccountNumber(_ value: Int64) -> String {
    value.formatted(.number.notation(.compactName))
}

private func phoneAccountCurrency(_ value: Double) -> String {
    value.formatted(.currency(code: "USD").precision(.fractionLength(2...2)))
}

private func phoneResetText(_ date: Date?) -> String {
    guard let date else { return "--" }
    let seconds = max(0, date.timeIntervalSinceNow)
    if seconds < 60 { return "现在" }
    if seconds < 3_600 { return "\(Int(seconds / 60))m" }
    if seconds < 86_400 {
        let hours = Int(seconds / 3_600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3_600) / 60)
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
    let days = Int(seconds / 86_400)
    let hours = Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3_600)
    return hours == 0 ? "\(days)d" : "\(days)d \(hours)h"
}

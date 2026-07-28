import SwiftUI

struct AccountDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedWindowID = ""
    let account: CodexAccount

    private var snapshot: ProviderQuotaSnapshot? {
        model.providerSnapshot(for: account)
    }

    private var health: AccountHealth {
        account.health(snapshot: snapshot)
    }

    private var selectedMetrics: UsageWindowMetrics? {
        selectedWindow?.metrics
    }

    private var selectedWindow: ProviderQuotaWindow? {
        snapshot?.windows.first(where: { $0.id == selectedWindowID }) ?? snapshot?.windows.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AccountMetadataHeader(
                    providerName: account.providerDisplayName,
                    plan: snapshot?.planType,
                    health: health,
                    resetCredits: snapshot?.resetCredits
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text("剩余额度")
                        .font(.headline)

                    if let snapshot, !snapshot.windows.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(Array(snapshot.windows.enumerated()), id: \.element.id) { index, window in
                                QuotaSummary(
                                    label: window.label,
                                    window: window.quota,
                                    color: detailQuotaAccent(index)
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Label(
                            account.supportsProviderUsage ? "暂无额度数据" : "此账号类型不支持额度查询",
                            systemImage: "gauge.with.dots.needle.0percent"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if let snapshot, !snapshot.windows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                    Text("用量详情")
                        .font(.headline)

                        AccountWindowPicker(
                            windows: snapshot.windows,
                            selection: $selectedWindowID
                        )

                        AccountUsageGrid(
                            metrics: selectedMetrics,
                            showsTokenBreakdown: account.supportsCodexQuota,
                            costTitle: account.supportsCodexQuota ? "实际费用" : "账号费用"
                        )
                    }
                }

                AccountDataFooter(updatedAt: snapshot?.fetchedAt, isStale: health == .stale)

                if let error = account.errorMessage, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.octagon.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 5)
        }
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
                .accessibilityLabel("刷新账号")
                .disabled(!account.supportsProviderUsage || model.isRefreshing(account: account))
            }
        }
        .onChange(of: snapshot?.windows.map(\.id) ?? []) { _, windowIDs in
            if !windowIDs.contains(selectedWindowID) {
                selectedWindowID = windowIDs.first ?? ""
            }
        }
    }
}

private struct AccountWindowPicker: View {
    let windows: [ProviderQuotaWindow]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 3) {
            ForEach(windows) { window in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                            selection = window.id
                    }
                } label: {
                        Text(window.label)
                        .font(.caption.weight(.semibold))
                            .frame(minWidth: 42)
                        .padding(.vertical, 5)
                            .foregroundStyle(selection == window.id ? Color.white : Color.secondary)
                            .background(selection == window.id ? Color.accentColor : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        }
        .padding(3)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("统计窗口")
    }
}

private struct AccountMetadataHeader: View {
    let providerName: String
    let plan: String?
    let health: AccountHealth
    let resetCredits: Int?

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(health.color)
                    .frame(width: 6, height: 6)
                Text(health.cardLabel)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(health.color)

            if let plan, !plan.isEmpty {
                Text("\(providerName) \(plan.lowercased())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 3)

            if let resetCredits {
                Label("\(resetCredits) 次", systemImage: "arrow.counterclockwise")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }
        }
    }
}

private func detailQuotaAccent(_ index: Int) -> Color {
    [.purple, .mint, .blue, .orange, .cyan, .green][index % 6]
}

private struct QuotaSummary: View {
    let label: String
    let window: QuotaWindow?
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: (window?.remainingPercent ?? 0) / 100)
                    .stroke(
                        window == nil ? Color.gray : color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(window.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "--")
                    .font(.caption.monospacedDigit().bold())
            }
            .frame(width: 62, height: 62)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)

            Text(detailResetText(window?.resetsAt))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AccountUsageGrid: View {
    let metrics: UsageWindowMetrics?
    let showsTokenBreakdown: Bool
    let costTitle: String

    private let columns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            UsageMetricTile(
                title: "请求",
                systemImage: "arrow.up.arrow.down",
                value: metrics.map { detailNumber($0.requestCount) } ?? "--",
                color: .cyan
            )
            UsageMetricTile(
                title: "Token",
                systemImage: "text.word.spacing",
                value: metrics.map { detailNumber($0.totalTokens) } ?? "--",
                color: .indigo
            )
            UsageMetricTile(
                title: costTitle,
                systemImage: "dollarsign.circle",
                value: metrics.map { detailCurrency($0.actualCost) } ?? "--",
                color: .orange
            )
            if showsTokenBreakdown {
                UsageMetricTile(
                    title: "输入",
                    systemImage: "arrow.down.to.line",
                    value: metrics.map { detailNumber($0.inputTokens) } ?? "--",
                    color: .blue
                )
                UsageMetricTile(
                    title: "输出",
                    systemImage: "arrow.up.from.line",
                    value: metrics.map { detailNumber($0.outputTokens) } ?? "--",
                    color: .green
                )
                UsageMetricTile(
                    title: "缓存",
                    systemImage: "internaldrive",
                    value: metrics.map {
                        detailNumber($0.cacheCreationTokens + $0.cacheReadTokens)
                    } ?? "--",
                    color: .mint
                )
            }
        }
    }
}

private struct UsageMetricTile: View {
    let title: String
    let systemImage: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct AccountDataFooter: View {
    let updatedAt: Date?
    let isStale: Bool

    var body: some View {
        if let updatedAt {
            HStack(spacing: 4) {
                Image(systemName: isStale ? "clock" : "bolt.fill")
                Text(isStale ? "缓存数据" : "实时数据")
                Spacer()
                Text(updatedAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

private func detailNumber(_ value: Int64) -> String {
    value.formatted(.number.notation(.compactName))
}

private func detailCurrency(_ value: Double) -> String {
    if abs(value) >= 1_000 {
        return String(format: "$%.1fK", value / 1_000)
    }
    return String(format: "$%.2f", value)
}

private func detailResetText(_ date: Date?) -> String {
    guard let date else { return "--" }
    let seconds = max(0, date.timeIntervalSinceNow)
    if seconds < 60 { return "现在重置" }
    if seconds < 3_600 { return "\(Int(seconds / 60))m 后" }
    if seconds < 86_400 {
        let hours = Int(seconds / 3_600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3_600) / 60)
        return minutes == 0 ? "\(hours)h 后" : "\(hours)h \(minutes)m"
    }
    let days = Int(seconds / 86_400)
    let hours = Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3_600)
    return hours == 0 ? "\(days)d 后" : "\(days)d \(hours)h"
}

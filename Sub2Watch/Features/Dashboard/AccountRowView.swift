import SwiftUI

struct AccountRowView: View {
    let account: CodexAccount
    let snapshot: ProviderQuotaSnapshot?

    private var health: AccountHealth {
        account.health(snapshot: snapshot)
    }

    private var planLabel: String {
        guard let plan = snapshot?.planType, !plan.isEmpty else {
            return account.providerDisplayName
        }
        return "\(account.providerDisplayName) \(plan.lowercased())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                ProviderIconView(providerID: account.providerID, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    ViewThatFits(in: .horizontal) {
                        Text(planLabel)
                        Text(snapshot?.planType?.capitalized ?? account.providerDisplayName)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 3)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(health.color)
                            .frame(width: 6, height: 6)
                        Text(health.cardLabel)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(health.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(health.color.opacity(0.13))
                    .clipShape(Capsule())

                    if let resetCredits = snapshot?.resetCredits {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("可重置 \(resetCredits) 次")
                        }
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else if health == .stale {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                            Text("缓存数据")
                        }
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            Divider()

            if let snapshot, !snapshot.windows.isEmpty {
                ForEach(Array(snapshot.windows.enumerated()), id: \.element.id) { index, window in
                    AccountQuotaWindowRow(
                        label: window.label,
                        quota: window.quota,
                        usage: window.metrics,
                        accent: accountQuotaAccent(index)
                    )
                }
            } else {
                Label(
                    account.supportsProviderUsage ? "暂无额度数据" : "此账号类型不支持额度查询",
                    systemImage: "gauge.with.dots.needle.0percent"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 5)
        .padding(.trailing, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountQuotaWindowRow: View {
    let label: String
    let quota: QuotaWindow?
    let usage: UsageWindowMetrics?
    let accent: Color

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.caption.monospaced().weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .foregroundStyle(accent)
                .frame(width: 36, height: 38)
                .background(accent.opacity(0.17))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    AccountMetricTag(
                        text: usage.map { "\(compactAccountNumber($0.requestCount)) req" } ?? "-- req"
                    )
                    AccountMetricTag(
                        text: usage.map { compactAccountNumber($0.totalTokens) } ?? "--"
                    )
                }
                .frame(maxWidth: .infinity)

                ProgressView(value: quota?.remainingPercent ?? 0, total: 100)
                    .tint(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 3) {
                Text(quota.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "--")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(compactResetText(quota?.resetsAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 54, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProviderIconView: View {
    let providerID: String
    let size: CGFloat

    private var tint: Color {
        switch providerID.lowercased() {
        case "codex", "openai": .green
        case "anthropic", "claude": .orange
        case "gemini", "google": .blue
        case "antigravity": .cyan
        case "grok": .primary
        default: .secondary
        }
    }

    var body: some View {
        Image(systemName: providerSymbolName(providerID))
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            .accessibilityHidden(true)
    }
}

func providerSymbolName(_ providerID: String) -> String {
    switch providerID.lowercased() {
    case "codex", "openai": "terminal.fill"
    case "anthropic", "claude": "sun.max.fill"
    case "gemini", "google": "sparkles"
    case "antigravity": "atom"
    case "grok": "xmark"
    default: "cpu"
    }
}

private func accountQuotaAccent(_ index: Int) -> Color {
    [.purple, .mint, .blue, .orange, .cyan, .green][index % 6]
}

private struct AccountMetricTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct UsageQuotaWindowRow: View {
    let label: String
    let usedPercent: Double?
    let resetDate: Date?
    let metrics: UsageWindowMetrics?
    var trailingText: String?
    var emphasized = false

    private var accent: Color {
        label == "5h" ? .indigo : .mint
    }

    var body: some View {
        VStack(spacing: emphasized ? 8 : 5) {
            UsageMetricsLine(metrics: metrics, emphasized: emphasized)
            HStack(spacing: emphasized ? 7 : 5) {
                Text(label)
                    .font((emphasized ? Font.body : Font.caption).monospaced().weight(.medium))
                    .foregroundStyle(label == "7d" ? Color.white : Color.indigo.opacity(0.95))
                    .frame(width: emphasized ? 40 : 34, height: emphasized ? 29 : 24)
                    .background(accent.opacity(label == "7d" ? 0.28 : 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                ProgressView(value: usedPercent ?? 0, total: 100)
                    .tint(accent)
                    .frame(minWidth: 42)

                Text(usedPercent.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font((emphasized ? Font.body : Font.caption2).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .trailing)

                Text(trailingText ?? compactResetText(resetDate))
                    .font((emphasized ? Font.caption : Font.caption2).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

}

private struct UsageMetricsLine: View {
    let metrics: UsageWindowMetrics?
    let emphasized: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(metrics.map { "\(compactAccountNumber($0.requestCount)) req" } ?? "-- req")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(metrics.map { compactAccountNumber($0.totalTokens) } ?? "--")
                .frame(maxWidth: .infinity)
            Text(metrics.map { compactCost($0.actualCost) } ?? "--")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font((emphasized ? Font.caption : Font.caption2).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
    }

    private func compactCost(_ value: Double) -> String {
        if abs(value) >= 1_000_000 {
            return "A " + String(format: "$%.1fM", value / 1_000_000)
        }
        if abs(value) >= 1_000 {
            return "A " + String(format: "$%.1fK", value / 1_000)
        }
        return String(format: "A $%.2f", value)
    }
}

private func compactAccountNumber(_ value: Int64) -> String {
    let absolute = Double(abs(value))
    let sign = value < 0 ? "-" : ""
    let formatted: String
    if absolute >= 1_000_000_000 {
        formatted = String(format: "%.1fB", absolute / 1_000_000_000)
    } else if absolute >= 1_000_000 {
        formatted = String(format: "%.1fM", absolute / 1_000_000)
    } else if absolute >= 1_000 {
        formatted = String(format: "%.1fK", absolute / 1_000)
    } else {
        return "\(value)"
    }
    return sign + formatted.replacingOccurrences(of: ".0", with: "")
}

private func compactResetText(_ date: Date?) -> String {
    guard let date else { return "--" }
    let seconds = max(0, date.timeIntervalSinceNow)
    if seconds < 60 { return "现在" }
    if seconds < 60 * 60 { return "\(Int(seconds / 60))m" }
    if seconds < 24 * 60 * 60 {
        let hours = Int(seconds / 3600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
    let days = Int(seconds / 86_400)
    let hours = Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3600)
    return hours == 0 ? "\(days)d" : "\(days)d \(hours)h"
}

extension AccountHealth {
    var color: Color {
        switch self {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical, .error:
            return .red
        case .stale, .unknown:
            return .gray
        }
    }

    var label: String {
        switch self {
        case .healthy:
            return "正常"
        case .warning:
            return "接近上限"
        case .critical:
            return "额度紧张"
        case .stale:
            return "数据过期"
        case .error:
            return "不可调度"
        case .unknown:
            return "暂无数据"
        }
    }

    var cardLabel: String {
        switch self {
        case .healthy:
            return "可用"
        case .warning:
            return "注意"
        case .critical:
            return "紧张"
        case .stale:
            return "缓存"
        case .error:
            return "停用"
        case .unknown:
            return "未知"
        }
    }
}

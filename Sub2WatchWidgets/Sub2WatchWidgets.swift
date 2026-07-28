import SwiftUI
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let summary: WidgetQuotaSummary?
}

struct QuotaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaWidgetEntry {
        QuotaWidgetEntry(date: Date(), summary: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaWidgetEntry) -> Void) {
        completion(
            QuotaWidgetEntry(
                date: Date(),
                summary: WidgetQuotaSummaryStore.load() ?? .placeholder
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaWidgetEntry>) -> Void) {
        let entry = QuotaWidgetEntry(
            date: Date(),
            summary: WidgetQuotaSummaryStore.load()
        )
        completion(
            Timeline(
                entries: [entry],
                policy: .after(Date().addingTimeInterval(15 * 60))
            )
        )
    }
}

@main
struct Sub2WatchWidgets: WidgetBundle {
    var body: some Widget {
        Sub2WatchQuotaWidget()
        Sub2WatchRingQuotaWidget()
        Sub2WatchCornerRingQuotaWidget()
    }
}

struct Sub2WatchQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: SharedWidgetConfiguration.quotaWidgetKind,
            provider: QuotaWidgetProvider()
        ) { entry in
            QuotaWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("额度")
        .description("查看各 AI 平台账号的剩余额度")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
        ])
    }
}

struct Sub2WatchRingQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: SharedWidgetConfiguration.ringQuotaWidgetKind,
            provider: QuotaWidgetProvider()
        ) { entry in
            ConcentricQuotaView(summary: entry.summary)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("额度双环")
        .description("外圈显示 5h，内圈显示 7d 剩余额度")
        .supportedFamilies([.accessoryCircular])
    }
}

struct Sub2WatchCornerRingQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: SharedWidgetConfiguration.cornerRingQuotaWidgetKind,
            provider: QuotaWidgetProvider()
        ) { entry in
            CornerConcentricQuotaView(summary: entry.summary)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("角落双环")
        .description("在表盘角落用双环显示 5h 与 7d 剩余额度")
        .supportedFamilies([.accessoryCorner])
    }
}

private struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaWidgetEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            RectangularQuotaView(summary: entry.summary)
        case .accessoryCircular:
            CircularQuotaView(summary: entry.summary)
        case .accessoryCorner:
            CornerQuotaView(summary: entry.summary)
        case .accessoryInline:
            InlineQuotaView(summary: entry.summary)
        default:
            RectangularQuotaView(summary: entry.summary)
        }
    }
}

private struct RectangularQuotaView: View {
    let summary: WidgetQuotaSummary?

    var body: some View {
        let providers = summary?.providers ?? []
        let isGlobal = providers.count > 1
        let provider = providers.first
        let windows = displayedWindows(summary)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .foregroundStyle(.blue)
                    .widgetAccentable()
                Text(isGlobal ? "AI 额度" : provider?.displayName ?? "额度")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 2)
                Text(headerDetail(providers))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(windows.prefix(2).enumerated()), id: \.offset) { _, window in
                QuotaWidgetRow(
                    label: window.label,
                    remaining: window.remaining,
                    accent: window.accent,
                    usesWideLabel: isGlobal
                )
            }
        }
    }
}

private struct QuotaWidgetRow: View {
    let label: String
    let remaining: Double?
    let accent: Color
    let usesWideLabel: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(accent)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: usesWideLabel ? 48 : 17, alignment: .leading)

            ProgressView(value: remaining ?? 0, total: 100)
                .progressViewStyle(.linear)
                .tint(accent)

            Text(percentText(remaining))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 26, alignment: .trailing)
                .layoutPriority(1)
        }
    }
}

private struct CircularQuotaView: View {
    let summary: WidgetQuotaSummary?

    var body: some View {
        let quota = mostConstrainedQuota(summary)
        CompactQuotaBar(
            label: quota.label,
            remaining: quota.remaining,
            accent: quotaAccent(for: quota.label)
        )
    }
}

private struct ConcentricQuotaView: View {
    let summary: WidgetQuotaSummary?

    var body: some View {
        let windows = displayedWindows(summary)
        let fiveHour = windows.first
        let sevenDay = windows.dropFirst().first

        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)

            ZStack {
                QuotaRing(
                    remaining: fiveHour?.remaining,
                    accent: fiveHour?.accent ?? .purple,
                    lineWidth: 5
                )
                .frame(width: diameter - 3, height: diameter - 3)

                QuotaRing(
                    remaining: sevenDay?.remaining,
                    accent: sevenDay?.accent ?? .mint,
                    lineWidth: 4.5
                )
                .frame(width: diameter - 17, height: diameter - 17)

                VStack(spacing: 0) {
                    RingValueRow(label: "5h", remaining: fiveHour?.remaining)
                    RingValueRow(label: "7d", remaining: sevenDay?.remaining)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cornerAccessibilityLabel(windows))
    }
}

private struct CornerConcentricQuotaView: View {
    let summary: WidgetQuotaSummary?

    var body: some View {
        let windows = displayedWindows(summary)
        let fiveHour = windows.first
        let sevenDay = windows.dropFirst().first

        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)

            ZStack {
                QuotaRing(
                    remaining: fiveHour?.remaining,
                    accent: fiveHour?.accent ?? .purple,
                    lineWidth: 4.5
                )
                .frame(width: diameter - 2, height: diameter - 2)

                QuotaRing(
                    remaining: sevenDay?.remaining,
                    accent: sevenDay?.accent ?? .mint,
                    lineWidth: 4
                )
                .frame(width: diameter - 13, height: diameter - 13)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .widgetLabel {
            Text(cornerRingLabel(windows))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cornerAccessibilityLabel(windows))
    }
}

private struct QuotaRing: View {
    let remaining: Double?
    let accent: Color
    let lineWidth: CGFloat

    private var progress: Double {
        min(max(remaining ?? 0, 0), 100) / 100
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
    }
}

private struct RingValueRow: View {
    let label: String
    let remaining: Double?

    var body: some View {
        Text("\(label) \(percentText(remaining))")
            .font(.system(size: 7, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct CornerQuotaView: View {
    let summary: WidgetQuotaSummary?

    var body: some View {
        let windows = displayedWindows(summary)
        let primaryWindow = windows.dropFirst().first ?? windows.first
        let secondaryWindow = windows.count > 1 ? windows.first : nil

        Group {
            if let secondaryWindow {
                CornerCurvedValue(window: secondaryWindow)
            } else {
                Color.clear
            }
        }
            .widgetLabel {
                if let primaryWindow {
                    CornerQuotaGaugeRow(window: primaryWindow)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cornerAccessibilityLabel(windows))
    }
}

private struct CompactQuotaBar: View {
    let label: String
    let remaining: Double?
    let accent: Color

    private var progress: Double {
        min(max(remaining ?? 0, 0), 100) / 100
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                    .foregroundStyle(accent)
                    .widgetAccentable()
                Text(percentText(remaining))
            }
            .font(.caption2.monospacedDigit().weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.3))
                    Capsule()
                        .fill(accent)
                        .frame(width: proxy.size.width * progress)
                        .widgetAccentable()
                }
            }
            .frame(width: 36, height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) 剩余 \(percentText(remaining))")
    }
}

private struct InlineQuotaView: View {
    let summary: WidgetQuotaSummary?

    var body: some View {
        let windows = displayedWindows(summary)
        Label {
            Text(inlineText(windows))
        } icon: {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }
}

private func percentText(_ value: Double?) -> String {
    value.map { "\(Int($0.rounded()))%" } ?? "--"
}

private func quotaAccent(for label: String) -> Color {
    label.lowercased() == "5h" ? .purple : .mint
}

private func shortWindowLabel(_ label: String) -> String {
    label.split(separator: " ").last.map(String.init) ?? label
}

private func cornerAccessibilityLabel(_ windows: [DisplayedWidgetWindow]) -> String {
    windows.prefix(2).map { window in
        "\(window.providerName) \(shortWindowLabel(window.label)) 剩余 \(percentText(window.remaining))"
    }.joined(separator: "，")
}

private func cornerRingLabel(_ windows: [DisplayedWidgetWindow]) -> String {
    windows.prefix(2).map { window in
        "\(shortWindowLabel(window.label)) \(percentText(window.remaining))"
    }.joined(separator: " · ")
}

private struct DisplayedWidgetWindow {
    let providerName: String
    let label: String
    let remaining: Double?
    let accent: Color
}

private struct CornerQuotaGaugeRow: View {
    let window: DisplayedWidgetWindow

    var body: some View {
        Gauge(value: window.remaining ?? 0, in: 0...100) {
            Text(window.providerName)
        } currentValueLabel: {
            EmptyView()
        } minimumValueLabel: {
            Text(shortWindowLabel(window.label))
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .monospaced()
        } maximumValueLabel: {
            Text(percentText(window.remaining))
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .tint(window.accent)
        .widgetAccentable()
    }
}

private struct CornerCurvedValue: View {
    let window: DisplayedWidgetWindow

    var body: some View {
        Text("\(shortWindowLabel(window.label)) \(percentText(window.remaining))")
            .foregroundStyle(window.accent)
            .monospacedDigit()
            .lineLimit(1)
            .widgetCurvesContent()
    }
}

private func displayedWindows(_ summary: WidgetQuotaSummary?) -> [DisplayedWidgetWindow] {
    guard let providers = summary?.providers, !providers.isEmpty else {
        return [
            DisplayedWidgetWindow(providerName: "Codex", label: "5h", remaining: nil, accent: .purple),
            DisplayedWidgetWindow(providerName: "Codex", label: "7d", remaining: nil, accent: .mint),
        ]
    }

    let isGlobal = providers.count > 1
    let windows = providers.flatMap { provider in
        provider.windows.enumerated().map { index, window in
            DisplayedWidgetWindow(
                providerName: provider.displayName,
                label: isGlobal ? "\(provider.displayName) \(window.label)" : window.label,
                remaining: window.remainingPercent,
                accent: windowAccent(window, index: index)
            )
        }
    }
    if isGlobal {
        return windows.sorted { ($0.remaining ?? 101) < ($1.remaining ?? 101) }
    }
    return windows
}

private func mostConstrainedQuota(
    _ summary: WidgetQuotaSummary?
) -> (providerName: String, label: String, remaining: Double?) {
    let windows = displayedWindows(summary)
    guard let quota = windows
        .filter({ $0.remaining != nil })
        .min(by: { ($0.remaining ?? 101) < ($1.remaining ?? 101) }) ?? windows.first else {
        return ("额度", "--", nil)
    }
    let shortLabel = quota.label.split(separator: " ").last.map(String.init) ?? quota.label
    return (quota.providerName, shortLabel, quota.remaining)
}

private func headerDetail(_ providers: [WidgetProviderQuotaSummary]) -> String {
    guard !providers.isEmpty else { return "--" }
    if providers.count > 1 { return "\(providers.count) AI" }
    guard let provider = providers.first else { return "--" }
    return "\(provider.reportingAccountCount)/\(provider.accountCount)"
}

private func inlineText(_ windows: [DisplayedWidgetWindow]) -> String {
    windows.prefix(2).map { window in
        "\(window.label) \(percentText(window.remaining))"
    }.joined(separator: " · ")
}

private func windowAccent(_ window: WidgetQuotaWindowSummary, index: Int) -> Color {
    let normalized = window.id.lowercased()
    if normalized.contains("5h") { return .purple }
    if normalized.contains("7d") { return .mint }
    return index.isMultiple(of: 2) ? .blue : .green
}

private extension WidgetQuotaSummary {
    static let placeholder = WidgetQuotaSummary(
        providers: [
            WidgetProviderQuotaSummary(
                id: "codex",
                displayName: "Codex",
                accountCount: 5,
                reportingAccountCount: 5,
                windows: [
                    WidgetQuotaWindowSummary(
                        id: "5h",
                        label: "5h",
                        remainingPercent: 68,
                        requests: 1_240,
                        tokens: 150_000_000
                    ),
                    WidgetQuotaWindowSummary(
                        id: "7d",
                        label: "7d",
                        remainingPercent: 42,
                        requests: 10_300,
                        tokens: 1_200_000_000
                    ),
                ]
            ),
        ],
        updatedAt: Date()
    )
}

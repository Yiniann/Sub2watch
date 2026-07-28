import Charts
import Foundation
import SwiftUI

struct UsageDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsPeriodPicker = false

    private let columns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7),
    ]

    private var errorMessages: [String] {
        [
            model.usageErrorMessage,
            model.modelStatsErrorMessage,
            model.usageTrendErrorMessage,
        ].compactMap { message in
            guard let message, !message.isEmpty else { return nil }
            return message
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let stats = model.usageStats {
                    VStack(spacing: 0) {
                        LazyVGrid(columns: columns, spacing: 7) {
                            DashboardMetricTile(
                                title: "今日请求",
                                systemImage: "arrow.up.arrow.down",
                                value: stats.todayRequests.compactFormatted,
                                footer: "累计 \(stats.totalRequests.compactFormatted)",
                                color: .cyan
                            )
                            DashboardMetricTile(
                                title: "今日 Token",
                                systemImage: "text.word.spacing",
                                value: stats.todayTokens.compactFormatted,
                                footer: "累计 \(stats.totalTokens.compactFormatted)",
                                color: .indigo
                            )
                            DashboardMetricTile(
                                title: "当前吞吐",
                                systemImage: "gauge.with.dots.needle.50percent",
                                value: "\(stats.requestsPerMinute.compactFormatted) RPM",
                                footer: "\(stats.tokensPerMinute.compactFormatted) TPM",
                                color: .green
                            )
                            DashboardMetricTile(
                                title: "今日费用",
                                systemImage: "dollarsign.circle",
                                value: stats.todayActualCost.compactCurrencyFormatted,
                                footer: "累计 \(stats.totalActualCost.compactCurrencyFormatted)",
                                color: .orange
                            )
                        }
                    }
                    .scrollTargetLayout()

                    HStack(alignment: .firstTextBaseline) {
                        Text("统计分析")
                            .font(.headline)
                        Spacer()
                        Button {
                            showsPeriodPicker = true
                        } label: {
                            HStack(spacing: 2) {
                                if model.isRefreshingModelStats {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Text(model.modelStatsPeriod.title)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isRefreshingModelStats)
                    }
                    .sheet(isPresented: $showsPeriodPicker) {
                        ModelStatsPeriodPicker(
                            selectedPeriod: model.modelStatsPeriod
                        ) { period in
                            Task { await model.selectModelStatsPeriod(period) }
                        }
                    }

                    if let modelStats = model.modelUsageStats {
                        ModelDistributionView(stats: modelStats)
                            .id(model.modelStatsPeriod)
                    }

                    VStack(spacing: 0) {
                        TokenTrendView(stats: model.usageTrend)
                            .id(model.modelStatsPeriod)
                    }
                    .scrollTargetLayout()
                } else if model.isRefreshingUsage {
                    ProgressView("正在读取统计")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ContentUnavailableView(
                        "暂无用量统计",
                        systemImage: "chart.bar.xaxis"
                    )
                }
            }

            if !errorMessages.isEmpty {
                Label {
                    Text(errorMessages.joined(separator: "\n"))
                        .lineLimit(3)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 5)
        .dashboardTopScrollEdgeEffect()
        .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        .refreshable {
            await model.refreshUsageData()
        }
    }
}

private extension View {
    @ViewBuilder
    func dashboardTopScrollEdgeEffect() -> some View {
        if #available(watchOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

private struct TokenTrendView: View {
    @EnvironmentObject private var model: AppModel
    let stats: UsageTrendResponse?
    @State private var visibleKinds: Set<TokenTrendKind> = [.input, .output]

    private var points: [UsageTrendPoint] {
        (stats?.trend ?? []).sorted { $0.date < $1.date }
    }

    private var maximumValue: Double {
        let maximum = points.flatMap { point in
            visibleKinds.map { Double($0.value(in: point)) }
        }.max() ?? 0
        return max(1, maximum * 1.08)
    }

    private var displayedKinds: [TokenTrendKind] {
        TokenTrendKind.allCases.filter(visibleKinds.contains)
    }

    private var axisIndexes: [Int] {
        guard points.count > 1 else { return points.isEmpty ? [] : [0] }
        return Array(Set([0, points.count / 2, points.count - 1])).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token 使用趋势")
                .font(.headline)

            if model.isRefreshingModelStats && stats == nil {
                ProgressView("正在读取趋势")
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else if points.isEmpty {
                ContentUnavailableView(
                    "该时段暂无趋势数据",
                    systemImage: "chart.xyaxis.line"
                )
                .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                Chart {
                    ForEach(displayedKinds) { kind in
                        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                            LineMark(
                                x: .value("时间", index),
                                y: .value(kind.title, kind.value(in: point)),
                                series: .value("类型", kind.title)
                            )
                            .foregroundStyle(kind.color)
                            .lineStyle(
                                StrokeStyle(
                                    lineWidth: 2,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartYScale(domain: 0...maximumValue)
                .chartXAxis {
                    AxisMarks(values: axisIndexes) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let index = value.as(Int.self), points.indices.contains(index) {
                                Text(axisLabel(for: points[index].date))
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(Int64(amount).compactFormatted)
                                    .font(.system(size: 8).monospacedDigit())
                            }
                        }
                    }
                }
                .frame(height: 132)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(TokenTrendKind.allCases) { kind in
                    Button {
                        toggle(kind)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(visibleKinds.contains(kind) ? kind.color : .secondary)
                                .frame(width: 11)
                            Text(kind.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .opacity(visibleKinds.contains(kind) ? 1 : 0.45)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(visibleKinds.contains(kind) ? "已显示" : "已隐藏")
                }
            }
        }
    }

    private func toggle(_ kind: TokenTrendKind) {
        if visibleKinds.contains(kind) {
            guard visibleKinds.count > 1 else { return }
            visibleKinds.remove(kind)
        } else {
            visibleKinds.insert(kind)
        }
    }

    private func axisLabel(for value: String) -> String {
        if stats?.granularity == "hour" {
            return String(value.suffix(5))
        }
        let components = value.split(separator: "-")
        guard components.count == 3 else { return value }
        return "\(components[1])/\(components[2])"
    }
}

private enum TokenTrendKind: String, CaseIterable, Identifiable {
    case input
    case output
    case cacheCreation
    case cacheRead

    var id: String { rawValue }

    var title: String {
        switch self {
        case .input: "输入"
        case .output: "输出"
        case .cacheCreation: "缓存写入"
        case .cacheRead: "缓存读取"
        }
    }

    var systemImage: String {
        switch self {
        case .input: "arrow.down.circle.fill"
        case .output: "arrow.up.circle.fill"
        case .cacheCreation: "square.and.arrow.down.fill"
        case .cacheRead: "bolt.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .input: .blue
        case .output: .green
        case .cacheCreation: .orange
        case .cacheRead: .cyan
        }
    }

    func value(in point: UsageTrendPoint) -> Int64 {
        switch self {
        case .input: point.inputTokens
        case .output: point.outputTokens
        case .cacheCreation: point.cacheCreationTokens
        case .cacheRead: point.cacheReadTokens
        }
    }
}

private struct ModelDistributionView: View {
    let stats: ModelUsageStatsResponse
    @State private var selectedModelID: String?

    private let colors: [Color] = [.blue, .mint, .orange, .pink, .gray]

    private var sourceItems: [ModelUsageStat] {
        stats.models
            .filter { $0.totalTokens > 0 }
            .sorted { $0.totalTokens > $1.totalTokens }
    }

    private var items: [ModelDistributionItem] {
        let leadingItems = Array(sourceItems.prefix(4))
        var result = leadingItems.enumerated().map { index, item in
            ModelDistributionItem(
                id: item.model,
                model: item.model,
                requestCount: item.requests,
                tokens: item.totalTokens,
                actualCost: item.actualCost,
                color: colors[index]
            )
        }

        let remainingItems = sourceItems.dropFirst(4)
        let remainingTokens = remainingItems.reduce(Int64(0)) { $0 + $1.totalTokens }
        if remainingTokens > 0 {
            let remainingCosts = remainingItems.map(\.actualCost)
            result.append(
                ModelDistributionItem(
                    id: "other-models",
                    model: "其他",
                    requestCount: remainingItems.reduce(Int64(0)) { $0 + $1.requests },
                    tokens: remainingTokens,
                    actualCost: remainingCosts.reduce(0, +),
                    color: colors[4]
                )
            )
        }
        return result
    }

    private var totalTokens: Int64 {
        items.reduce(Int64(0)) { $0 + $1.tokens }
    }

    private var selectedItem: ModelDistributionItem? {
        items.first { $0.id == selectedModelID }
    }

    private func item(at value: Double) -> ModelDistributionItem? {
        var upperBound = 0.0
        for item in items {
            upperBound += Double(item.tokens)
            if value <= upperBound {
                return item
            }
        }
        return items.last
    }

    private func select(_ item: ModelDistributionItem) {
        selectedModelID = selectedModelID == item.id ? nil : item.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("模型分布")
                    .font(.headline)

                if items.isEmpty {
                    ContentUnavailableView(
                        "该时段暂无模型数据",
                        systemImage: "chart.pie"
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    Chart(items) { item in
                        SectorMark(
                            angle: .value("Token", Double(item.tokens)),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .cornerRadius(2)
                        .foregroundStyle(item.color)
                        .opacity(selectedModelID == nil || selectedModelID == item.id ? 1 : 0.32)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 112)
                    .chartOverlay { _ in
                        GeometryReader { geometry in
                            Color.clear
                                .contentShape(Circle())
                                .simultaneousGesture(
                                    SpatialTapGesture()
                                        .onEnded { event in
                                            let center = CGPoint(
                                                x: geometry.size.width / 2,
                                                y: geometry.size.height / 2
                                            )
                                            let dx = event.location.x - center.x
                                            let dy = event.location.y - center.y
                                            let distance = hypot(dx, dy)
                                            let outerRadius = min(
                                                geometry.size.width,
                                                geometry.size.height
                                            ) / 2
                                            guard distance >= outerRadius * 0.58,
                                                  distance <= outerRadius else { return }

                                            var angle = atan2(dx, -dy)
                                            if angle < 0 { angle += 2 * .pi }
                                            let tokenValue = angle / (2 * .pi) * Double(totalTokens)
                                            if let item = item(at: tokenValue) {
                                                select(item)
                                            }
                                        }
                                )
                        }
                    }
                    .overlay {
                        VStack(spacing: 0) {
                            Text(selectedItem.map { percentage(for: $0) } ?? totalTokens.compactFormatted)
                                .font(.headline.monospacedDigit().bold())
                            Text(selectedItem?.model ?? "总计")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .frame(maxWidth: 82)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }

            if !items.isEmpty {
                VStack(spacing: 3) {
                    ForEach(items) { item in
                        Button {
                            select(item)
                        } label: {
                            ModelDistributionLegendItem(
                                item: item,
                                totalTokens: totalTokens,
                                isSelected: selectedModelID == item.id
                            )
                        }
                        .buttonStyle(.plain)

                        if selectedModelID == item.id {
                            ModelDistributionDetailRow(item: item)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: selectedModelID)
            }
        }
        .scrollTargetLayout()
    }

    private func percentage(for item: ModelDistributionItem) -> String {
        guard totalTokens > 0 else { return "0%" }
        return (Double(item.tokens) / Double(totalTokens))
            .formatted(.percent.precision(.fractionLength(1)))
    }
}

private struct ModelStatsPeriodPicker: View {
    @Environment(\.dismiss) private var dismiss
    let selectedPeriod: ModelStatsPeriod
    let onSelect: (ModelStatsPeriod) -> Void

    var body: some View {
        NavigationStack {
            List(ModelStatsPeriod.allCases) { period in
                Button {
                    dismiss()
                    onSelect(period)
                } label: {
                    HStack {
                        Text(period.title)
                        Spacer()
                        if period == selectedPeriod {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("统计时间")
        }
    }
}

private struct ModelDistributionItem: Identifiable {
    let id: String
    let model: String
    let requestCount: Int64
    let tokens: Int64
    let actualCost: Double?
    let color: Color
}

private struct ModelDistributionLegendItem: View {
    let item: ModelDistributionItem
    let totalTokens: Int64
    let isSelected: Bool

    private var percentage: Double {
        guard totalTokens > 0 else { return 0 }
        return Double(item.tokens) / Double(totalTokens)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(item.color)
                .frame(width: 8, height: 8)
            Text(item.model)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 4)
            Text(percentage, format: .percent.precision(.fractionLength(1)))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isSelected ? item.color : .secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }
}

private struct ModelDistributionDetailRow: View {
    let item: ModelDistributionItem

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text("请求 \(item.requestCount.compactFormatted)")
                Spacer()
                Text("Token \(item.tokens.compactFormatted)")
            }
            HStack {
                Text("实际费用")
                Spacer()
                Text(item.actualCost?.compactCurrencyFormatted ?? "--")
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.leading, 14)
        .padding(.bottom, 3)
    }
}

private struct DashboardMetricTile: View {
    let title: String
    let systemImage: String
    let value: String
    let footer: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .frame(width: 13)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
                .font(.caption2)
                .foregroundStyle(color)

            Spacer(minLength: 2)

            Text(value)
                .font(.title3.monospacedDigit().bold())
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(footer)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .topLeading)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension Int64 {
    var compactFormatted: String {
        formatted(.number.notation(.compactName))
    }
}

extension Double {
    var compactCurrencyFormatted: String {
        if abs(self) >= 1_000_000 {
            return String(format: "$%.1fM", self / 1_000_000)
        }
        if abs(self) >= 1_000 {
            return String(format: "$%.1fK", self / 1_000)
        }
        if abs(self) < 1 {
            return String(format: "$%.3f", self)
        }
        return String(format: "$%.2f", self)
    }

    var durationFormatted: String {
        if self >= 1_000 {
            return String(format: "%.1f s", self / 1_000)
        }
        return String(format: "%.0f ms", self)
    }
}

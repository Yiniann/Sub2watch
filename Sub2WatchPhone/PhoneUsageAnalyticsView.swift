import Charts
import Foundation
import SwiftUI

struct PhoneUsageAnalyticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("统计分析")
                    .font(.headline)

                Spacer()

                Menu {
                    ForEach(ModelStatsPeriod.allCases) { period in
                        Button {
                            Task { await model.selectModelStatsPeriod(period) }
                        } label: {
                            if period == model.modelStatsPeriod {
                                Label(period.title, systemImage: "checkmark")
                            } else {
                                Text(period.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if model.isRefreshingModelStats {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "calendar")
                        }
                        Text(model.modelStatsPeriod.title)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .disabled(model.isRefreshingModelStats)
            }
            .padding(.horizontal, 2)

            PhoneModelDistributionView(stats: model.modelUsageStats)
                .id(model.modelStatsPeriod)

            PhoneTokenTrendView(stats: model.usageTrend)
                .id(model.modelStatsPeriod)
        }
    }
}

private struct PhoneModelDistributionView: View {
    let stats: ModelUsageStatsResponse?
    @State private var selectedModelID: String?
    @State private var selectedAngle: Double?

    private let colors: [Color] = [.blue, .mint, .orange, .pink, .gray]

    private var sourceItems: [ModelUsageStat] {
        (stats?.models ?? [])
            .filter { $0.totalTokens > 0 }
            .sorted { $0.totalTokens > $1.totalTokens }
    }

    private var items: [PhoneModelDistributionItem] {
        var result = sourceItems.prefix(4).enumerated().map { index, item in
            PhoneModelDistributionItem(
                id: item.model,
                model: item.model,
                requestCount: item.requests,
                tokens: item.totalTokens,
                actualCost: item.actualCost,
                color: colors[index]
            )
        }

        let remaining = sourceItems.dropFirst(4)
        let remainingTokens = remaining.reduce(Int64(0)) { $0 + $1.totalTokens }
        if remainingTokens > 0 {
            result.append(
                PhoneModelDistributionItem(
                    id: "other-models",
                    model: "其他",
                    requestCount: remaining.reduce(Int64(0)) { $0 + $1.requests },
                    tokens: remainingTokens,
                    actualCost: remaining.reduce(0) { $0 + $1.actualCost },
                    color: colors[4]
                )
            )
        }
        return result
    }

    private var totalTokens: Int64 {
        items.reduce(Int64(0)) { $0 + $1.tokens }
    }

    private var selectedItem: PhoneModelDistributionItem? {
        items.first { $0.id == selectedModelID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("模型分布", systemImage: "chart.pie.fill")
                .font(.headline)

            if items.isEmpty {
                ContentUnavailableView(
                    "该时段暂无模型数据",
                    systemImage: "chart.pie"
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(items) { item in
                    SectorMark(
                        angle: .value("Token", Double(item.tokens)),
                        innerRadius: .ratio(0.64),
                        angularInset: 1.6
                    )
                    .cornerRadius(3)
                    .foregroundStyle(item.color)
                    .opacity(selectedModelID == nil || selectedModelID == item.id ? 1 : 0.28)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngle)
                .frame(height: 190)
                .overlay {
                    VStack(spacing: 2) {
                        Text(selectedItem.map(percentage) ?? phoneAnalyticsNumber(totalTokens))
                            .font(.title3.monospacedDigit().bold())
                        Text(selectedItem?.model ?? "总 Token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: 110)
                    }
                    .allowsHitTesting(false)
                }
                .onChange(of: selectedAngle) { _, angle in
                    guard let angle else { return }
                    selectedModelID = item(at: angle)?.id
                }

                VStack(spacing: 2) {
                    ForEach(items) { item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedModelID = selectedModelID == item.id ? nil : item.id
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 9, height: 9)
                                Text(item.model)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Spacer(minLength: 8)
                                Text(percentage(item))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(selectedModelID == item.id ? item.color : .secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)

                        if selectedModelID == item.id {
                            HStack(spacing: 8) {
                                PhoneAnalysisDetailMetric(
                                    title: "请求",
                                    value: phoneAnalyticsNumber(item.requestCount)
                                )
                                PhoneAnalysisDetailMetric(
                                    title: "Token",
                                    value: phoneAnalyticsNumber(item.tokens)
                                )
                                PhoneAnalysisDetailMetric(
                                    title: "实际费用",
                                    value: phoneAnalyticsCurrency(item.actualCost)
                                )
                            }
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func item(at angle: Double) -> PhoneModelDistributionItem? {
        var upperBound = 0.0
        for item in items {
            upperBound += Double(item.tokens)
            if angle <= upperBound { return item }
        }
        return items.last
    }

    private func percentage(_ item: PhoneModelDistributionItem) -> String {
        guard totalTokens > 0 else { return "0%" }
        return (Double(item.tokens) / Double(totalTokens))
            .formatted(.percent.precision(.fractionLength(1)))
    }
}

private struct PhoneAnalysisDetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct PhoneModelDistributionItem: Identifiable {
    let id: String
    let model: String
    let requestCount: Int64
    let tokens: Int64
    let actualCost: Double
    let color: Color
}

private struct PhoneTokenTrendView: View {
    @EnvironmentObject private var model: AppModel
    let stats: UsageTrendResponse?
    @State private var visibleKinds: Set<PhoneTokenTrendKind> = [.input, .output]

    private var points: [UsageTrendPoint] {
        (stats?.trend ?? []).sorted { $0.date < $1.date }
    }

    private var displayedKinds: [PhoneTokenTrendKind] {
        PhoneTokenTrendKind.allCases.filter(visibleKinds.contains)
    }

    private var maximumValue: Double {
        let maximum = points.flatMap { point in
            displayedKinds.map { Double($0.value(in: point)) }
        }.max() ?? 0
        return max(1, maximum * 1.08)
    }

    private var axisIndexes: [Int] {
        guard points.count > 1 else { return points.isEmpty ? [] : [0] }
        return Array(Set([0, points.count / 2, points.count - 1])).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Token 使用趋势", systemImage: "chart.xyaxis.line")
                .font(.headline)

            if model.isRefreshingModelStats && stats == nil {
                ProgressView("正在读取趋势")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if points.isEmpty {
                ContentUnavailableView(
                    "该时段暂无趋势数据",
                    systemImage: "chart.xyaxis.line"
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Chart {
                    ForEach(displayedKinds) { kind in
                        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                            LineMark(
                                x: .value("时间", index),
                                y: .value(kind.title, Double(kind.value(in: point))),
                                series: .value("类型", kind.title)
                            )
                            .foregroundStyle(kind.color)
                            .lineStyle(
                                StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                            )
                            .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartYScale(domain: 0...maximumValue)
                .chartXAxis {
                    AxisMarks(values: axisIndexes) { value in
                        AxisGridLine()
                            .foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let index = value.as(Int.self), points.indices.contains(index) {
                                Text(axisLabel(for: points[index].date))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(.quaternary)
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(phoneAnalyticsNumber(Int64(amount)))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .frame(height: 220)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(PhoneTokenTrendKind.allCases) { kind in
                    Button {
                        toggle(kind)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: kind.systemImage)
                                .foregroundStyle(visibleKinds.contains(kind) ? kind.color : .secondary)
                                .frame(width: 18)
                            Text(kind.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .opacity(visibleKinds.contains(kind) ? 1 : 0.45)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(visibleKinds.contains(kind) ? "已显示" : "已隐藏")
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toggle(_ kind: PhoneTokenTrendKind) {
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

private enum PhoneTokenTrendKind: String, CaseIterable, Identifiable {
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

private func phoneAnalyticsNumber(_ value: Int64) -> String {
    value.formatted(.number.notation(.compactName))
}

private func phoneAnalyticsCurrency(_ value: Double) -> String {
    value.formatted(.currency(code: "USD").precision(.fractionLength(2...2)))
}

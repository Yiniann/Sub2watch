import Foundation

enum SharedWidgetConfiguration {
    static let appGroupIdentifier = "group.com.yinian.Sub2Watch"
    static let quotaWidgetKind = "Sub2WatchQuotaWidget"
    static let ringQuotaWidgetKind = "Sub2WatchRingQuotaWidget"
    static let cornerRingQuotaWidgetKind = "Sub2WatchCornerRingQuotaWidget"
}

struct WidgetQuotaWindowSummary: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let remainingPercent: Double?
    let requests: Int64?
    let tokens: Int64?
}

struct WidgetProviderQuotaSummary: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let accountCount: Int
    let reportingAccountCount: Int
    let windows: [WidgetQuotaWindowSummary]
}

struct WidgetQuotaSummary: Codable, Equatable, Sendable {
    let providers: [WidgetProviderQuotaSummary]
    let updatedAt: Date
}

struct WidgetQuotaSummaryStore {
    private static let key = "widget-quota-summary-v2"

    static func load() -> WidgetQuotaSummary? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetQuotaSummary.self, from: data)
    }

    static func save(_ summary: WidgetQuotaSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedWidgetConfiguration.appGroupIdentifier) ?? .standard
    }
}

import Foundation

struct DashboardCache: Codable {
    let accounts: [CodexAccount]
    let liveSnapshots: [Int: AccountQuotaSnapshot]
    let providerSnapshots: [Int: ProviderQuotaSnapshot]?
    let accountUsageWindows: [Int: AccountUsageWindows]?
    let usageStats: DashboardUsageStats?
    let openAITokenStats: OpenAITokenStatsResponse?
    let modelUsageStats: ModelUsageStatsResponse?
    let usageTrend: UsageTrendResponse?
    let modelStatsPeriodRawValue: String?
    let etag: String?
    let accountScopeVersion: Int?
    let userPlatformQuotas: [UserPlatformQuota]?
    let userAPIKeys: [UserAPIKey]?
    let userSubscriptions: [UserSubscriptionSummary]?
    let savedAt: Date
}

struct DashboardCacheStore {
    private let keyPrefix = "dashboard-cache-v2"

    func load(scope: String) -> DashboardCache? {
        guard let data = UserDefaults.standard.data(forKey: key(scope: scope)) else { return nil }
        return try? JSONDecoder().decode(DashboardCache.self, from: data)
    }

    func save(_ cache: DashboardCache, scope: String) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key(scope: scope))
    }

    func clear(scope: String) {
        UserDefaults.standard.removeObject(forKey: key(scope: scope))
    }

    private func key(scope: String) -> String {
        "\(keyPrefix)-\(scope)"
    }
}

struct DeviceSyncSnapshotStore {
    private let key = "phone-sync-snapshot-v1"

    func load() -> DeviceSyncSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DeviceSyncSnapshot.self, from: data)
    }

    func save(_ snapshot: DeviceSyncSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

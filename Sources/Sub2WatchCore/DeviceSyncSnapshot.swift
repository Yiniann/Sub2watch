import Foundation

public struct DeviceSyncSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let isConfigured: Bool
    public let isAdministrator: Bool
    public let user: AuthenticatedUser?
    public let accounts: [CodexAccount]
    public let liveSnapshots: [Int: AccountQuotaSnapshot]
    public let providerSnapshots: [Int: ProviderQuotaSnapshot]
    public let accountUsageWindows: [Int: AccountUsageWindows]
    public let usageStats: DashboardUsageStats?
    public let openAITokenStats: OpenAITokenStatsResponse?
    public let modelUsageStats: ModelUsageStatsResponse?
    public let usageTrend: UsageTrendResponse?
    public let userPlatformQuotas: [UserPlatformQuota]
    public let userAPIKeys: [UserAPIKey]
    public let userSubscriptions: [UserSubscriptionSummary]
    public let modelStatsPeriodRawValue: String
    public let savedAt: Date

    public init(
        schemaVersion: Int = DeviceSyncSnapshot.currentSchemaVersion,
        isConfigured: Bool,
        isAdministrator: Bool,
        user: AuthenticatedUser?,
        accounts: [CodexAccount],
        liveSnapshots: [Int: AccountQuotaSnapshot],
        providerSnapshots: [Int: ProviderQuotaSnapshot],
        accountUsageWindows: [Int: AccountUsageWindows],
        usageStats: DashboardUsageStats?,
        openAITokenStats: OpenAITokenStatsResponse?,
        modelUsageStats: ModelUsageStatsResponse?,
        usageTrend: UsageTrendResponse?,
        userPlatformQuotas: [UserPlatformQuota],
        userAPIKeys: [UserAPIKey],
        userSubscriptions: [UserSubscriptionSummary],
        modelStatsPeriodRawValue: String,
        savedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.isConfigured = isConfigured
        self.isAdministrator = isAdministrator
        self.user = user
        self.accounts = accounts
        self.liveSnapshots = liveSnapshots
        self.providerSnapshots = providerSnapshots
        self.accountUsageWindows = accountUsageWindows
        self.usageStats = usageStats
        self.openAITokenStats = openAITokenStats
        self.modelUsageStats = modelUsageStats
        self.usageTrend = usageTrend
        self.userPlatformQuotas = userPlatformQuotas
        self.userAPIKeys = userAPIKeys
        self.userSubscriptions = userSubscriptions
        self.modelStatsPeriodRawValue = modelStatsPeriodRawValue
        self.savedAt = savedAt
    }
}

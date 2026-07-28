import Foundation

public enum ConfigurationError: LocalizedError, Equatable {
    case missingURL
    case invalidURL
    case insecureHTTPDisabled
    case missingAPIKey
    case missingEmail
    case missingPassword

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            return "请输入 Sub2API 服务地址"
        case .invalidURL:
            return "服务地址必须是有效的 HTTP 或 HTTPS 地址"
        case .insecureHTTPDisabled:
            return "HTTP 会明文传输登录凭据，请先开启允许 HTTP"
        case .missingAPIKey:
            return "请输入管理员密钥"
        case .missingEmail:
            return "请输入邮箱"
        case .missingPassword:
            return "请输入密码"
        }
    }
}

public enum AuthenticationMode: String, Codable, Equatable, Sendable {
    case accountSession
    case adminAPIKey
}

public enum UserRole: String, Codable, Equatable, Sendable {
    case admin
    case user
}

public struct AuthenticatedUser: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let email: String
    public let username: String?
    public let role: UserRole
    public let balance: Double
    public let status: String
}

public struct ServerConfiguration: Codable, Equatable, Sendable {
    public let apiBaseURL: URL
    public let adminAPIKey: String
    public let allowsInsecureHTTP: Bool
    public let authenticationMode: AuthenticationMode
    public let accessToken: String?
    public let refreshToken: String?
    public let accessTokenExpiresAt: Date?
    public let user: AuthenticatedUser?

    public init(apiBaseURL: URL, adminAPIKey: String, allowsInsecureHTTP: Bool) {
        self.apiBaseURL = apiBaseURL
        self.adminAPIKey = adminAPIKey
        self.allowsInsecureHTTP = allowsInsecureHTTP
        authenticationMode = .adminAPIKey
        accessToken = nil
        refreshToken = nil
        accessTokenExpiresAt = nil
        user = nil
    }

    public init(
        apiBaseURL: URL,
        allowsInsecureHTTP: Bool,
        accessToken: String,
        refreshToken: String?,
        accessTokenExpiresAt: Date?,
        user: AuthenticatedUser
    ) {
        self.apiBaseURL = apiBaseURL
        adminAPIKey = ""
        self.allowsInsecureHTTP = allowsInsecureHTTP
        authenticationMode = .accountSession
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.user = user
    }

    public var role: UserRole { user?.role ?? .admin }
    public var isAdministrator: Bool { role == .admin }

    public var cacheScopeIdentifier: String {
        let identity: String
        switch authenticationMode {
        case .accountSession:
            identity = "user:\(user?.id ?? 0)"
        case .adminAPIKey:
            identity = "admin-key:\(adminAPIKey)"
        }
        let source = "\(apiBaseURL.absoluteString)|\(authenticationMode.rawValue)|\(identity)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    public func replacingTokens(
        accessToken: String,
        refreshToken newRefreshToken: String?,
        expiresIn: Int?,
        now: Date = Date()
    ) -> ServerConfiguration {
        guard let user else { return self }
        return ServerConfiguration(
            apiBaseURL: apiBaseURL,
            allowsInsecureHTTP: allowsInsecureHTTP,
            accessToken: accessToken,
            refreshToken: newRefreshToken ?? refreshToken,
            accessTokenExpiresAt: expiresIn.map {
                now.addingTimeInterval(TimeInterval($0))
            },
            user: user
        )
    }

    public func replacingUser(_ user: AuthenticatedUser) -> ServerConfiguration {
        ServerConfiguration(
            apiBaseURL: apiBaseURL,
            allowsInsecureHTTP: allowsInsecureHTTP,
            accessToken: accessToken ?? "",
            refreshToken: refreshToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            user: user
        )
    }

    public static func validated(
        baseURLText: String,
        adminAPIKey: String,
        allowsInsecureHTTP: Bool
    ) throws -> ServerConfiguration {
        let normalizedURL = try normalizedAPIBaseURL(
            baseURLText: baseURLText,
            allowsInsecureHTTP: allowsInsecureHTTP
        )
        let trimmedKey = adminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ConfigurationError.missingAPIKey
        }
        return ServerConfiguration(
            apiBaseURL: normalizedURL,
            adminAPIKey: trimmedKey,
            allowsInsecureHTTP: allowsInsecureHTTP
        )
    }

    public static func normalizedAPIBaseURL(
        baseURLText: String,
        allowsInsecureHTTP: Bool
    ) throws -> URL {
        let trimmedURL = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            throw ConfigurationError.missingURL
        }
        guard var components = URLComponents(string: trimmedURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            throw ConfigurationError.invalidURL
        }
        if scheme == "http" && !allowsInsecureHTTP {
            throw ConfigurationError.insecureHTTPDisabled
        }

        components.query = nil
        components.fragment = nil
        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix("/api/v1") {
            components.path = path
        } else if path.isEmpty || path == "/" {
            components.path = "/api/v1"
        } else {
            components.path = path + "/api/v1"
        }

        guard let normalizedURL = components.url else {
            throw ConfigurationError.invalidURL
        }
        return normalizedURL
    }

    private enum CodingKeys: String, CodingKey {
        case apiBaseURL
        case adminAPIKey
        case allowsInsecureHTTP
        case authenticationMode
        case accessToken
        case refreshToken
        case accessTokenExpiresAt
        case user
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiBaseURL = try container.decode(URL.self, forKey: .apiBaseURL)
        adminAPIKey = try container.decodeIfPresent(String.self, forKey: .adminAPIKey) ?? ""
        allowsInsecureHTTP = try container.decode(Bool.self, forKey: .allowsInsecureHTTP)
        authenticationMode = try container.decodeIfPresent(
            AuthenticationMode.self,
            forKey: .authenticationMode
        ) ?? .adminAPIKey
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        accessTokenExpiresAt = try container.decodeIfPresent(Date.self, forKey: .accessTokenExpiresAt)
        user = try container.decodeIfPresent(AuthenticatedUser.self, forKey: .user)
    }
}

public struct LoginRequest: Encodable, Sendable {
    public let email: String
    public let password: String
    public let turnstileToken: String

    private enum CodingKeys: String, CodingKey {
        case email
        case password
        case turnstileToken = "turnstile_token"
    }
}

public struct LoginResult: Decodable, Sendable {
    public let accessToken: String?
    public let refreshToken: String?
    public let expiresIn: Int?
    public let tokenType: String?
    public let user: AuthenticatedUser?
    public let requires2FA: Bool
    public let tempToken: String?
    public let userEmailMasked: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
        case requires2FA = "requires_2fa"
        case tempToken = "temp_token"
        case userEmailMasked = "user_email_masked"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        user = try container.decodeIfPresent(AuthenticatedUser.self, forKey: .user)
        requires2FA = try container.decodeIfPresent(Bool.self, forKey: .requires2FA) ?? false
        tempToken = try container.decodeIfPresent(String.self, forKey: .tempToken)
        userEmailMasked = try container.decodeIfPresent(String.self, forKey: .userEmailMasked)
    }
}

public struct RefreshTokenResult: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

public struct APIEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    public let code: Int
    public let message: String
    public let data: Value
}

public struct PaginatedData<Item: Codable & Sendable>: Codable, Sendable {
    public let items: [Item]
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let pages: Int

    private enum CodingKeys: String, CodingKey {
        case items
        case total
        case page
        case pageSize = "page_size"
        case pages
    }
}

public struct CodexAccount: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let platform: String
    public let type: String
    public let status: String
    public let schedulable: Bool
    public let errorMessage: String?
    public let parentAccountID: Int?
    public let extra: CodexAccountExtra?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case platform
        case type
        case status
        case schedulable
        case errorMessage = "error_message"
        case parentAccountID = "parent_account_id"
        case extra
    }
}

public extension CodexAccount {
    var supportsCodexQuota: Bool {
        platform.caseInsensitiveCompare("openai") == .orderedSame &&
            type.caseInsensitiveCompare("oauth") == .orderedSame
    }

    var providerID: String {
        if supportsCodexQuota { return "codex" }
        let normalized = platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? "unknown" : normalized
    }

    var providerDisplayName: String {
        if supportsCodexQuota { return "Codex" }
        switch providerID {
        case "anthropic", "claude": return "Claude"
        case "gemini", "google": return "Gemini"
        case "antigravity": return "Antigravity"
        case "grok": return "Grok"
        case "openai": return "OpenAI"
        case "deepseek": return "DeepSeek"
        case "qwen", "dashscope": return "Qwen"
        case "unknown": return "其他"
        default: return platform.capitalized
        }
    }

    var supportsProviderUsage: Bool {
        switch providerID {
        case "codex":
            return true
        case "anthropic", "claude":
            return type == "oauth" || type == "setup-token"
        case "gemini", "google":
            return true
        case "antigravity", "grok":
            return type == "oauth"
        default:
            return false
        }
    }
}

public struct CodexAccountExtra: Codable, Hashable, Sendable {
    public let fiveHourUsedPercent: Double?
    public let fiveHourResetAfterSeconds: Int?
    public let fiveHourResetAt: String?
    public let sevenDayUsedPercent: Double?
    public let sevenDayResetAfterSeconds: Int?
    public let sevenDayResetAt: String?
    public let usageUpdatedAt: String?
    public let planType: String?

    private enum CodingKeys: String, CodingKey {
        case fiveHourUsedPercent = "codex_5h_used_percent"
        case fiveHourResetAfterSeconds = "codex_5h_reset_after_seconds"
        case fiveHourResetAt = "codex_5h_reset_at"
        case sevenDayUsedPercent = "codex_7d_used_percent"
        case sevenDayResetAfterSeconds = "codex_7d_reset_after_seconds"
        case sevenDayResetAt = "codex_7d_reset_at"
        case usageUpdatedAt = "codex_usage_updated_at"
        case planType = "plan_type"
    }
}

public struct OpenAIRateLimitWindow: Codable, Hashable, Sendable {
    public let usedPercent: Double
    public let limitWindowSeconds: Int
    public let resetAfterSeconds: Int
    public let resetAt: Int

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }
}

public struct OpenAIRateLimit: Codable, Hashable, Sendable {
    public let allowed: Bool
    public let limitReached: Bool
    public let primaryWindow: OpenAIRateLimitWindow?
    public let secondaryWindow: OpenAIRateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    public var windows: [OpenAIRateLimitWindow] {
        [primaryWindow, secondaryWindow].compactMap { $0 }
    }
}

public struct OpenAIAdditionalRateLimit: Codable, Hashable, Sendable {
    public let limitName: String
    public let meteredFeature: String
    public let rateLimit: OpenAIRateLimit?

    private enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }
}

public struct OpenAIResetCredits: Codable, Hashable, Sendable {
    public let availableCount: Int

    private enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }
}

public struct OpenAIQuotaUsage: Codable, Hashable, Sendable {
    public let email: String?
    public let planType: String?
    public let rateLimit: OpenAIRateLimit?
    public let additionalRateLimits: [OpenAIAdditionalRateLimit]
    public let resetCredits: OpenAIResetCredits?
    public let fetchedAt: Int

    private enum CodingKeys: String, CodingKey {
        case email
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
        case resetCredits = "rate_limit_reset_credits"
        case fetchedAt = "fetched_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        rateLimit = try container.decodeIfPresent(OpenAIRateLimit.self, forKey: .rateLimit)
        additionalRateLimits = try container.decodeIfPresent(
            [OpenAIAdditionalRateLimit].self,
            forKey: .additionalRateLimits
        ) ?? []
        resetCredits = try container.decodeIfPresent(OpenAIResetCredits.self, forKey: .resetCredits)
        fetchedAt = try container.decode(Int.self, forKey: .fetchedAt)
    }
}

public struct QuotaWindow: Codable, Hashable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date?

    public var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

public struct ProviderUsageProgress: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date?
    public let windowStats: ProviderWindowStats?

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
        case windowStats = "window_stats"
    }
}

public struct ProviderWindowStats: Codable, Equatable, Sendable {
    public let requests: Int64
    public let tokens: Int64
    public let cost: Double

    public init(requests: Int64, tokens: Int64, cost: Double) {
        self.requests = requests
        self.tokens = tokens
        self.cost = cost
    }
}

public struct AntigravityModelQuota: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetTime: String

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetTime = "reset_time"
    }
}

public struct GrokQuotaWindow: Codable, Equatable, Sendable {
    public let limit: Int64?
    public let remaining: Int64?
    public let resetAt: String?

    private enum CodingKeys: String, CodingKey {
        case limit
        case remaining
        case resetAt = "reset_at"
    }
}

public struct GrokBillingSummary: Codable, Equatable, Sendable {
    public let periodType: String?
    public let usagePercent: Double?
    public let periodEnd: String?
    public let usedPercent: Double?
    public let billingPeriodEnd: String?
    public let plan: String?

    private enum CodingKeys: String, CodingKey {
        case periodType = "period_type"
        case usagePercent = "usage_percent"
        case periodEnd = "period_end"
        case usedPercent = "used_percent"
        case billingPeriodEnd = "billing_period_end"
        case plan
    }
}

public struct ProviderUsageInfo: Codable, Equatable, Sendable {
    public let updatedAt: Date?
    public let fiveHour: ProviderUsageProgress?
    public let sevenDay: ProviderUsageProgress?
    public let sevenDaySonnet: ProviderUsageProgress?
    public let sevenDayFable: ProviderUsageProgress?
    public let geminiSharedDaily: ProviderUsageProgress?
    public let geminiProDaily: ProviderUsageProgress?
    public let geminiFlashDaily: ProviderUsageProgress?
    public let geminiSharedMinute: ProviderUsageProgress?
    public let geminiProMinute: ProviderUsageProgress?
    public let geminiFlashMinute: ProviderUsageProgress?
    public let antigravityQuota: [String: AntigravityModelQuota]?
    public let grokRequestQuota: GrokQuotaWindow?
    public let grokTokenQuota: GrokQuotaWindow?
    public let grokFreeTokenLimit: Int64?
    public let grokLocalUsage24h: ProviderWindowStats?
    public let grokBilling: GrokBillingSummary?
    public let subscriptionTier: String?
    public let errorCode: String?
    public let error: String?

    private enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayFable = "seven_day_fable"
        case geminiSharedDaily = "gemini_shared_daily"
        case geminiProDaily = "gemini_pro_daily"
        case geminiFlashDaily = "gemini_flash_daily"
        case geminiSharedMinute = "gemini_shared_minute"
        case geminiProMinute = "gemini_pro_minute"
        case geminiFlashMinute = "gemini_flash_minute"
        case antigravityQuota = "antigravity_quota"
        case grokRequestQuota = "grok_request_quota"
        case grokTokenQuota = "grok_token_quota"
        case grokFreeTokenLimit = "grok_free_token_limit"
        case grokLocalUsage24h = "grok_local_usage_24h"
        case grokBilling = "grok_billing"
        case subscriptionTier = "subscription_tier"
        case errorCode = "error_code"
        case error
    }
}

public struct ProviderQuotaWindow: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let quota: QuotaWindow
    public let metrics: UsageWindowMetrics?

    public init(id: String, label: String, quota: QuotaWindow, metrics: UsageWindowMetrics?) {
        self.id = id
        self.label = label
        self.quota = quota
        self.metrics = metrics
    }
}

public struct ProviderQuotaSnapshot: Codable, Equatable, Sendable {
    public let accountID: Int
    public let providerID: String
    public let providerName: String
    public let planType: String?
    public let resetCredits: Int?
    public let windows: [ProviderQuotaWindow]
    public let fetchedAt: Date?
    public let error: String?

    public init(
        accountID: Int,
        providerID: String,
        providerName: String,
        planType: String?,
        resetCredits: Int? = nil,
        windows: [ProviderQuotaWindow],
        fetchedAt: Date?,
        error: String?
    ) {
        self.accountID = accountID
        self.providerID = providerID
        self.providerName = providerName
        self.planType = planType
        self.resetCredits = resetCredits
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.error = error
    }
}

public struct AggregateQuotaWindow: Codable, Equatable, Sendable {
    public let totalAccountCount: Int
    public let reportingAccountCount: Int
    public let averageRemainingPercent: Double?
    public let minimumRemainingPercent: Double?
    public let equivalentAvailableAccounts: Double

    public init(windows: [QuotaWindow], totalAccountCount: Int) {
        let remaining = windows.map(\.remainingPercent)
        self.totalAccountCount = totalAccountCount
        reportingAccountCount = remaining.count
        averageRemainingPercent = remaining.isEmpty
            ? nil
            : remaining.reduce(0, +) / Double(remaining.count)
        minimumRemainingPercent = remaining.min()
        equivalentAvailableAccounts = remaining.reduce(0, +) / 100
    }
}

public struct AggregateQuotaSummary: Codable, Equatable, Sendable {
    public let fiveHour: AggregateQuotaWindow
    public let sevenDay: AggregateQuotaWindow

    public init(snapshots: [AccountQuotaSnapshot], totalAccountCount: Int) {
        fiveHour = AggregateQuotaWindow(
            windows: snapshots.compactMap(\.fiveHour),
            totalAccountCount: totalAccountCount
        )
        sevenDay = AggregateQuotaWindow(
            windows: snapshots.compactMap(\.sevenDay),
            totalAccountCount: totalAccountCount
        )
    }
}

public struct DashboardUsageStats: Codable, Equatable, Sendable {
    public let totalRequests: Int64
    public let todayRequests: Int64
    public let totalInputTokens: Int64
    public let todayInputTokens: Int64
    public let totalOutputTokens: Int64
    public let todayOutputTokens: Int64
    public let totalCacheCreationTokens: Int64
    public let todayCacheCreationTokens: Int64
    public let totalCacheReadTokens: Int64
    public let todayCacheReadTokens: Int64
    public let totalTokens: Int64
    public let todayTokens: Int64
    public let totalCost: Double
    public let todayCost: Double
    public let totalActualCost: Double
    public let todayActualCost: Double
    public let averageDurationMilliseconds: Double
    public let requestsPerMinute: Int64
    public let tokensPerMinute: Int64
    public let totalAccounts: Int64
    public let normalAccounts: Int64
    public let errorAccounts: Int64
    public let rateLimitAccounts: Int64
    public let overloadAccounts: Int64
    public let statsUpdatedAt: String?
    public let statsStale: Bool?

    private enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case todayRequests = "today_requests"
        case totalInputTokens = "total_input_tokens"
        case todayInputTokens = "today_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case todayOutputTokens = "today_output_tokens"
        case totalCacheCreationTokens = "total_cache_creation_tokens"
        case todayCacheCreationTokens = "today_cache_creation_tokens"
        case totalCacheReadTokens = "total_cache_read_tokens"
        case todayCacheReadTokens = "today_cache_read_tokens"
        case totalTokens = "total_tokens"
        case todayTokens = "today_tokens"
        case totalCost = "total_cost"
        case todayCost = "today_cost"
        case totalActualCost = "total_actual_cost"
        case todayActualCost = "today_actual_cost"
        case averageDurationMilliseconds = "average_duration_ms"
        case requestsPerMinute = "rpm"
        case tokensPerMinute = "tpm"
        case totalAccounts = "total_accounts"
        case normalAccounts = "normal_accounts"
        case errorAccounts = "error_accounts"
        case rateLimitAccounts = "ratelimit_accounts"
        case overloadAccounts = "overload_accounts"
        case statsUpdatedAt = "stats_updated_at"
        case statsStale = "stats_stale"
    }

    public init(
        totalRequests: Int64,
        todayRequests: Int64,
        totalInputTokens: Int64,
        todayInputTokens: Int64,
        totalOutputTokens: Int64,
        todayOutputTokens: Int64,
        totalCacheCreationTokens: Int64,
        todayCacheCreationTokens: Int64,
        totalCacheReadTokens: Int64,
        todayCacheReadTokens: Int64,
        totalTokens: Int64,
        todayTokens: Int64,
        totalCost: Double,
        todayCost: Double,
        totalActualCost: Double,
        todayActualCost: Double,
        averageDurationMilliseconds: Double,
        requestsPerMinute: Int64,
        tokensPerMinute: Int64,
        totalAccounts: Int64,
        normalAccounts: Int64,
        errorAccounts: Int64,
        rateLimitAccounts: Int64,
        overloadAccounts: Int64,
        statsUpdatedAt: String?,
        statsStale: Bool?
    ) {
        self.totalRequests = totalRequests
        self.todayRequests = todayRequests
        self.totalInputTokens = totalInputTokens
        self.todayInputTokens = todayInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.todayOutputTokens = todayOutputTokens
        self.totalCacheCreationTokens = totalCacheCreationTokens
        self.todayCacheCreationTokens = todayCacheCreationTokens
        self.totalCacheReadTokens = totalCacheReadTokens
        self.todayCacheReadTokens = todayCacheReadTokens
        self.totalTokens = totalTokens
        self.todayTokens = todayTokens
        self.totalCost = totalCost
        self.todayCost = todayCost
        self.totalActualCost = totalActualCost
        self.todayActualCost = todayActualCost
        self.averageDurationMilliseconds = averageDurationMilliseconds
        self.requestsPerMinute = requestsPerMinute
        self.tokensPerMinute = tokensPerMinute
        self.totalAccounts = totalAccounts
        self.normalAccounts = normalAccounts
        self.errorAccounts = errorAccounts
        self.rateLimitAccounts = rateLimitAccounts
        self.overloadAccounts = overloadAccounts
        self.statsUpdatedAt = statsUpdatedAt
        self.statsStale = statsStale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalRequests = try container.decode(Int64.self, forKey: .totalRequests)
        todayRequests = try container.decode(Int64.self, forKey: .todayRequests)
        totalInputTokens = try container.decode(Int64.self, forKey: .totalInputTokens)
        todayInputTokens = try container.decode(Int64.self, forKey: .todayInputTokens)
        totalOutputTokens = try container.decode(Int64.self, forKey: .totalOutputTokens)
        todayOutputTokens = try container.decode(Int64.self, forKey: .todayOutputTokens)
        totalCacheCreationTokens = try container.decode(Int64.self, forKey: .totalCacheCreationTokens)
        todayCacheCreationTokens = try container.decode(Int64.self, forKey: .todayCacheCreationTokens)
        totalCacheReadTokens = try container.decode(Int64.self, forKey: .totalCacheReadTokens)
        todayCacheReadTokens = try container.decode(Int64.self, forKey: .todayCacheReadTokens)
        totalTokens = try container.decode(Int64.self, forKey: .totalTokens)
        todayTokens = try container.decode(Int64.self, forKey: .todayTokens)
        totalCost = try container.decode(Double.self, forKey: .totalCost)
        todayCost = try container.decode(Double.self, forKey: .todayCost)
        totalActualCost = try container.decode(Double.self, forKey: .totalActualCost)
        todayActualCost = try container.decode(Double.self, forKey: .todayActualCost)
        averageDurationMilliseconds = try container.decode(Double.self, forKey: .averageDurationMilliseconds)
        requestsPerMinute = try container.decode(Int64.self, forKey: .requestsPerMinute)
        tokensPerMinute = try container.decode(Int64.self, forKey: .tokensPerMinute)
        totalAccounts = try container.decodeIfPresent(Int64.self, forKey: .totalAccounts) ?? 0
        normalAccounts = try container.decodeIfPresent(Int64.self, forKey: .normalAccounts) ?? 0
        errorAccounts = try container.decodeIfPresent(Int64.self, forKey: .errorAccounts) ?? 0
        rateLimitAccounts = try container.decodeIfPresent(Int64.self, forKey: .rateLimitAccounts) ?? 0
        overloadAccounts = try container.decodeIfPresent(Int64.self, forKey: .overloadAccounts) ?? 0
        statsUpdatedAt = try container.decodeIfPresent(String.self, forKey: .statsUpdatedAt)
        statsStale = try container.decodeIfPresent(Bool.self, forKey: .statsStale)
    }
}

public struct OpenAIModelTokenStat: Codable, Equatable, Identifiable, Sendable {
    public var id: String { model }

    public let model: String
    public let requestCount: Int64
    public let totalOutputTokens: Int64
    public let actualCost: Double?
    public let averageTokensPerSecond: Double?
    public let averageFirstTokenMilliseconds: Double?
    public let averageDurationMilliseconds: Int64
    public let requestsWithFirstToken: Int64

    private enum CodingKeys: String, CodingKey {
        case model
        case requestCount = "request_count"
        case totalOutputTokens = "total_output_tokens"
        case actualCost = "actual_cost"
        case averageTokensPerSecond = "avg_tokens_per_sec"
        case averageFirstTokenMilliseconds = "avg_first_token_ms"
        case averageDurationMilliseconds = "avg_duration_ms"
        case requestsWithFirstToken = "requests_with_first_token"
    }
}

public struct OpenAITokenStatsResponse: Codable, Equatable, Sendable {
    public let timeRange: String
    public let startTime: Date
    public let endTime: Date
    public let platform: String?
    public let items: [OpenAIModelTokenStat]
    public let total: Int64

    private enum CodingKeys: String, CodingKey {
        case timeRange = "time_range"
        case startTime = "start_time"
        case endTime = "end_time"
        case platform
        case items
        case total
    }
}

public struct ModelUsageStat: Codable, Equatable, Identifiable, Sendable {
    public var id: String { model }

    public let model: String
    public let requests: Int64
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheCreationTokens: Int64
    public let cacheReadTokens: Int64
    public let totalTokens: Int64
    public let cost: Double
    public let actualCost: Double
    public let accountCost: Double

    private enum CodingKeys: String, CodingKey {
        case model
        case requests
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case totalTokens = "total_tokens"
        case cost
        case actualCost = "actual_cost"
        case accountCost = "account_cost"
    }

    public init(
        model: String,
        requests: Int64,
        inputTokens: Int64,
        outputTokens: Int64,
        cacheCreationTokens: Int64,
        cacheReadTokens: Int64,
        totalTokens: Int64,
        cost: Double,
        actualCost: Double,
        accountCost: Double
    ) {
        self.model = model
        self.requests = requests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.totalTokens = totalTokens
        self.cost = cost
        self.actualCost = actualCost
        self.accountCost = accountCost
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        requests = try container.decode(Int64.self, forKey: .requests)
        inputTokens = try container.decode(Int64.self, forKey: .inputTokens)
        outputTokens = try container.decode(Int64.self, forKey: .outputTokens)
        cacheCreationTokens = try container.decode(Int64.self, forKey: .cacheCreationTokens)
        cacheReadTokens = try container.decode(Int64.self, forKey: .cacheReadTokens)
        totalTokens = try container.decode(Int64.self, forKey: .totalTokens)
        cost = try container.decode(Double.self, forKey: .cost)
        actualCost = try container.decode(Double.self, forKey: .actualCost)
        accountCost = try container.decodeIfPresent(Double.self, forKey: .accountCost) ?? 0
    }
}

public struct UserPlatformQuotaList: Codable, Equatable, Sendable {
    public let platformQuotas: [UserPlatformQuota]

    private enum CodingKeys: String, CodingKey {
        case platformQuotas = "platform_quotas"
    }
}

public struct UserPlatformQuota: Codable, Equatable, Identifiable, Sendable {
    public var id: String { platform }
    public let platform: String
    public let dailyUsageUSD: Double
    public let dailyLimitUSD: Double?
    public let dailyWindowResetsAt: String?
    public let weeklyUsageUSD: Double
    public let weeklyLimitUSD: Double?
    public let weeklyWindowResetsAt: String?
    public let monthlyUsageUSD: Double
    public let monthlyLimitUSD: Double?
    public let monthlyWindowResetsAt: String?

    private enum CodingKeys: String, CodingKey {
        case platform
        case dailyUsageUSD = "daily_usage_usd"
        case dailyLimitUSD = "daily_limit_usd"
        case dailyWindowResetsAt = "daily_window_resets_at"
        case weeklyUsageUSD = "weekly_usage_usd"
        case weeklyLimitUSD = "weekly_limit_usd"
        case weeklyWindowResetsAt = "weekly_window_resets_at"
        case monthlyUsageUSD = "monthly_usage_usd"
        case monthlyLimitUSD = "monthly_limit_usd"
        case monthlyWindowResetsAt = "monthly_window_resets_at"
    }
}

public struct UserAPIKey: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let status: String
    public let quota: Double
    public let quotaUsed: Double
    public let rateLimit5h: Double
    public let rateLimit1d: Double
    public let rateLimit7d: Double
    public let usage5h: Double
    public let usage1d: Double
    public let usage7d: Double
    public let reset5hAt: String?
    public let reset1dAt: String?
    public let reset7dAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, status, quota
        case quotaUsed = "quota_used"
        case rateLimit5h = "rate_limit_5h"
        case rateLimit1d = "rate_limit_1d"
        case rateLimit7d = "rate_limit_7d"
        case usage5h = "usage_5h"
        case usage1d = "usage_1d"
        case usage7d = "usage_7d"
        case reset5hAt = "reset_5h_at"
        case reset1dAt = "reset_1d_at"
        case reset7dAt = "reset_7d_at"
    }
}

public struct UserSubscriptionSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let groupID: Int64
    public let groupName: String
    public let status: String
    public let dailyUsedUSD: Double
    public let dailyLimitUSD: Double
    public let weeklyUsedUSD: Double
    public let weeklyLimitUSD: Double
    public let monthlyUsedUSD: Double
    public let monthlyLimitUSD: Double
    public let expiresAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, status
        case groupID = "group_id"
        case groupName = "group_name"
        case dailyUsedUSD = "daily_used_usd"
        case dailyLimitUSD = "daily_limit_usd"
        case weeklyUsedUSD = "weekly_used_usd"
        case weeklyLimitUSD = "weekly_limit_usd"
        case monthlyUsedUSD = "monthly_used_usd"
        case monthlyLimitUSD = "monthly_limit_usd"
        case expiresAt = "expires_at"
    }

    public init(
        id: Int64,
        groupID: Int64,
        groupName: String,
        status: String,
        dailyUsedUSD: Double,
        dailyLimitUSD: Double,
        weeklyUsedUSD: Double,
        weeklyLimitUSD: Double,
        monthlyUsedUSD: Double,
        monthlyLimitUSD: Double,
        expiresAt: String?
    ) {
        self.id = id
        self.groupID = groupID
        self.groupName = groupName
        self.status = status
        self.dailyUsedUSD = dailyUsedUSD
        self.dailyLimitUSD = dailyLimitUSD
        self.weeklyUsedUSD = weeklyUsedUSD
        self.weeklyLimitUSD = weeklyLimitUSD
        self.monthlyUsedUSD = monthlyUsedUSD
        self.monthlyLimitUSD = monthlyLimitUSD
        self.expiresAt = expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        groupID = try container.decode(Int64.self, forKey: .groupID)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? "订阅"
        status = try container.decode(String.self, forKey: .status)
        dailyUsedUSD = try container.decodeIfPresent(Double.self, forKey: .dailyUsedUSD) ?? 0
        dailyLimitUSD = try container.decodeIfPresent(Double.self, forKey: .dailyLimitUSD) ?? 0
        weeklyUsedUSD = try container.decodeIfPresent(Double.self, forKey: .weeklyUsedUSD) ?? 0
        weeklyLimitUSD = try container.decodeIfPresent(Double.self, forKey: .weeklyLimitUSD) ?? 0
        monthlyUsedUSD = try container.decodeIfPresent(Double.self, forKey: .monthlyUsedUSD) ?? 0
        monthlyLimitUSD = try container.decodeIfPresent(Double.self, forKey: .monthlyLimitUSD) ?? 0
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
    }
}

public struct UserSubscriptionSummaryResponse: Codable, Equatable, Sendable {
    public let activeCount: Int
    public let totalUsedUSD: Double
    public let subscriptions: [UserSubscriptionSummary]

    private enum CodingKeys: String, CodingKey {
        case activeCount = "active_count"
        case totalUsedUSD = "total_used_usd"
        case subscriptions
    }
}

public struct ModelUsageStatsResponse: Codable, Equatable, Sendable {
    public let models: [ModelUsageStat]
    public let startDate: String
    public let endDate: String

    private enum CodingKeys: String, CodingKey {
        case models
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

public struct UsageTrendPoint: Codable, Equatable, Sendable {
    public let date: String
    public let requests: Int64
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheCreationTokens: Int64
    public let cacheReadTokens: Int64
    public let totalTokens: Int64
    public let cost: Double
    public let actualCost: Double

    private enum CodingKeys: String, CodingKey {
        case date
        case requests
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case totalTokens = "total_tokens"
        case cost
        case actualCost = "actual_cost"
    }
}

public struct UsageTrendResponse: Codable, Equatable, Sendable {
    public let trend: [UsageTrendPoint]
    public let startDate: String
    public let endDate: String
    public let granularity: String

    private enum CodingKeys: String, CodingKey {
        case trend
        case startDate = "start_date"
        case endDate = "end_date"
        case granularity
    }
}

public struct AccountUsageLog: Codable, Equatable, Sendable {
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheCreationTokens: Int64
    public let cacheReadTokens: Int64
    public let actualCost: Double
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case actualCost = "actual_cost"
        case createdAt = "created_at"
    }
}

public struct AccountUsageStats: Codable, Equatable, Sendable {
    public let totalRequests: Int64
    public let totalInputTokens: Int64
    public let totalOutputTokens: Int64
    public let totalCacheCreationTokens: Int64
    public let totalCacheReadTokens: Int64
    public let totalTokens: Int64
    public let totalActualCost: Double

    private enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case totalCacheCreationTokens = "total_cache_creation_tokens"
        case totalCacheReadTokens = "total_cache_read_tokens"
        case totalTokens = "total_tokens"
        case totalActualCost = "total_actual_cost"
    }
}

public struct UsageWindowMetrics: Codable, Equatable, Sendable {
    public let requestCount: Int64
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheCreationTokens: Int64
    public let cacheReadTokens: Int64
    public let totalTokens: Int64
    public let actualCost: Double

    public init(providerStats: ProviderWindowStats) {
        requestCount = providerStats.requests
        inputTokens = 0
        outputTokens = 0
        cacheCreationTokens = 0
        cacheReadTokens = 0
        totalTokens = providerStats.tokens
        actualCost = providerStats.cost
    }

    public init(logs: [AccountUsageLog], since: Date) {
        let included = logs.filter { $0.createdAt >= since }
        requestCount = Int64(included.count)
        inputTokens = included.reduce(0) { $0 + $1.inputTokens }
        outputTokens = included.reduce(0) { $0 + $1.outputTokens }
        cacheCreationTokens = included.reduce(0) { $0 + $1.cacheCreationTokens }
        cacheReadTokens = included.reduce(0) { $0 + $1.cacheReadTokens }
        totalTokens = inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
        actualCost = included.reduce(0) { $0 + $1.actualCost }
    }

    public init(stats: AccountUsageStats) {
        requestCount = stats.totalRequests
        inputTokens = stats.totalInputTokens
        outputTokens = stats.totalOutputTokens
        cacheCreationTokens = stats.totalCacheCreationTokens
        cacheReadTokens = stats.totalCacheReadTokens
        totalTokens = stats.totalTokens
        actualCost = stats.totalActualCost
    }

    public init(summing metrics: [UsageWindowMetrics]) {
        requestCount = metrics.reduce(0) { $0 + $1.requestCount }
        inputTokens = metrics.reduce(0) { $0 + $1.inputTokens }
        outputTokens = metrics.reduce(0) { $0 + $1.outputTokens }
        cacheCreationTokens = metrics.reduce(0) { $0 + $1.cacheCreationTokens }
        cacheReadTokens = metrics.reduce(0) { $0 + $1.cacheReadTokens }
        totalTokens = metrics.reduce(0) { $0 + $1.totalTokens }
        actualCost = metrics.reduce(0) { $0 + $1.actualCost }
    }
}

public extension ProviderUsageInfo {
    func snapshot(for account: CodexAccount) -> ProviderQuotaSnapshot {
        let windows: [ProviderQuotaWindow]
        switch account.providerID {
        case "codex":
            windows = progressWindows([
                ("5h", "5h", fiveHour),
                ("7d", "7d", sevenDay),
            ])
        case "anthropic", "claude":
            windows = progressWindows([
                ("5h", "5h", fiveHour),
                ("7d", "7d", sevenDay),
                ("7d-sonnet", "7d S", sevenDaySonnet),
                ("7d-fable", "7d F", sevenDayFable),
            ])
        case "gemini", "google":
            windows = progressWindows([
                ("shared-daily", "1d", geminiSharedDaily),
                ("pro-daily", "Pro 1d", geminiProDaily),
                ("flash-daily", "Flash 1d", geminiFlashDaily),
                ("shared-minute", "1m", geminiSharedMinute),
                ("pro-minute", "Pro 1m", geminiProMinute),
                ("flash-minute", "Flash 1m", geminiFlashMinute),
            ])
        case "antigravity":
            windows = (antigravityQuota ?? [:])
                .map { name, value in
                    ProviderQuotaWindow(
                        id: name,
                        label: Self.compactModelName(name),
                        quota: QuotaWindow(
                            usedPercent: value.utilization,
                            resetsAt: DateParser.parse(value.resetTime)
                        ),
                        metrics: nil
                    )
                }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        case "grok":
            windows = grokWindows()
        default:
            windows = []
        }

        return ProviderQuotaSnapshot(
            accountID: account.id,
            providerID: account.providerID,
            providerName: account.providerDisplayName,
            planType: subscriptionTier,
            resetCredits: nil,
            windows: windows,
            fetchedAt: updatedAt,
            error: error
        )
    }

    private func progressWindows(
        _ values: [(id: String, label: String, progress: ProviderUsageProgress?)]
    ) -> [ProviderQuotaWindow] {
        values.compactMap { value in
            guard let progress = value.progress else { return nil }
            return ProviderQuotaWindow(
                id: value.id,
                label: value.label,
                quota: QuotaWindow(
                    usedPercent: max(0, progress.utilization),
                    resetsAt: progress.resetsAt
                ),
                metrics: progress.windowStats.map(UsageWindowMetrics.init(providerStats:))
            )
        }
    }

    private func grokWindows() -> [ProviderQuotaWindow] {
        if let billing = grokBilling,
           let used = billing.usagePercent ?? billing.usedPercent {
            let isWeekly = billing.periodType?.lowercased() == "weekly"
            let reset = billing.periodEnd ?? billing.billingPeriodEnd
            return [
                ProviderQuotaWindow(
                    id: isWeekly ? "7d" : "billing",
                    label: isWeekly ? "7d" : "账期",
                    quota: QuotaWindow(
                        usedPercent: max(0, used),
                        resetsAt: reset.flatMap(DateParser.parse)
                    ),
                    metrics: grokLocalUsage24h.map(UsageWindowMetrics.init(providerStats:))
                ),
            ]
        }

        let grokPlan = (grokBilling?.plan ?? subscriptionTier ?? "").lowercased()
        let planIsFree = grokPlan.contains("free") || grokPlan.contains("basic")
        let planIsPaid = !grokPlan.isEmpty && !planIsFree && !grokPlan.contains("unknown")
        let isFree = !planIsPaid && (planIsFree || grokBilling != nil)
        if isFree,
           let limit = grokFreeTokenLimit,
           limit > 0,
           let stats = grokLocalUsage24h {
            return [
                ProviderQuotaWindow(
                    id: "free-24h",
                    label: "24h",
                    quota: QuotaWindow(
                        usedPercent: min(100, Double(stats.tokens) / Double(limit) * 100),
                        resetsAt: nil
                    ),
                    metrics: UsageWindowMetrics(providerStats: stats)
                ),
            ]
        }

        return [
            Self.grokCapacityWindow(id: "requests", label: "请求", value: grokRequestQuota),
            Self.grokCapacityWindow(id: "tokens", label: "Token", value: grokTokenQuota),
        ].compactMap { $0 }
    }

    private static func grokCapacityWindow(
        id: String,
        label: String,
        value: GrokQuotaWindow?
    ) -> ProviderQuotaWindow? {
        guard let value, let limit = value.limit, let remaining = value.remaining, limit > 0 else {
            return nil
        }
        let used = 100 - min(100, max(0, Double(remaining) / Double(limit) * 100))
        return ProviderQuotaWindow(
            id: id,
            label: label,
            quota: QuotaWindow(
                usedPercent: used,
                resetsAt: value.resetAt.flatMap(DateParser.parse)
            ),
            metrics: nil
        )
    }

    private static func compactModelName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "gemini-", with: "")
            .replacingOccurrences(of: "-preview", with: "")
    }
}

public struct AccountUsageWindows: Codable, Equatable, Sendable {
    public let fiveHour: UsageWindowMetrics?
    public let sevenDay: UsageWindowMetrics?

    public init(fiveHour: UsageWindowMetrics?, sevenDay: UsageWindowMetrics?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public init(summing windows: [AccountUsageWindows]) {
        let fiveHourMetrics = windows.compactMap(\.fiveHour)
        let sevenDayMetrics = windows.compactMap(\.sevenDay)
        fiveHour = fiveHourMetrics.isEmpty ? nil : UsageWindowMetrics(summing: fiveHourMetrics)
        sevenDay = sevenDayMetrics.isEmpty ? nil : UsageWindowMetrics(summing: sevenDayMetrics)
    }
}

public struct AccountQuotaSnapshot: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        case cached
        case live
    }

    public let accountID: Int
    public let accountName: String
    public let planType: String?
    public let fiveHour: QuotaWindow?
    public let sevenDay: QuotaWindow?
    public let resetCredits: Int?
    public let fetchedAt: Date?
    public let source: Source

    public var highestUsedPercent: Double? {
        [fiveHour?.usedPercent, sevenDay?.usedPercent]
            .compactMap { $0 }
            .max()
    }

    public func isStale(now: Date = Date(), threshold: TimeInterval = 30 * 60) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) > threshold
    }
}

public enum AccountHealth: Int, Comparable, Sendable {
    case healthy = 0
    case warning = 1
    case critical = 2
    case stale = 3
    case error = 4
    case unknown = 5

    public static func < (lhs: AccountHealth, rhs: AccountHealth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public extension CodexAccount {
    func cachedQuotaSnapshot(now: Date = Date()) -> AccountQuotaSnapshot? {
        guard supportsCodexQuota else { return nil }
        guard let extra else { return nil }
        let fetchedAt = extra.usageUpdatedAt.flatMap(DateParser.parse)
        let fiveHour = Self.makeCachedWindow(
            usedPercent: extra.fiveHourUsedPercent,
            resetAt: extra.fiveHourResetAt,
            resetAfterSeconds: extra.fiveHourResetAfterSeconds,
            fetchedAt: fetchedAt,
            now: now
        )
        let sevenDay = Self.makeCachedWindow(
            usedPercent: extra.sevenDayUsedPercent,
            resetAt: extra.sevenDayResetAt,
            resetAfterSeconds: extra.sevenDayResetAfterSeconds,
            fetchedAt: fetchedAt,
            now: now
        )
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return AccountQuotaSnapshot(
            accountID: id,
            accountName: name,
            planType: extra.planType,
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            resetCredits: nil,
            fetchedAt: fetchedAt,
            source: .cached
        )
    }

    func health(snapshot: AccountQuotaSnapshot?, now: Date = Date()) -> AccountHealth {
        if status == "error" || !schedulable || !(errorMessage?.isEmpty ?? true) {
            return .error
        }
        if !supportsCodexQuota { return .healthy }
        guard let snapshot else { return .unknown }
        if snapshot.isStale(now: now) { return .stale }
        guard let used = snapshot.highestUsedPercent else { return .unknown }
        if used >= 95 { return .critical }
        if used >= 80 { return .warning }
        return .healthy
    }

    func health(snapshot: ProviderQuotaSnapshot?, now: Date = Date()) -> AccountHealth {
        if status == "error" || !schedulable || !(errorMessage?.isEmpty ?? true) {
            return .error
        }
        guard supportsProviderUsage else { return .healthy }
        guard let snapshot else { return .unknown }
        if let fetchedAt = snapshot.fetchedAt,
           now.timeIntervalSince(fetchedAt) > 30 * 60 {
            return .stale
        }
        guard let used = snapshot.windows.map(\.quota.usedPercent).max() else { return .unknown }
        if used >= 95 { return .critical }
        if used >= 80 { return .warning }
        return .healthy
    }

    private static func makeCachedWindow(
        usedPercent: Double?,
        resetAt: String?,
        resetAfterSeconds: Int?,
        fetchedAt: Date?,
        now: Date
    ) -> QuotaWindow? {
        guard let usedPercent else { return nil }
        let absoluteReset = resetAt.flatMap(DateParser.parse)
        let calculatedReset = resetAfterSeconds.flatMap { seconds in
            (fetchedAt ?? now).addingTimeInterval(TimeInterval(seconds))
        }
        return QuotaWindow(
            usedPercent: max(0, usedPercent),
            resetsAt: absoluteReset ?? calculatedReset
        )
    }
}

public extension OpenAIQuotaUsage {
    func snapshot(for account: CodexAccount) -> AccountQuotaSnapshot {
        let mainWindows = rateLimit?.windows ?? []
        let additionalWindows = additionalRateLimits.flatMap { limit -> [OpenAIRateLimitWindow] in
            guard limit.meteredFeature == "codex_bengalfox" || account.parentAccountID == nil else {
                return []
            }
            return limit.rateLimit?.windows ?? []
        }
        let preferredWindows: [OpenAIRateLimitWindow]
        if account.parentAccountID != nil && !additionalWindows.isEmpty {
            preferredWindows = additionalWindows
        } else if !mainWindows.isEmpty {
            preferredWindows = mainWindows
        } else {
            preferredWindows = additionalWindows
        }

        return AccountQuotaSnapshot(
            accountID: account.id,
            accountName: account.name,
            planType: planType,
            fiveHour: Self.closestWindow(to: 5 * 60 * 60, in: preferredWindows),
            sevenDay: Self.closestWindow(to: 7 * 24 * 60 * 60, in: preferredWindows),
            resetCredits: resetCredits?.availableCount,
            fetchedAt: Date(timeIntervalSince1970: TimeInterval(fetchedAt)),
            source: .live
        )
    }

    private static func closestWindow(
        to targetSeconds: Int,
        in windows: [OpenAIRateLimitWindow]
    ) -> QuotaWindow? {
        guard let match = windows.min(by: {
            abs($0.limitWindowSeconds - targetSeconds) < abs($1.limitWindowSeconds - targetSeconds)
        }) else {
            return nil
        }
        let difference = abs(match.limitWindowSeconds - targetSeconds)
        guard difference <= targetSeconds / 2 else { return nil }
        let resetDate: Date?
        if match.resetAt > 0 {
            resetDate = Date(timeIntervalSince1970: TimeInterval(match.resetAt))
        } else if match.resetAfterSeconds > 0 {
            resetDate = Date().addingTimeInterval(TimeInterval(match.resetAfterSeconds))
        } else {
            resetDate = nil
        }
        return QuotaWindow(usedPercent: max(0, match.usedPercent), resetsAt: resetDate)
    }
}

public enum DateParser {
    public static func parse(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

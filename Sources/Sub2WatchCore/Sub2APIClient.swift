import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum Sub2APIError: LocalizedError, Sendable {
    case invalidResponse
    case invalidPayload
    case unauthorized
    case forbidden
    case complianceRequired
    case rateLimited
    case upstreamUnavailable
    case server(status: Int, message: String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器返回了无法识别的响应"
        case .invalidPayload:
            return "服务器数据格式与当前应用不兼容"
        case .unauthorized:
            return "登录已失效或凭据无效"
        case .forbidden:
            return "当前账号无权访问此功能"
        case .complianceRequired:
            return "请先在 Sub2API 管理后台完成合规确认"
        case .rateLimited:
            return "上游请求过于频繁，请稍后再试"
        case .upstreamUnavailable:
            return "Codex 上游暂时不可用"
        case let .server(_, message):
            return message
        case let .transport(message):
            return message
        }
    }
}

public struct AccountListResult: Sendable {
    public let accounts: [CodexAccount]?
    public let etag: String?

    public init(accounts: [CodexAccount]?, etag: String?) {
        self.accounts = accounts
        self.etag = etag
    }
}

public struct Sub2APIClient: Sendable {
    public init() {}

    public func login(
        apiBaseURL: URL,
        email: String,
        password: String
    ) async throws -> LoginResult {
        let url = endpoint("auth/login", apiBaseURL: apiBaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            LoginRequest(email: email, password: password, turnstileToken: "")
        )
        return try await decode(LoginResult.self, from: request)
    }

    public func completeTwoFactorLogin(
        apiBaseURL: URL,
        temporaryToken: String,
        code: String
    ) async throws -> LoginResult {
        struct Payload: Encodable {
            let tempToken: String
            let totpCode: String

            enum CodingKeys: String, CodingKey {
                case tempToken = "temp_token"
                case totpCode = "totp_code"
            }
        }
        let url = endpoint("auth/login/2fa", apiBaseURL: apiBaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Payload(tempToken: temporaryToken, totpCode: code)
        )
        return try await decode(LoginResult.self, from: request)
    }

    public func refreshSession(
        apiBaseURL: URL,
        refreshToken: String
    ) async throws -> RefreshTokenResult {
        struct Payload: Encodable {
            let refreshToken: String
            enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
        }
        let url = endpoint("auth/refresh", apiBaseURL: apiBaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Payload(refreshToken: refreshToken))
        return try await decode(RefreshTokenResult.self, from: request)
    }

    public func logout(configuration: ServerConfiguration) async throws {
        guard configuration.authenticationMode == .accountSession else { return }
        struct Payload: Encodable {
            let refreshToken: String?
            enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
        }
        let url = endpoint("auth/logout", configuration: configuration)
        var request = self.request(url: url, configuration: configuration)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Payload(refreshToken: configuration.refreshToken))
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
    }

    public func listAccounts(
        configuration: ServerConfiguration,
        etag: String? = nil
    ) async throws -> AccountListResult {
        var components = URLComponents(
            url: endpoint("admin/accounts", configuration: configuration),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "1000"),
            URLQueryItem(name: "sort_by", value: "name"),
            URLQueryItem(name: "sort_order", value: "asc"),
        ]
        guard let url = components?.url else { throw Sub2APIError.invalidResponse }
        var request = request(url: url, configuration: configuration)
        request.timeoutInterval = 25
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await perform(request)
        if response.statusCode == 304 {
            return AccountListResult(accounts: nil, etag: etag)
        }
        try validate(response: response, data: data)
        do {
            let envelope = try decoder.decode(
                APIEnvelope<PaginatedData<CodexAccount>>.self,
                from: data
            )
            return AccountListResult(
                accounts: envelope.data.items,
                etag: response.value(forHTTPHeaderField: "ETag")
            )
        } catch {
            throw Sub2APIError.invalidPayload
        }
    }

    public func quota(
        for accountID: Int,
        configuration: ServerConfiguration
    ) async throws -> OpenAIQuotaUsage {
        let url = endpoint(
            "admin/openai/accounts/\(accountID)/quota",
            configuration: configuration
        )
        var request = request(url: url, configuration: configuration)
        request.timeoutInterval = 30
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(APIEnvelope<OpenAIQuotaUsage>.self, from: data).data
        } catch {
            throw Sub2APIError.invalidPayload
        }
    }

    public func providerUsage(
        for accountID: Int,
        force: Bool = true,
        configuration: ServerConfiguration
    ) async throws -> ProviderUsageInfo {
        var components = URLComponents(
            url: endpoint("admin/accounts/\(accountID)/usage", configuration: configuration),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "source", value: "active"),
            URLQueryItem(name: "force", value: force ? "true" : "false"),
        ]
        guard let url = components?.url else { throw Sub2APIError.invalidResponse }
        var request = request(url: url, configuration: configuration)
        request.timeoutInterval = 40
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(APIEnvelope<ProviderUsageInfo>.self, from: data).data
        } catch {
            throw Sub2APIError.invalidPayload
        }
    }

    public func dashboardStats(
        configuration: ServerConfiguration
    ) async throws -> DashboardUsageStats {
        let path = configuration.isAdministrator
            ? "admin/dashboard/stats"
            : "usage/dashboard/stats"
        let url = endpoint(path, configuration: configuration)
        var request = request(url: url, configuration: configuration)
        request.timeoutInterval = 25
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(APIEnvelope<DashboardUsageStats>.self, from: data).data
        } catch {
            throw Sub2APIError.invalidPayload
        }
    }

    public func openAITokenStats(
        configuration: ServerConfiguration,
        timeRange: String = "1d",
        topN: Int = 10
    ) async throws -> OpenAITokenStatsResponse {
        var components = URLComponents(
            url: endpoint(
                "admin/ops/dashboard/openai-token-stats",
                configuration: configuration
            ),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "time_range", value: timeRange),
            URLQueryItem(name: "platform", value: "openai"),
            URLQueryItem(name: "top_n", value: String(topN)),
        ]
        guard let url = components?.url else { throw Sub2APIError.invalidResponse }
        var request = request(url: url, configuration: configuration)
        request.timeoutInterval = 25
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(APIEnvelope<OpenAITokenStatsResponse>.self, from: data).data
        } catch {
            throw Sub2APIError.invalidPayload
        }
    }

    public func modelUsageStats(
        configuration: ServerConfiguration,
        startDate: String,
        endDate: String,
        timeZoneIdentifier: String
    ) async throws -> ModelUsageStatsResponse {
        let path = configuration.isAdministrator
            ? "admin/dashboard/models"
            : "usage/dashboard/models"
        var components = URLComponents(
            url: endpoint(path, configuration: configuration),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "start_date", value: startDate),
            URLQueryItem(name: "end_date", value: endDate),
            URLQueryItem(name: "timezone", value: timeZoneIdentifier),
            URLQueryItem(name: "model_source", value: "requested"),
        ]
        guard let url = components?.url else { throw Sub2APIError.invalidResponse }
        var request = request(url: url, configuration: configuration)
        request.timeoutInterval = 25
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(APIEnvelope<ModelUsageStatsResponse>.self, from: data).data
        } catch {
            throw Sub2APIError.invalidPayload
        }
    }

    public func usageTrend(
        configuration: ServerConfiguration,
        startDate: String,
        endDate: String,
        timeZoneIdentifier: String,
        granularity: String
    ) async throws -> UsageTrendResponse {
        let path = configuration.isAdministrator
            ? "admin/dashboard/trend"
            : "usage/dashboard/trend"
        var components = URLComponents(
            url: endpoint(path, configuration: configuration),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "start_date", value: startDate),
            URLQueryItem(name: "end_date", value: endDate),
            URLQueryItem(name: "timezone", value: timeZoneIdentifier),
            URLQueryItem(name: "granularity", value: granularity),
        ]
        guard let url = components?.url else { throw Sub2APIError.invalidResponse }
        var request = request(url: url, configuration: configuration)
        request.timeoutInterval = 25
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(APIEnvelope<UsageTrendResponse>.self, from: data).data
        } catch {
            throw Sub2APIError.invalidPayload
        }
    }

    public func accountUsageStats(
        for accountID: Int,
        period: String,
        configuration: ServerConfiguration
    ) async throws -> AccountUsageStats {
        var components = URLComponents(
            url: endpoint("admin/usage/stats", configuration: configuration),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "account_id", value: String(accountID)),
            URLQueryItem(name: "period", value: period),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "nocache", value: "true"),
        ]
        guard let url = components?.url else { throw Sub2APIError.invalidResponse }
        var request = request(url: url, configuration: configuration)
        request.timeoutInterval = 30
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(APIEnvelope<AccountUsageStats>.self, from: data).data
        } catch {
            throw Sub2APIError.invalidPayload
        }
    }

    public func recentUsageLogs(
        for accountID: Int,
        since: Date,
        through endDate: Date,
        configuration: ServerConfiguration
    ) async throws -> [AccountUsageLog] {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var allLogs: [AccountUsageLog] = []
        var page = 1
        while true {
            var components = URLComponents(
                url: endpoint("admin/usage", configuration: configuration),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: "1000"),
                URLQueryItem(name: "account_id", value: String(accountID)),
                URLQueryItem(name: "start_date", value: dateFormatter.string(from: since)),
                URLQueryItem(name: "end_date", value: dateFormatter.string(from: endDate)),
                URLQueryItem(name: "timezone", value: "UTC"),
                URLQueryItem(name: "exact_total", value: "true"),
                URLQueryItem(name: "sort_by", value: "created_at"),
                URLQueryItem(name: "sort_order", value: "desc"),
            ]
            guard let url = components?.url else { throw Sub2APIError.invalidResponse }
            var request = request(url: url, configuration: configuration)
            request.timeoutInterval = 30
            let (data, response) = try await perform(request)
            try validate(response: response, data: data)

            let result: PaginatedData<AccountUsageLog>
            do {
                result = try decoder.decode(
                    APIEnvelope<PaginatedData<AccountUsageLog>>.self,
                    from: data
                ).data
            } catch {
                throw Sub2APIError.invalidPayload
            }
            allLogs.append(contentsOf: result.items)
            guard page < result.pages else { break }
            page += 1
        }
        return allLogs
    }

    public func userPlatformQuotas(
        configuration: ServerConfiguration
    ) async throws -> [UserPlatformQuota] {
        let url = endpoint("user/platform-quotas", configuration: configuration)
        return try await decode(UserPlatformQuotaList.self, from: request(
            url: url,
            configuration: configuration
        )).platformQuotas
    }

    public func userProfile(
        configuration: ServerConfiguration
    ) async throws -> AuthenticatedUser {
        let url = endpoint("user/profile", configuration: configuration)
        return try await decode(AuthenticatedUser.self, from: request(
            url: url,
            configuration: configuration
        ))
    }

    public func userAPIKeys(
        configuration: ServerConfiguration
    ) async throws -> [UserAPIKey] {
        var components = URLComponents(
            url: endpoint("keys", configuration: configuration),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "100"),
        ]
        guard let url = components?.url else { throw Sub2APIError.invalidResponse }
        return try await decode(PaginatedData<UserAPIKey>.self, from: request(
            url: url,
            configuration: configuration
        )).items
    }

    public func userSubscriptionSummary(
        configuration: ServerConfiguration
    ) async throws -> [UserSubscriptionSummary] {
        let url = endpoint("subscriptions/summary", configuration: configuration)
        return try await decode(UserSubscriptionSummaryResponse.self, from: request(
            url: url,
            configuration: configuration
        )).subscriptions
    }

    private func endpoint(_ path: String, configuration: ServerConfiguration) -> URL {
        endpoint(path, apiBaseURL: configuration.apiBaseURL)
    }

    private func endpoint(_ path: String, apiBaseURL: URL) -> URL {
        path.split(separator: "/").reduce(apiBaseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }

    private func request(url: URL, configuration: ServerConfiguration) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch configuration.authenticationMode {
        case .adminAPIKey:
            request.setValue(configuration.adminAPIKey, forHTTPHeaderField: "x-api-key")
        case .accountSession:
            if let token = configuration.accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        return request
    }

    private func decode<Value: Decodable & Sendable>(
        _ type: Value.Type,
        from request: URLRequest
    ) async throws -> Value {
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(APIEnvelope<Value>.self, from: data).data
        } catch {
            throw Sub2APIError.invalidPayload
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw Sub2APIError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as Sub2APIError {
            throw error
        } catch let error as URLError {
            throw Sub2APIError.transport(
                "\(error.localizedDescription)（网络错误 \(error.code.rawValue)）"
            )
        } catch {
            throw Sub2APIError.transport(error.localizedDescription)
        }
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        guard !(200...299).contains(response.statusCode) else { return }
        switch response.statusCode {
        case 401:
            throw Sub2APIError.unauthorized
        case 403:
            throw Sub2APIError.forbidden
        case 423:
            throw Sub2APIError.complianceRequired
        case 429:
            throw Sub2APIError.rateLimited
        case 502...504:
            throw Sub2APIError.upstreamUnavailable
        default:
            let message = (try? decoder.decode(ErrorPayload.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw Sub2APIError.server(status: response.statusCode, message: message)
        }
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = DateParser.parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO 8601 date"
                )
            }
            return date
        }
        return decoder
    }
}

private struct ErrorPayload: Decodable {
    let message: String
}

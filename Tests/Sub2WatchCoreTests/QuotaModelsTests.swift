import XCTest
@testable import Sub2WatchCore

final class QuotaModelsTests: XCTestCase {
    func testConfigurationNormalizesAPIBasePath() throws {
        let configuration = try ServerConfiguration.validated(
            baseURLText: "https://sub2api.example.com/",
            adminAPIKey: "admin-secret",
            allowsInsecureHTTP: false
        )

        XCTAssertEqual(configuration.apiBaseURL.absoluteString, "https://sub2api.example.com/api/v1")
    }

    func testHTTPRequiresExplicitOptIn() {
        XCTAssertThrowsError(
            try ServerConfiguration.validated(
                baseURLText: "http://192.168.1.20:8080",
                adminAPIKey: "admin-secret",
                allowsInsecureHTTP: false
            )
        ) { error in
            XCTAssertEqual(error as? ConfigurationError, .insecureHTTPDisabled)
        }
    }

    func testCachedSnapshotUsesCanonicalWindows() throws {
        let json = """
        {
          "id": 12,
          "name": "codex@example.com",
          "platform": "openai",
          "type": "oauth",
          "status": "active",
          "schedulable": true,
          "error_message": "",
          "extra": {
            "codex_5h_used_percent": 42,
            "codex_5h_reset_at": "2026-07-27T08:00:00Z",
            "codex_7d_used_percent": 88,
            "codex_7d_reset_at": "2026-08-01T08:00:00Z",
            "codex_usage_updated_at": "2026-07-27T07:50:00Z"
          }
        }
        """
        let account = try JSONDecoder().decode(CodexAccount.self, from: Data(json.utf8))
        let snapshot = try XCTUnwrap(account.cachedQuotaSnapshot())

        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 42)
        XCTAssertEqual(snapshot.sevenDay?.usedPercent, 88)
        XCTAssertEqual(snapshot.source, .cached)
    }

    func testLiveQuotaClassifiesWindowsByDuration() throws {
        let json = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "plan_type": "plus",
            "rate_limit": {
              "allowed": true,
              "limit_reached": false,
              "primary_window": {
                "used_percent": 61,
                "limit_window_seconds": 604800,
                "reset_after_seconds": 1000,
                "reset_at": 1785200000
              },
              "secondary_window": {
                "used_percent": 24,
                "limit_window_seconds": 18000,
                "reset_after_seconds": 500,
                "reset_at": 1785100000
              }
            },
            "rate_limit_reset_credits": { "available_count": 2 },
            "fetched_at": 1785000000
          }
        }
        """
        let usage = try JSONDecoder().decode(APIEnvelope<OpenAIQuotaUsage>.self, from: Data(json.utf8)).data
        let account = CodexAccount(
            id: 1,
            name: "Account",
            platform: "openai",
            type: "oauth",
            status: "active",
            schedulable: true,
            errorMessage: nil,
            parentAccountID: nil,
            extra: nil
        )
        let snapshot = usage.snapshot(for: account)

        XCTAssertEqual(snapshot.fiveHour?.usedPercent, 24)
        XCTAssertEqual(snapshot.sevenDay?.usedPercent, 61)
        XCTAssertEqual(snapshot.resetCredits, 2)
    }

    func testAggregateQuotaSummarizesAllReportingAccounts() {
        let summary = AggregateQuotaWindow(
            windows: [
                QuotaWindow(usedPercent: 20, resetsAt: nil),
                QuotaWindow(usedPercent: 60, resetsAt: nil),
            ],
            totalAccountCount: 3
        )

        XCTAssertEqual(summary.reportingAccountCount, 2)
        XCTAssertEqual(summary.totalAccountCount, 3)
        XCTAssertEqual(summary.averageRemainingPercent, 60)
        XCTAssertEqual(summary.minimumRemainingPercent, 40)
        XCTAssertEqual(summary.equivalentAvailableAccounts, 1.2, accuracy: 0.001)
    }

    func testDashboardUsageStatsDecoding() throws {
        let json = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "total_requests": 1000,
            "today_requests": 25,
            "total_input_tokens": 50000,
            "today_input_tokens": 1200,
            "total_output_tokens": 10000,
            "today_output_tokens": 300,
            "total_cache_creation_tokens": 4000,
            "today_cache_creation_tokens": 100,
            "total_cache_read_tokens": 20000,
            "today_cache_read_tokens": 600,
            "total_tokens": 84000,
            "today_tokens": 2200,
            "total_cost": 18.5,
            "today_cost": 0.7,
            "total_actual_cost": 14.8,
            "today_actual_cost": 0.55,
            "average_duration_ms": 1800,
            "rpm": 4,
            "tpm": 3200,
            "total_accounts": 8,
            "normal_accounts": 6,
            "error_accounts": 1,
            "ratelimit_accounts": 1,
            "overload_accounts": 0,
            "stats_updated_at": "2026-07-27T02:00:00Z",
            "stats_stale": false
          }
        }
        """
        let stats = try JSONDecoder().decode(
            APIEnvelope<DashboardUsageStats>.self,
            from: Data(json.utf8)
        ).data

        XCTAssertEqual(stats.todayRequests, 25)
        XCTAssertEqual(stats.todayTokens, 2200)
        XCTAssertEqual(stats.todayCacheReadTokens, 600)
        XCTAssertEqual(stats.tokensPerMinute, 3200)
        XCTAssertEqual(stats.todayActualCost, 0.55)
    }

    func testOpenAIModelStatsDecodesFractionalDates() throws {
        let json = """
        {
          "time_range": "1d",
          "start_time": "2026-07-26T02:00:00.123456Z",
          "end_time": "2026-07-27T02:00:00Z",
          "platform": "openai",
          "items": [{
            "model": "gpt-5.1-codex-max",
            "request_count": 42,
            "avg_tokens_per_sec": 88.5,
            "avg_first_token_ms": 510.2,
            "total_output_tokens": 123456,
            "avg_duration_ms": 6200,
            "requests_with_first_token": 41
          }],
          "total": 1
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let string = try container.decode(String.self)
            return try XCTUnwrap(DateParser.parse(string))
        }
        let stats = try decoder.decode(OpenAITokenStatsResponse.self, from: Data(json.utf8))

        XCTAssertEqual(stats.items.first?.requestCount, 42)
        XCTAssertEqual(stats.items.first?.totalOutputTokens, 123456)
        XCTAssertEqual(stats.items.first?.averageTokensPerSecond, 88.5)
    }

    func testModelUsageStatsDecodingIncludesActualCost() throws {
        let json = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "models": [{
              "model": "gpt-5.6-sol",
              "requests": 662,
              "input_tokens": 70000000,
              "output_tokens": 8000000,
              "cache_creation_tokens": 840000,
              "cache_read_tokens": 5000000,
              "total_tokens": 83840000,
              "cost": 75.0,
              "actual_cost": 62.5,
              "account_cost": 51.0
            }],
            "start_date": "2026-07-21",
            "end_date": "2026-07-27"
          }
        }
        """
        let stats = try JSONDecoder().decode(
            APIEnvelope<ModelUsageStatsResponse>.self,
            from: Data(json.utf8)
        ).data

        XCTAssertEqual(stats.models.first?.requests, 662)
        XCTAssertEqual(stats.models.first?.totalTokens, 83_840_000)
        XCTAssertEqual(stats.models.first?.actualCost, 62.5)
        XCTAssertEqual(stats.startDate, "2026-07-21")
    }

    func testUsageTrendDecodingIncludesTokenSeries() throws {
        let json = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "trend": [{
              "date": "2026-07-27 09:00",
              "requests": 10,
              "input_tokens": 1000,
              "output_tokens": 200,
              "cache_creation_tokens": 50,
              "cache_read_tokens": 500,
              "total_tokens": 1750,
              "cost": 1.2,
              "actual_cost": 0.9
            }],
            "start_date": "2026-07-26",
            "end_date": "2026-07-27",
            "granularity": "hour"
          }
        }
        """
        let stats = try JSONDecoder().decode(
            APIEnvelope<UsageTrendResponse>.self,
            from: Data(json.utf8)
        ).data

        XCTAssertEqual(stats.trend.first?.requests, 10)
        XCTAssertEqual(stats.trend.first?.inputTokens, 1_000)
        XCTAssertEqual(stats.trend.first?.cacheReadTokens, 500)
        XCTAssertEqual(stats.granularity, "hour")
    }

    func testFiveHourUsageFiltersAndTotalsLogs() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let logs = [
            AccountUsageLog(
                inputTokens: 100,
                outputTokens: 20,
                cacheCreationTokens: 10,
                cacheReadTokens: 50,
                actualCost: 0.42,
                createdAt: now.addingTimeInterval(-60 * 60)
            ),
            AccountUsageLog(
                inputTokens: 999,
                outputTokens: 999,
                cacheCreationTokens: 999,
                cacheReadTokens: 999,
                actualCost: 9.99,
                createdAt: now.addingTimeInterval(-6 * 60 * 60)
            ),
        ]

        let metrics = UsageWindowMetrics(
            logs: logs,
            since: now.addingTimeInterval(-5 * 60 * 60)
        )

        XCTAssertEqual(metrics.requestCount, 1)
        XCTAssertEqual(metrics.totalTokens, 180)
        XCTAssertEqual(metrics.cacheReadTokens, 50)
        XCTAssertEqual(metrics.actualCost, 0.42)
    }

    func testAccountUsageStatsDecoding() throws {
        let json = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "total_requests": 353,
            "total_input_tokens": 30000000,
            "total_output_tokens": 4000000,
            "total_cache_creation_tokens": 100000,
            "total_cache_read_tokens": 9300000,
            "total_cache_tokens": 9400000,
            "total_tokens": 43400000,
            "total_cost": 45.2,
            "total_actual_cost": 40.92,
            "average_duration_ms": 1800
          }
        }
        """
        let stats = try JSONDecoder().decode(
            APIEnvelope<AccountUsageStats>.self,
            from: Data(json.utf8)
        ).data
        let metrics = UsageWindowMetrics(stats: stats)

        XCTAssertEqual(metrics.requestCount, 353)
        XCTAssertEqual(metrics.totalTokens, 43_400_000)
        XCTAssertEqual(metrics.actualCost, 40.92)
    }

    func testProviderUsageMapsPlatformSpecificWindows() throws {
        let json = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "updated_at": null,
            "five_hour": { "utilization": 35, "resets_at": null, "remaining_seconds": 100 },
            "seven_day": { "utilization": 62, "resets_at": null, "remaining_seconds": 200 },
            "seven_day_sonnet": { "utilization": 71, "resets_at": null, "remaining_seconds": 200 },
            "gemini_shared_daily": {
              "utilization": 44,
              "resets_at": null,
              "remaining_seconds": 300,
              "window_stats": { "requests": 22, "tokens": 3300, "cost": 1.25 }
            },
            "gemini_shared_minute": { "utilization": 10, "resets_at": null, "remaining_seconds": 20 },
            "antigravity_quota": {
              "claude-sonnet-4": { "utilization": 52, "reset_time": "2026-07-28T12:00:00Z" }
            },
            "grok_billing": {
              "period_type": "weekly",
              "usage_percent": 47,
              "period_end": "2026-08-01T00:00:00Z",
              "plan": "SuperGrok"
            },
            "subscription_tier": "pro"
          }
        }
        """
        let usage = try JSONDecoder().decode(
            APIEnvelope<ProviderUsageInfo>.self,
            from: Data(json.utf8)
        ).data

        let claude = usage.snapshot(for: providerAccount(id: 1, platform: "anthropic"))
        XCTAssertEqual(claude.windows.map(\.id), ["5h", "7d", "7d-sonnet"])
        XCTAssertEqual(claude.windows[0].quota.remainingPercent, 65)

        let gemini = usage.snapshot(for: providerAccount(id: 2, platform: "gemini"))
        XCTAssertEqual(gemini.windows.map(\.id), ["shared-daily", "shared-minute"])
        XCTAssertEqual(gemini.windows[0].metrics?.requestCount, 22)
        XCTAssertEqual(gemini.windows[0].metrics?.totalTokens, 3_300)

        let antigravity = usage.snapshot(
            for: providerAccount(id: 3, platform: "antigravity")
        )
        XCTAssertEqual(antigravity.windows.first?.label, "sonnet-4")
        XCTAssertEqual(antigravity.windows.first?.quota.remainingPercent, 48)

        let grok = usage.snapshot(for: providerAccount(id: 4, platform: "grok"))
        XCTAssertEqual(grok.windows.first?.id, "7d")
        XCTAssertEqual(grok.windows.first?.quota.remainingPercent, 53)
    }

    func testAccountProviderCapabilitiesMatchSub2API() {
        XCTAssertTrue(providerAccount(id: 1, platform: "openai").supportsProviderUsage)
        XCTAssertTrue(providerAccount(id: 2, platform: "anthropic").supportsProviderUsage)
        XCTAssertTrue(providerAccount(id: 3, platform: "gemini", type: "apikey").supportsProviderUsage)
        XCTAssertTrue(providerAccount(id: 4, platform: "antigravity").supportsProviderUsage)
        XCTAssertTrue(providerAccount(id: 5, platform: "grok").supportsProviderUsage)
        XCTAssertFalse(providerAccount(id: 6, platform: "openai", type: "apikey").supportsProviderUsage)
    }

    func testLegacyConfigurationDecodesAsAdminAPIKey() throws {
        let json = """
        {
          "apiBaseURL": "https://sub2api.example.com/api/v1",
          "adminAPIKey": "legacy-secret",
          "allowsInsecureHTTP": false
        }
        """
        let configuration = try JSONDecoder().decode(
            ServerConfiguration.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(configuration.authenticationMode, .adminAPIKey)
        XCTAssertTrue(configuration.isAdministrator)
        XCTAssertEqual(configuration.adminAPIKey, "legacy-secret")
    }

    func testTwoFactorLoginResponseDecodesWithoutSession() throws {
        let json = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "requires_2fa": true,
            "temp_token": "temporary-token",
            "user_email_masked": "de***@example.com"
          }
        }
        """
        let result = try JSONDecoder().decode(
            APIEnvelope<LoginResult>.self,
            from: Data(json.utf8)
        ).data

        XCTAssertTrue(result.requires2FA)
        XCTAssertEqual(result.tempToken, "temporary-token")
        XCTAssertNil(result.accessToken)
    }

    func testRefreshResponseAllowsUnrotatedRefreshToken() throws {
        let json = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "access_token": "new-access-token"
          }
        }
        """
        let result = try JSONDecoder().decode(
            APIEnvelope<RefreshTokenResult>.self,
            from: Data(json.utf8)
        ).data

        XCTAssertEqual(result.accessToken, "new-access-token")
        XCTAssertNil(result.refreshToken)
        XCTAssertNil(result.expiresIn)
    }

    func testReplacingTokensKeepsExistingRefreshTokenWhenServerDoesNotRotateIt() {
        let user = AuthenticatedUser(
            id: 42,
            email: "user@example.com",
            username: "User",
            role: .user,
            balance: 10,
            status: "active"
        )
        let configuration = ServerConfiguration(
            apiBaseURL: URL(string: "https://sub2api.example.com/api/v1")!,
            allowsInsecureHTTP: false,
            accessToken: "old-access-token",
            refreshToken: "existing-refresh-token",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 100),
            user: user
        )

        let refreshed = configuration.replacingTokens(
            accessToken: "new-access-token",
            refreshToken: nil,
            expiresIn: nil
        )

        XCTAssertEqual(refreshed.accessToken, "new-access-token")
        XCTAssertEqual(refreshed.refreshToken, "existing-refresh-token")
        XCTAssertNil(refreshed.accessTokenExpiresAt)
    }

    func testForbiddenErrorIsNotReportedAsExpiredLogin() {
        XCTAssertEqual(Sub2APIError.forbidden.errorDescription, "当前账号无权访问此功能")
    }

    func testUserDashboardPayloadDefaultsAdminOnlyFields() throws {
        let json = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "total_requests": 20,
            "today_requests": 3,
            "total_input_tokens": 100,
            "today_input_tokens": 10,
            "total_output_tokens": 50,
            "today_output_tokens": 5,
            "total_cache_creation_tokens": 0,
            "today_cache_creation_tokens": 0,
            "total_cache_read_tokens": 30,
            "today_cache_read_tokens": 3,
            "total_tokens": 180,
            "today_tokens": 18,
            "total_cost": 2.0,
            "today_cost": 0.2,
            "total_actual_cost": 1.5,
            "today_actual_cost": 0.15,
            "average_duration_ms": 900,
            "rpm": 1,
            "tpm": 18
          }
        }
        """
        let stats = try JSONDecoder().decode(
            APIEnvelope<DashboardUsageStats>.self,
            from: Data(json.utf8)
        ).data

        XCTAssertEqual(stats.todayTokens, 18)
        XCTAssertEqual(stats.totalAccounts, 0)
    }

    func testUserModelPayloadAllowsMissingAccountCost() throws {
        let json = """
        {
          "model": "gpt-5",
          "requests": 2,
          "input_tokens": 10,
          "output_tokens": 5,
          "cache_creation_tokens": 0,
          "cache_read_tokens": 3,
          "total_tokens": 18,
          "cost": 0.2,
          "actual_cost": 0.15
        }
        """
        let model = try JSONDecoder().decode(ModelUsageStat.self, from: Data(json.utf8))
        XCTAssertEqual(model.accountCost, 0)
    }

    private func providerAccount(
        id: Int,
        platform: String,
        type: String = "oauth"
    ) -> CodexAccount {
        CodexAccount(
            id: id,
            name: "Account \(id)",
            platform: platform,
            type: type,
            status: "active",
            schedulable: true,
            errorMessage: nil,
            parentAccountID: nil,
            extra: nil
        )
    }
}

import Foundation
@testable import GitHubCopilotUsageSpikeCore
import Testing

@Suite("GitHub Copilot usage decoding")
struct GitHubCopilotUsageDecoderTests {
    @Test
    func `maps credits and enabled overage while suppressing unlimited buckets`() throws {
        let usage = try GitHubCopilotUsageDecoder.decodeUsage(
            GitHubCopilotTestSupport.usageResponse().body,
        )

        #expect(usage.planName == "Pro")
        #expect(usage.metrics.count == 2)
        guard case let .percentage(credits) = usage.metrics[0],
              case let .amount(extra) = usage.metrics[1]
        else {
            Issue.record("Expected Credits and Extra Usage")
            return
        }
        #expect(credits.usedFraction == 0.6)
        #expect(credits.resetsAt != nil)
        #expect(extra.used == Decimal(2))
        #expect(extra.limit == nil)
    }

    @Test
    func `maps current free chat and completion snapshots`() throws {
        let data = Data(
            """
            {
              "copilot_plan":"individual",
              "limited_user_reset_date":"2026-09-30",
              "quota_snapshots":{
                "premium_interactions":{"entitlement":0,"remaining":0},
                "chat":{"entitlement":100,"remaining":75,"percent_remaining":75},
                "completions":{"entitlement":2000,"remaining":1900,"percent_remaining":95}
              }
            }
            """.utf8,
        )

        let usage = try GitHubCopilotUsageDecoder.decodeUsage(data)

        #expect(usage.metrics.count == 2)
        guard case let .percentage(chat) = usage.metrics[0],
              case let .percentage(completions) = usage.metrics[1]
        else {
            Issue.record("Expected free percentage buckets")
            return
        }
        #expect(chat.usedFraction == 0.25)
        #expect(completions.usedFraction == 0.05)
    }

    @Test
    func `maps legacy free counts without inventing a percentage`() throws {
        let data = Data(
            """
            {
              "copilot_plan":"free",
              "limited_user_quotas":{"chat":250,"completions":1500},
              "monthly_quotas":{"chat":500,"completions":2000}
            }
            """.utf8,
        )

        let usage = try GitHubCopilotUsageDecoder.decodeUsage(data)

        guard case let .amount(chat) = usage.metrics[0],
              case let .amount(completions) = usage.metrics[1]
        else {
            Issue.record("Expected legacy count buckets")
            return
        }
        #expect(chat.used == Decimal(250))
        #expect(chat.limit == Decimal(500))
        #expect(completions.used == Decimal(500))
    }

    @Test
    func `preserves organization managed personal credits or honest empty state`() throws {
        let withCredits = Data(
            """
            {
              "copilot_plan":"business",
              "token_based_billing":true,
              "quota_snapshots":{"premium_interactions":{"entitlement":0,"credits_used":2111}}
            }
            """.utf8,
        )
        let empty = Data(
            """
            {"copilot_plan":"business","token_based_billing":true,"quota_snapshots":{}}
            """.utf8,
        )

        let personal = try GitHubCopilotUsageDecoder.decodeUsage(withCredits)
        let unavailable = try GitHubCopilotUsageDecoder.decodeUsage(empty)

        #expect(personal.isOrganizationManaged)
        guard case let .amount(credits) = personal.metrics[0] else {
            Issue.record("Expected personal credits")
            return
        }
        #expect(credits.used == Decimal(2111))
        #expect(unavailable.isOrganizationManaged)
        #expect(unavailable.metrics.isEmpty)
    }

    @Test
    func `rejects booleans as quota numbers and malformed reset dates`() {
        let boolean = Data(
            """
            {"quota_snapshots":{"chat":{"entitlement":true,"remaining":1}}}
            """.utf8,
        )
        let date = Data(
            """
            {
              "quota_reset_date":"tomorrow",
              "quota_snapshots":{"chat":{"entitlement":1,"remaining":1}}
            }
            """.utf8,
        )

        #expect(throws: GitHubCopilotSpikeError.quotaUnavailable) {
            try GitHubCopilotUsageDecoder.decodeUsage(boolean)
        }
        #expect(throws: GitHubCopilotSpikeError.invalidResponse) {
            try GitHubCopilotUsageDecoder.decodeUsage(date)
        }
    }
}

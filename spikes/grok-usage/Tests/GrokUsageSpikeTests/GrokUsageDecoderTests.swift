import Foundation
@testable import GrokUsageSpikeCore
import Testing

@Suite("Grok usage decoding")
struct GrokUsageDecoderTests {
    @Test
    func `maps weekly percentage and on demand cents`() throws {
        let metrics = try GrokUsageDecoder.decodeUsage(
            GrokSpikeTestSupport.billingResponse(percent: 42.5).body,
        )

        #expect(metrics.count == 2)
        guard case let .percentage(weekly) = metrics[0],
              case let .amount(onDemand) = metrics[1]
        else {
            Issue.record("Expected percentage then amount metrics")
            return
        }
        #expect(weekly.id == "included-weekly")
        #expect(weekly.usedFraction == 0.425)
        #expect(weekly.windowDuration == 604_800.0)
        #expect(onDemand.used == Decimal(string: "1.25"))
        #expect(onDemand.limit == Decimal(5))
    }

    @Test
    func `treats omitted proto zero percentage as zero for a returned period`() throws {
        let data = Data(
            """
            {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY"}}}
            """.utf8,
        )

        let metrics = try GrokUsageDecoder.decodeUsage(data)

        guard case let .percentage(monthly) = metrics[0] else {
            Issue.record("Expected a monthly percentage")
            return
        }
        #expect(monthly.id == "included-monthly")
        #expect(monthly.usedFraction == 0)
    }

    @Test
    func `maps the legacy monthly amount response`() throws {
        let data = Data(
            """
            {
              "config": {
                "monthlyLimit": {"val": 2000},
                "used": {"val": "1234"},
                "billingPeriodEnd": "2026-09-01T00:00:00.000Z"
              }
            }
            """.utf8,
        )

        let metrics = try GrokUsageDecoder.decodeUsage(data)

        guard case let .amount(monthly) = metrics[0] else {
            Issue.record("Expected a monthly amount")
            return
        }
        #expect(monthly.used == Decimal(string: "12.34"))
        #expect(monthly.limit == Decimal(20))
        #expect(monthly.resetsAt != nil)
    }

    @Test
    func `rejects malformed dates and negative usage`() {
        let malformedDate = Data(
            """
            {"config":{"creditUsagePercent":1,"currentPeriod":{"end":"tomorrow"}}}
            """.utf8,
        )
        let negative = Data(#"{"config":{"creditUsagePercent":-1}}"#.utf8)

        #expect(throws: GrokSpikeError.invalidResponse) {
            try GrokUsageDecoder.decodeUsage(malformedDate)
        }
        #expect(throws: GrokSpikeError.invalidResponse) {
            try GrokUsageDecoder.decodeUsage(negative)
        }
    }

    @Test
    func `requires a canonical remote user identifier`() {
        #expect(throws: GrokSpikeError.invalidResponse) {
            try GrokUsageDecoder.decodeIdentity(Data(#"{"subscriptionTier":"Pro"}"#.utf8))
        }
    }
}

@testable import ClaudeUsageSpikeCore
import Foundation
import Testing

@Suite("Claude usage decoder")
struct ClaudeUsageDecoderTests {
    @Test
    func `maps returned limits dynamically and replaces legacy duplicates`() throws {
        let metrics = try ClaudeUsageDecoder.decode(Data(
            #"""
            {
              "five_hour": {"utilization": 11, "resets_at": "2030-01-01T00:00:00Z"},
              "seven_day": {"utilization": 22, "resets_at": "2030-01-02T00:00:00Z"},
              "limits": [
                {
                  "kind": "session", "percent": 13,
                  "resets_at": "2030-01-03T00:00:00Z", "scope": null
                },
                {
                  "kind": "weekly_all", "percent": 24,
                  "resets_at": "2030-01-04T00:00:00Z", "scope": null
                },
                {
                  "kind": "weekly_scoped", "percent": 35,
                  "resets_at": "2030-01-05T00:00:00Z",
                  "scope": {
                    "model": {"id": null, "display_name": "Fable"}, "surface": null
                  }
                },
                {"kind": "daily_bonus", "percent": 46, "resets_at": null, "scope": null}
              ],
              "extra_usage": {
                "is_enabled": true,
                "used_credits": 1234,
                "monthly_limit": 5000,
                "currency": "usd",
                "decimal_places": 2
              }
            }
            """#.utf8,
        ))

        let percentages = metrics.compactMap { metric -> ClaudePercentageMetric? in
            guard case let .percentage(value) = metric else {
                return nil
            }
            return value
        }
        let amount = try #require(metrics.compactMap { metric -> ClaudeAmountMetric? in
            guard case let .amount(value) = metric else {
                return nil
            }
            return value
        }.first)

        #expect(percentages.map(\.id) == ["session", "weekly", "weekly:fable", "daily-bonus"])
        #expect(percentages.map(\.usedFraction) == [0.13, 0.24, 0.35, 0.46])
        #expect(amount.value == Decimal(string: "12.34"))
        #expect(amount.limit == Decimal(50))
        #expect(amount.unit == "USD")
    }

    @Test
    func `omits missing and invalid windows without inventing zero values`() throws {
        let metrics = try ClaudeUsageDecoder.decode(Data(
            #"{"five_hour":null,"seven_day":{"utilization":-1},"limits":[]}"#.utf8,
        ))

        #expect(metrics.isEmpty)
    }

    @Test
    func `rejects malformed response`() {
        #expect(throws: ClaudeSpikeError.invalidResponse) {
            try ClaudeUsageDecoder.decode(Data("not-json".utf8))
        }
    }
}

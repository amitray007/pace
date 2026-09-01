import Foundation
@testable import PaceProviders
import Testing

@Suite("Claude usage decoding")
struct ClaudeUsageDecoderTests {
    @Test
    func `maps returned windows dynamically and replaces legacy duplicates`() throws {
        let metrics = try ClaudeUsageDecoder.decode(Data(
            #"""
            {
              "five_hour": {"utilization": 11, "resets_at": "2030-01-01T00:00:00Z"},
              "seven_day": {"utilization": 22, "resets_at": "2030-01-02T00:00:00Z"},
              "limits": [
                {"kind":"session","percent":13,"resets_at":"2030-01-03T00:00:00Z"},
                {"kind":"weekly_all","percent":24,"resets_at":"2030-01-04T00:00:00Z"},
                {
                  "kind":"weekly_scoped","percent":35,
                  "resets_at":"2030-01-05T00:00:00Z",
                  "scope":{"model":{"id":null,"display_name":"Fable"}}
                },
                {"kind":"daily_bonus","percent":46,"resets_at":null}
              ],
              "extra_usage": {
                "is_enabled":true,"used_credits":1234,"monthly_limit":5000,
                "currency":"usd","decimal_places":2
              }
            }
            """#.utf8,
        ))

        let percentages = metrics.compactMap { metric -> ClaudePercentageMetric? in
            guard case let .percentage(value) = metric else { return nil }
            return value
        }
        let amount = try #require(metrics.compactMap { metric -> ClaudeAmountMetric? in
            guard case let .amount(value) = metric else { return nil }
            return value
        }.first)

        #expect(percentages.map(\.id) == [
            "current-session",
            "weekly-all-models",
            "weekly-fable",
            "daily-bonus",
        ])
        #expect(percentages.map(\.usedFraction) == [0.13, 0.24, 0.35, 0.46])
        #expect(amount.used == Decimal(string: "12.34"))
        #expect(amount.limit == Decimal(50))
        #expect(amount.unit == "USD")
    }

    @Test
    func `omits missing invalid and amount only counters`() throws {
        let metrics = try ClaudeUsageDecoder.decode(Data(
            #"""
            {
              "five_hour": null,
              "seven_day": {"utilization": -1},
              "limits": [{"kind":"daily","percent":-2}],
              "extra_usage":{"is_enabled":true,"used_credits":1234,"monthly_limit":null}
            }
            """#.utf8,
        ))

        #expect(metrics.isEmpty)
    }

    @Test
    func `rejects malformed envelope and oversized transport body`() async {
        #expect(throws: ClaudeProviderError.invalidResponse) {
            try ClaudeUsageDecoder.decode(Data("not-json".utf8))
        }
        await #expect(throws: ClaudeProviderError.invalidResponse) {
            try await ClaudeURLSessionTransport.boundedData(
                from: AsyncStream { continuation in
                    continuation.yield(1)
                    continuation.yield(2)
                    continuation.finish()
                },
                maximumSize: 1,
            )
        }
    }
}

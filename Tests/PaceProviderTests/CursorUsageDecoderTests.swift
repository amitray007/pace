import Foundation
@testable import PaceProviders
import Testing

@Suite("Cursor production usage decoding")
struct CursorUsageDecoderTests {
    @Test
    func `maps provider ordered percentages cycle and on demand spend`() throws {
        let metrics = try CursorUsageDecoder.decode(Data(
            """
            {
              "enabled": true,
              "billingCycleStart": 1788134400000,
              "billingCycleEnd": 1788739200000,
              "planUsage": {
                "totalPercentUsed": 42,
                "autoPercentUsed": 20,
                "apiPercentUsed": 22
              },
              "spendLimitUsage": {
                "individualLimit": 10000,
                "individualRemaining": 7500
              }
            }
            """.utf8,
        ))

        #expect(metrics.count == 4)
        guard case let .percentage(total) = metrics[0],
              case let .amount(extra) = metrics[3]
        else {
            Issue.record("Expected ordered total percentage and extra usage amount")
            return
        }
        #expect(total.usedFraction == 0.42)
        #expect(total.windowDuration == 604_800)
        #expect(extra.used == 25)
        #expect(extra.limit == 100)
    }

    @Test
    func `reads Connect string-encoded billing cycle timestamps`() throws {
        // Live `GetCurrentPeriodUsage` encodes its int64 cycle bounds as JSON strings.
        let metrics = try CursorUsageDecoder.decode(Data(
            """
            {
              "enabled": true,
              "billingCycleStart": "1787734692000",
              "billingCycleEnd": "1790413092000",
              "planUsage": {"totalPercentUsed": 9.6}
            }
            """.utf8,
        ))

        guard case let .percentage(total) = metrics.first else {
            Issue.record("Expected total percentage")
            return
        }
        #expect(total.resetsAt == Date(timeIntervalSince1970: 1_790_413_092))
        #expect(total.windowDuration == 2_678_400)
    }

    @Test
    func `omits the cycle when its bounds are not numeric`() throws {
        let metrics = try CursorUsageDecoder.decode(Data(
            """
            {
              "enabled": true,
              "billingCycleStart": "soon",
              "billingCycleEnd": "",
              "planUsage": {"totalPercentUsed": 9.6, "autoPercentUsed": "true"}
            }
            """.utf8,
        ))

        #expect(metrics.count == 1)
        guard case let .percentage(total) = metrics.first else {
            Issue.record("Expected total percentage")
            return
        }
        #expect(total.resetsAt == nil)
        #expect(total.windowDuration == nil)
    }

    @Test
    func `uses capped amount when total percentage is absent`() throws {
        let metrics = try CursorUsageDecoder.decode(Data(
            """
            {
              "enabled": true,
              "planUsage": {"limit": 5000, "totalSpend": 1250}
            }
            """.utf8,
        ))

        guard case let .amount(total) = metrics.first else {
            Issue.record("Expected total amount")
            return
        }
        #expect(total.used == 12.5)
        #expect(total.limit == 50)
    }

    @Test
    func `omits on demand usage when only a limit is present`() throws {
        let metrics = try CursorUsageDecoder.decode(Data(
            #"{"enabled":true,"planUsage":{},"spendLimitUsage":{"individualLimit":10000}}"#.utf8,
        ))

        #expect(metrics.isEmpty)
    }

    @Test
    func `rejects disabled malformed and boolean usage values`() throws {
        #expect(throws: CursorProviderError.invalidResponse) {
            try CursorUsageDecoder.decode(Data(#"{"enabled":false,"planUsage":{}}"#.utf8))
        }

        let metrics = try CursorUsageDecoder.decode(Data(
            #"{"enabled":true,"planUsage":{"totalPercentUsed":true}}"#.utf8,
        ))
        #expect(metrics.isEmpty)
    }
}

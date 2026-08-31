@testable import CursorUsageSpikeCore
import Foundation
import Testing

@Suite("Cursor usage decoder")
struct CursorUsageDecoderTests {
    @Test
    func `maps returned pools cycle and on demand spend`() throws {
        let metrics = try CursorUsageDecoder.decode(Data(
            """
            {
              "enabled": true,
              "billingCycleStart": 1788134400000,
              "billingCycleEnd": 1790812800000,
              "planUsage": {
                "totalPercentUsed": 20,
                "autoPercentUsed": 12.5,
                "apiPercentUsed": 7.5
              },
              "spendLimitUsage": {
                "individualLimit": 5000,
                "individualRemaining": 1000
              }
            }
            """.utf8,
        ))

        #expect(metrics.count == 4)
        guard case let .percentage(total) = metrics[0] else {
            Issue.record("Expected total percentage")
            return
        }
        #expect(total.id == "total")
        #expect(total.usedFraction == 0.2)
        #expect(total.windowDuration == 2_678_400)
        #expect(total.resetsAt == Date(timeIntervalSince1970: 1_790_812_800))

        guard case let .amount(onDemand) = metrics[3] else {
            Issue.record("Expected on-demand amount")
            return
        }
        #expect(onDemand.used == 40)
        #expect(onDemand.limit == 50)
        #expect(onDemand.unit == "USD")
    }

    @Test
    func `uses amount when Cursor omits total percentage`() throws {
        let metrics = try CursorUsageDecoder.decode(Data(
            """
            {
              "enabled": true,
              "planUsage": {
                "limit": 40000,
                "remaining": 32000
              }
            }
            """.utf8,
        ))

        #expect(metrics == [
            .amount(CursorAmountMetric(
                id: "total",
                label: "Total Usage",
                used: 80,
                limit: 400,
                unit: "USD",
                resetsAt: nil,
            )),
        ])
    }

    @Test
    func `does not accept booleans as numeric usage`() {
        #expect(throws: CursorSpikeError.invalidResponse) {
            try CursorUsageDecoder.decode(Data(
                """
                {
                  "enabled": true,
                  "planUsage": {"totalPercentUsed": true}
                }
                """.utf8,
            ))
        }
    }

    @Test
    func `normalizes plan label`() {
        let plan = CursorUsageDecoder.decodePlan(Data(
            #"{"planInfo":{"planName":"  PRO PLUS  "}}"#.utf8,
        ))
        #expect(plan == "Pro Plus")
        #expect(CursorUsageDecoder.decodePlan(Data(#"{"planInfo":{"planName":42}}"#.utf8)) == nil)
    }
}

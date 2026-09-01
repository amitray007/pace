import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Codex rate-limit normalization")
struct CodexRateLimitNormalizerTests {
    private let accountID: AccountID = {
        guard let uuid = UUID(uuidString: "10000000-0000-0000-0000-000000000001") else {
            preconditionFailure("Invalid test UUID")
        }
        return AccountID(rawValue: uuid)
    }()

    private let observedAt = Date(timeIntervalSince1970: 1_788_134_400)

    @Test
    func `decodes and preserves every returned limit window`() throws {
        let response = try JSONDecoder().decode(
            CodexRateLimitsResponse.self,
            from: Data(Self.multiBucketFixture.utf8),
        )

        let snapshots = try CodexRateLimitNormalizer.normalize(
            response,
            accountID: accountID,
            observedAt: observedAt,
        )

        #expect(snapshots.map(\.id.bucketID.rawValue) == [
            "codex.primary",
            "codex.secondary",
            "gpt-5.3-codex.primary",
        ])
        #expect(snapshots.map(\.label) == [
            "Codex · 5-hour",
            "Codex · 7-day",
            "GPT-5.3-Codex · 5-hour",
        ])
        #expect(snapshots.map(\.usedFraction) == [0.21, 0.63, 0.48])
        #expect(snapshots.allSatisfy { $0.id.accountID == accountID })
        #expect(snapshots.allSatisfy { $0.observedAt == observedAt })
    }

    @Test
    func `uses the backward compatible bucket when the map is absent`() throws {
        let response = try JSONDecoder().decode(
            CodexRateLimitsResponse.self,
            from: Data(Self.singleBucketFixture.utf8),
        )

        let snapshots = try CodexRateLimitNormalizer.normalize(
            response,
            accountID: accountID,
            observedAt: observedAt,
        )

        #expect(snapshots.count == 1)
        #expect(snapshots[0].id.bucketID.rawValue == "codex.primary")
        #expect(snapshots[0].label == "Codex · 7-day")
    }

    @Test
    func `omits a negative malformed window instead of inventing usage`() throws {
        let response = try JSONDecoder().decode(
            CodexRateLimitsResponse.self,
            from: Data(Self.negativeWindowFixture.utf8),
        )

        let snapshots = try CodexRateLimitNormalizer.normalize(
            response,
            accountID: accountID,
            observedAt: observedAt,
        )

        #expect(snapshots.isEmpty)
    }

    private static let multiBucketFixture = #"""
    {
      "rateLimits": {
        "limitId": "codex",
        "limitName": "Codex",
        "planType": "plus",
        "primary": {"usedPercent": 21, "windowDurationMins": 300, "resetsAt": 1788145200},
        "secondary": {"usedPercent": 63, "windowDurationMins": 10080, "resetsAt": 1788748800}
      },
      "rateLimitsByLimitId": {
        "gpt-5.3-codex": {
          "limitId": "gpt-5.3-codex",
          "limitName": "GPT-5.3-Codex",
          "planType": "plus",
          "primary": {"usedPercent": 48, "windowDurationMins": 300, "resetsAt": 1788148800},
          "secondary": null
        },
        "codex": {
          "limitId": "codex",
          "limitName": "Codex",
          "planType": "plus",
          "primary": {"usedPercent": 21, "windowDurationMins": 300, "resetsAt": 1788145200},
          "secondary": {"usedPercent": 63, "windowDurationMins": 10080, "resetsAt": 1788748800}
        }
      }
    }
    """#

    private static let singleBucketFixture = #"""
    {
      "rateLimits": {
        "limitId": "codex",
        "limitName": null,
        "planType": "plus",
        "primary": {"usedPercent": 9, "windowDurationMins": 10080, "resetsAt": null},
        "secondary": null
      },
      "rateLimitsByLimitId": null
    }
    """#

    private static let negativeWindowFixture = #"""
    {
      "rateLimits": {
        "limitId": "codex",
        "limitName": "Codex",
        "planType": "plus",
        "primary": {"usedPercent": -1, "windowDurationMins": 300, "resetsAt": null},
        "secondary": null
      }
    }
    """#
}

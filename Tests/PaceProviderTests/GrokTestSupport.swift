import Foundation
import PaceCore
@testable import PaceProviders

enum GrokTestSupport {
    static let observedAt = Date(timeIntervalSince1970: 1_788_134_400)

    static func profile(
        _ name: String = "personal",
        expectedIdentity: ProviderIdentity? = nil,
    ) -> GrokProfile {
        GrokProfile(
            directory: URL(filePath: "/profiles/grok/\(name)", directoryHint: .isDirectory),
            ownership: name == "work" ? .paceManaged : .existing,
            displayName: name.capitalized,
            expectedIdentity: expectedIdentity,
        )
    }

    static func identity(
        userID: String = "user-a",
        principalID: String? = "principal-a",
        teamID: String? = nil,
    ) -> GrokIdentity {
        GrokIdentity(
            userID: userID,
            principalID: principalID,
            teamID: teamID,
            email: "\(userID)@example.invalid",
            displayName: userID.capitalized,
        )
    }

    static func result(
        identity: GrokIdentity = identity(),
        metrics: [GrokMetric] = weeklyMetrics(),
    ) -> GrokUsageResult {
        GrokUsageResult(
            identity: identity,
            planName: "SuperGrok",
            metrics: metrics,
            observedAt: observedAt,
        )
    }

    static func weeklyMetrics() -> [GrokMetric] {
        [
            .percentage(GrokPercentageMetric(
                id: "included-weekly",
                label: "Weekly Limit",
                usedFraction: 0.42,
                resetsAt: observedAt.addingTimeInterval(604_800),
                windowDuration: 604_800,
            )),
            .amount(GrokAmountMetric(
                id: "on-demand",
                label: "Pay As You Go",
                used: Decimal(2),
                limit: Decimal(10),
                resetsAt: nil,
            )),
        ]
    }

    static func identityResponse(
        userID: String = "user-a",
        principalID: String = "principal-a",
        teamID: String? = nil,
    ) -> GrokHTTPResponse {
        let team = teamID.map { #", "teamId": "\#($0)""# } ?? ""
        return GrokHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "userId": "\(userID)",
                  "principalId": "\(principalID)"\(team),
                  "email": "\(userID)@example.invalid",
                  "subscriptionTier": "SuperGrok"
                }
                """.utf8,
            ),
        )
    }

    static func billingResponse() -> GrokHTTPResponse {
        GrokHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "config": {
                    "creditUsagePercent": 42,
                    "currentPeriod": {
                      "type": "USAGE_PERIOD_TYPE_WEEKLY",
                      "start": "2026-08-24T00:00:00Z",
                      "end": "2026-08-31T00:00:00Z"
                    },
                    "onDemandCap": {"val": 1000},
                    "onDemandUsed": {"val": 200}
                  }
                }
                """.utf8,
            ),
        )
    }
}

actor GrokStubReader: GrokUsageReading {
    private let results: [String: Result<GrokUsageResult, GrokProviderError>]
    private(set) var reads: [(profile: GrokProfile, includeUsage: Bool)] = []

    init(results: [String: Result<GrokUsageResult, GrokProviderError>]) {
        self.results = results
    }

    func read(
        profile: GrokProfile,
        includeUsage: Bool,
    ) throws(GrokProviderError) -> GrokUsageResult {
        reads.append((profile, includeUsage))
        guard let result = results[profile.directory.path] else {
            throw .invalidResponse
        }
        return try result.get()
    }
}

struct GrokStubCredentialLoader: GrokCredentialLoading {
    let credentials: [String: GrokCredential]

    func load(for profile: GrokProfile) throws(GrokProviderError) -> GrokCredential {
        guard let credential = credentials[profile.directory.path] else {
            throw .signedOut
        }
        return credential
    }
}

actor GrokStubTransport: GrokHTTPTransport {
    typealias Handler = @Sendable (URLRequest) throws -> GrokHTTPResponse

    private let handler: Handler
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest) throws -> GrokHTTPResponse {
        requests.append(request)
        return try handler(request)
    }
}

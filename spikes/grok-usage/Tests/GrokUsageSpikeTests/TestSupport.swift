import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
@testable import GrokUsageSpikeCore

enum GrokSpikeTestSupport {
    static let referenceDate = Date(timeIntervalSince1970: 1_788_134_400)

    static func profile(
        _ name: String = "default",
        expectedIdentity: GrokIdentity? = nil,
    ) -> GrokProfileBinding {
        GrokProfileBinding(
            grokHome: URL(filePath: "/profiles/\(name)", directoryHint: .isDirectory),
            expectedIdentity: expectedIdentity,
        )
    }

    static func identity(
        userID: String = "user-a",
        principalID: String? = "principal-a",
        teamID: String? = "team-a",
    ) -> GrokIdentity {
        GrokIdentity(userID: userID, principalID: principalID, teamID: teamID)
    }

    static func identityResponse(
        userID: String = "user-a",
        principalID: String? = "principal-a",
        teamID: String? = "team-a",
    ) -> GrokHTTPResponse {
        let principal = principalID.map { "\"principalId\": \"\($0)\"," } ?? ""
        let team = teamID.map { "\"teamId\": \"\($0)\"," } ?? ""
        return GrokHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "userId": "\(userID)",
                  \(principal)
                  \(team)
                  "email": "hidden@example.invalid",
                  "firstName": "Hidden",
                  "subscriptionTier": "SuperGrok Heavy"
                }
                """.utf8,
            ),
        )
    }

    static func billingResponse(percent: Double = 25) -> GrokHTTPResponse {
        GrokHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "config": {
                    "creditUsagePercent": \(percent),
                    "currentPeriod": {
                      "type": "USAGE_PERIOD_TYPE_WEEKLY",
                      "start": "2026-08-24T00:00:00Z",
                      "end": "2026-08-31T00:00:00Z"
                    },
                    "onDemandCap": {"val": "500"},
                    "onDemandUsed": {"val": 125}
                  }
                }
                """.utf8,
            ),
        )
    }
}

struct StubCredentialLoader: GrokCredentialLoading {
    let credentialsByPath: [String: GrokCredential]

    init(profile: GrokProfileBinding, credential: GrokCredential) {
        credentialsByPath = [profile.grokHome.path: credential]
    }

    init(credentialsByPath: [String: GrokCredential]) {
        self.credentialsByPath = credentialsByPath
    }

    func load(for profile: GrokProfileBinding) throws -> GrokCredential {
        guard let credential = credentialsByPath[profile.grokHome.path] else {
            throw GrokSpikeError.signedOut
        }
        return credential
    }
}

actor StubTransport: GrokHTTPTransport {
    typealias Handler = @Sendable (URLRequest) throws -> GrokHTTPResponse

    private let handler: Handler
    private var recordedRequests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest) throws -> GrokHTTPResponse {
        recordedRequests.append(request)
        return try handler(request)
    }

    func requests() -> [URLRequest] {
        recordedRequests
    }
}

extension URLRequest {
    var bearerToken: String? {
        value(forHTTPHeaderField: "Authorization")?
            .replacingOccurrences(of: "Bearer ", with: "")
    }
}

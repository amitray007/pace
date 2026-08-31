import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
@testable import ClaudeUsageSpikeCore

enum ClaudeSpikeTestSupport {
    static let referenceDate = Date(timeIntervalSince1970: 1_788_134_400)

    static func profile(
        _ name: String = "default",
        expectedIdentity: ClaudeIdentity? = nil,
    ) -> ClaudeProfileBinding {
        ClaudeProfileBinding(
            configDirectory: URL(filePath: "/profiles/\(name)", directoryHint: .isDirectory),
            expectedIdentity: expectedIdentity,
        )
    }

    static func credential(
        accessToken: String = "access",
        scopes: Set<String>? = ["user:profile"],
    ) -> ClaudeCredential {
        ClaudeCredential(
            accessToken: accessToken,
            refreshToken: "refresh-\(accessToken)",
            expiresAt: referenceDate.addingTimeInterval(3600),
            subscriptionType: "max",
            rateLimitTier: "default_claude_max_20x",
            scopes: scopes,
        )
    }

    static func candidate(
        accessToken: String = "access",
        source: ClaudeCredentialSource = .file,
        scopes: Set<String>? = ["user:profile"],
    ) -> ClaudeCredentialCandidate {
        ClaudeCredentialCandidate(
            credential: credential(accessToken: accessToken, scopes: scopes),
            source: source,
        )
    }

    static func profileResponse(
        accountID: String = "account-a",
        organizationID: String = "organization-a",
    ) -> ClaudeHTTPResponse {
        ClaudeHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "account": {
                    "uuid": "\(accountID)",
                    "email": "hidden@example.invalid",
                    "display_name": "Hidden"
                  },
                  "organization": {
                    "uuid": "\(organizationID)",
                    "name": "Hidden organization"
                  }
                }
                """.utf8,
            ),
        )
    }

    static func usageResponse(percent: Double = 25) -> ClaudeHTTPResponse {
        ClaudeHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "five_hour": {
                    "utilization": \(percent),
                    "resets_at": "2030-01-01T00:00:00Z"
                  }
                }
                """.utf8,
            ),
        )
    }
}

struct StubCredentialLoader: ClaudeCredentialLoading {
    let candidatesByPath: [String: [ClaudeCredentialCandidate]]

    init(
        profile: ClaudeProfileBinding,
        candidates: [ClaudeCredentialCandidate],
    ) {
        candidatesByPath = [profile.configDirectory.path: candidates]
    }

    init(candidatesByPath: [String: [ClaudeCredentialCandidate]]) {
        self.candidatesByPath = candidatesByPath
    }

    func load(for profile: ClaudeProfileBinding) -> [ClaudeCredentialCandidate] {
        candidatesByPath[profile.configDirectory.path] ?? []
    }
}

actor StubTransport: ClaudeHTTPTransport {
    typealias Handler = @Sendable (URLRequest) throws -> ClaudeHTTPResponse

    private let handler: Handler
    private var recordedRequests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest) throws -> ClaudeHTTPResponse {
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

import Foundation
import PaceCore
@testable import PaceProviders

enum ClaudeTestSupport {
    static let observedAt = Date(timeIntervalSince1970: 1_788_134_400)

    static func profile(
        _ name: String = "personal",
        expectedIdentity: ProviderIdentity? = nil,
    ) -> ClaudeProfile {
        ClaudeProfile(
            directory: URL(filePath: "/profiles/claude/\(name)", directoryHint: .isDirectory),
            ownership: name == "work" ? .paceManaged : .existing,
            displayName: name.capitalized,
            expectedIdentity: expectedIdentity,
        )
    }

    static func identity(
        accountID: String = "account-a",
        organizationID: String = "organization-a",
    ) -> ClaudeIdentity {
        ClaudeIdentity(
            accountID: accountID,
            organizationID: organizationID,
            email: "\(accountID)@example.invalid",
            accountName: accountID.capitalized,
            organizationName: organizationID.capitalized,
        )
    }

    static func credential(
        accessToken: String = "access",
        refreshToken: String? = "refresh",
        expiresAt: Date? = observedAt.addingTimeInterval(3600),
        scopes: Set<String>? = ["user:profile"],
    ) -> ClaudeCredential {
        ClaudeCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            subscriptionType: "max",
            rateLimitTier: "default_claude_max_20x",
            scopes: scopes,
        )
    }

    static func candidate(
        _ name: String = "personal",
        accessToken: String = "access",
        refreshToken: String? = "refresh",
        expiresAt: Date? = observedAt.addingTimeInterval(3600),
        scopes: Set<String>? = ["user:profile"],
        location: ClaudeCredentialLocation? = nil,
    ) -> ClaudeCredentialCandidate {
        let credential = credential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scopes: scopes,
        )
        let document = credentialDocument(credential)
        return ClaudeCredentialCandidate(
            credential: credential,
            location: location ??
                .file(URL(filePath: "/profiles/claude/\(name)/.credentials.json")),
            encoding: .json,
            originalDocument: document,
        )
    }

    static func result(
        identity: ClaudeIdentity = identity(),
        metrics: [ClaudeMetric] = weeklyMetrics(),
    ) -> ClaudeUsageResult {
        ClaudeUsageResult(
            identity: identity,
            planName: "Max 20x",
            metrics: metrics,
            observedAt: observedAt,
        )
    }

    static func weeklyMetrics() -> [ClaudeMetric] {
        [
            .percentage(ClaudePercentageMetric(
                id: "current-session",
                label: "Session",
                usedFraction: 0.42,
                windowDuration: 18000,
                resetsAt: observedAt.addingTimeInterval(18000),
            )),
            .percentage(ClaudePercentageMetric(
                id: "weekly-all-models",
                label: "Weekly",
                usedFraction: 0.2,
                windowDuration: 604_800,
                resetsAt: observedAt.addingTimeInterval(604_800),
            )),
        ]
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
                    "email": "\(accountID)@example.invalid",
                    "display_name": "\(accountID)"
                  },
                  "organization": {
                    "uuid": "\(organizationID)",
                    "name": "\(organizationID)"
                  }
                }
                """.utf8,
            ),
        )
    }

    static func usageResponse(percent: Double = 42) -> ClaudeHTTPResponse {
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

    static func refreshResponse(
        accessToken: String = "new-access",
        refreshToken: String = "new-refresh",
    ) -> ClaudeHTTPResponse {
        ClaudeHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "access_token": "\(accessToken)",
                  "refresh_token": "\(refreshToken)",
                  "expires_in": 3600
                }
                """.utf8,
            ),
        )
    }

    static func credentialDocument(_ credential: ClaudeCredential) -> Data {
        let refresh = credential.refreshToken.map { #", "refreshToken": "\#($0)""# } ?? ""
        let expiry = credential.expiresAt.map {
            #", "expiresAt": \#($0.timeIntervalSince1970 * 1000)"#
        } ?? ""
        let scopes = credential.scopes?.sorted().map { #""\#($0)""# }.joined(separator: ",")
            ?? ""
        return Data(
            """
            {
              "preserved": {"value": true},
              "claudeAiOauth": {
                "accessToken": "\(credential.accessToken)"\(refresh)\(expiry),
                "subscriptionType": "max",
                "rateLimitTier": "default_claude_max_20x",
                "scopes": [\(scopes)]
              }
            }
            """.utf8,
        )
    }
}

final class ClaudeStubCredentialStore: ClaudeCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var candidatesByPath: [String: [ClaudeCredentialCandidate]]
    private var savedCandidates: [ClaudeCredentialCandidate] = []
    private let saveError: ClaudeProviderError?

    init(
        candidatesByPath: [String: [ClaudeCredentialCandidate]],
        saveError: ClaudeProviderError? = nil,
    ) {
        self.candidatesByPath = candidatesByPath
        self.saveError = saveError
    }

    convenience init(
        profile: ClaudeProfile,
        candidates: [ClaudeCredentialCandidate],
        saveError: ClaudeProviderError? = nil,
    ) {
        self.init(
            candidatesByPath: [profile.directory.path: candidates],
            saveError: saveError,
        )
    }

    func load(
        for profile: ClaudeProfile,
    ) throws(ClaudeProviderError) -> [ClaudeCredentialCandidate] {
        lock.withLock { candidatesByPath[profile.directory.path] ?? [] }
    }

    func save(
        _ candidate: ClaudeCredentialCandidate,
        ifUnchanged generation: ClaudeCredentialGeneration,
        for profile: ClaudeProfile,
    ) throws(ClaudeProviderError) -> ClaudeCredentialGeneration {
        let result: Result<ClaudeCredentialGeneration, ClaudeProviderError> = lock.withLock {
            if let saveError {
                return .failure(saveError)
            }
            var current = candidatesByPath[profile.directory.path] ?? []
            guard ClaudeCredentialGeneration(current) == generation,
                  let index = current.firstIndex(where: { $0.location == candidate.location })
            else {
                return .failure(.credentialChanged)
            }
            current[index] = candidate
            candidatesByPath[profile.directory.path] = current
            savedCandidates.append(candidate)
            return .success(ClaudeCredentialGeneration(current))
        }
        return try result.get()
    }

    func replace(profile: ClaudeProfile, with candidates: [ClaudeCredentialCandidate]) {
        lock.withLock { candidatesByPath[profile.directory.path] = candidates }
    }

    var saves: [ClaudeCredentialCandidate] {
        lock.withLock { savedCandidates }
    }
}

actor ClaudeStubTransport: ClaudeHTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> ClaudeHTTPResponse

    private let handler: Handler
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> ClaudeHTTPResponse {
        requests.append(request)
        return try await handler(request)
    }
}

struct ClaudeNoopOAuthRefreshLock: ClaudeOAuthRefreshLocking {
    func acquire(
        for _: ClaudeProfile,
    ) async throws(ClaudeProviderError) -> ClaudeOAuthRefreshLockLease {
        ClaudeOAuthRefreshLockLease()
    }
}

actor ClaudeStubReader: ClaudeUsageReading {
    private let results: [String: Result<ClaudeUsageResult, ClaudeProviderError>]
    private(set) var reads: [(profile: ClaudeProfile, includeUsage: Bool)] = []

    init(results: [String: Result<ClaudeUsageResult, ClaudeProviderError>]) {
        self.results = results
    }

    func read(
        profile: ClaudeProfile,
        includeUsage: Bool,
    ) throws(ClaudeProviderError) -> ClaudeUsageResult {
        reads.append((profile, includeUsage))
        guard let result = results[profile.directory.path] else {
            throw .invalidResponse
        }
        return try result.get()
    }
}

extension URLRequest {
    var claudeBearerToken: String? {
        value(forHTTPHeaderField: "Authorization")?
            .replacingOccurrences(of: "Bearer ", with: "")
    }
}

import Foundation
import PaceCore
@testable import PaceProviders

enum CursorTestSupport {
    static let observedAt = Date(timeIntervalSince1970: 1_788_134_400)

    static func profile(
        _ name: String = "personal",
        source: CursorCredentialSource = .isolatedFile,
        expectedIdentity: ProviderIdentity? = nil,
    ) -> CursorProfile {
        CursorProfile(
            homeDirectory: URL(filePath: "/profiles/cursor/\(name)", directoryHint: .isDirectory),
            credentialSource: source,
            ownership: name == "work" ? .paceManaged : .existing,
            displayName: name.capitalized,
            expectedIdentity: expectedIdentity,
        )
    }

    static func identity(
        userID: String = "user-a",
        teamID: String? = "team-a",
    ) -> CursorIdentity {
        CursorIdentity(
            userID: userID,
            teamID: teamID,
            email: "\(userID)@example.invalid",
            displayName: userID.capitalized,
        )
    }

    static func credential(
        authenticationID: String = "auth0|user-a",
        accessToken: String? = nil,
        refreshToken: String? = "refresh-a",
        expiresAt: Date = observedAt.addingTimeInterval(3600),
        source: CursorCredentialSource = .isolatedFile,
    ) -> CursorCredential {
        CursorCredential(
            accessToken: accessToken ?? token(subject: authenticationID, expiresAt: expiresAt),
            refreshToken: refreshToken,
            authenticationID: authenticationID,
            source: source,
        )
    }

    static func result(
        identity: CursorIdentity = identity(),
        metrics: [CursorMetric] = usageMetrics(),
    ) -> CursorUsageResult {
        CursorUsageResult(
            identity: identity,
            planName: "Team",
            metrics: metrics,
            observedAt: observedAt,
        )
    }

    static func usageMetrics() -> [CursorMetric] {
        [
            .percentage(CursorPercentageMetric(
                id: "total",
                label: "Total Usage",
                usedFraction: 0.42,
                resetsAt: observedAt.addingTimeInterval(604_800),
                windowDuration: 604_800,
            )),
            .percentage(CursorPercentageMetric(
                id: "cursor-models",
                label: "Cursor Models",
                usedFraction: 0.2,
                resetsAt: observedAt.addingTimeInterval(604_800),
                windowDuration: 604_800,
            )),
        ]
    }

    static func identityResponse(
        userID: String = "user-a",
        teamID: String? = "team-a",
        authenticationID: String = "auth0|user-a",
    ) -> CursorHTTPResponse {
        let team = teamID.map { #", "teamId": "\#($0)""# } ?? ""
        return CursorHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "authId": "\(authenticationID)",
                  "userId": "\(userID)",
                  "email": "\(userID)@example.invalid",
                  "firstName": "\(userID)"\(team)
                }
                """.utf8,
            ),
        )
    }

    static func usageResponse(totalPercent: Double = 42) -> CursorHTTPResponse {
        CursorHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "enabled": true,
                  "billingCycleStart": 1788134400000,
                  "billingCycleEnd": 1788739200000,
                  "planUsage": {
                    "totalPercentUsed": \(totalPercent),
                    "autoPercentUsed": 20,
                    "apiPercentUsed": 22
                  }
                }
                """.utf8,
            ),
        )
    }

    static func planResponse(_ plan: String = "team") -> CursorHTTPResponse {
        CursorHTTPResponse(
            statusCode: 200,
            body: Data(#"{"planInfo":{"planName":"\#(plan)"}}"#.utf8),
        )
    }

    static func refreshResponse(
        authenticationID: String = "auth0|user-a",
        expiresAt: Date = observedAt.addingTimeInterval(7200),
    ) -> CursorHTTPResponse {
        let accessToken = token(subject: authenticationID, expiresAt: expiresAt)
        return CursorHTTPResponse(
            statusCode: 200,
            body: Data(#"{"access_token":"\#(accessToken)"}"#.utf8),
        )
    }

    static func token(subject: String, expiresAt: Date) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncodedString()
        let payload = Data(
            #"{"sub":"\#(subject)","exp":\#(Int(expiresAt.timeIntervalSince1970))}"#.utf8,
        ).base64URLEncodedString()
        return "\(header).\(payload).signature"
    }
}

final class CursorStubCredentialLoader: CursorCredentialLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var resultsByPath: [String: [Result<CursorCredential, CursorProviderError>]]
    private var loadCounts: [String: Int] = [:]

    init(resultsByPath: [String: [Result<CursorCredential, CursorProviderError>]]) {
        self.resultsByPath = resultsByPath
    }

    convenience init(profile: CursorProfile, credential: CursorCredential) {
        self.init(resultsByPath: [profile.homeDirectory.path: [.success(credential)]])
    }

    func load(for profile: CursorProfile) throws(CursorProviderError) -> CursorCredential {
        let result: Result<CursorCredential, CursorProviderError> = lock.withLock {
            let path = profile.homeDirectory.path
            let values = resultsByPath[path] ?? [.failure(.signedOut)]
            let index = min(loadCounts[path, default: 0], values.count - 1)
            loadCounts[path, default: 0] += 1
            return values[index]
        }
        return try result.get()
    }
}

actor CursorStubTransport: CursorHTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws -> CursorHTTPResponse

    private let handler: Handler
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> CursorHTTPResponse {
        requests.append(request)
        return try await handler(request)
    }
}

actor CursorStubReader: CursorUsageReading {
    private let results: [String: Result<CursorUsageResult, CursorProviderError>]
    private(set) var reads: [(profile: CursorProfile, includeUsage: Bool)] = []

    init(results: [String: Result<CursorUsageResult, CursorProviderError>]) {
        self.results = results
    }

    func read(
        profile: CursorProfile,
        includeUsage: Bool,
    ) throws(CursorProviderError) -> CursorUsageResult {
        reads.append((profile, includeUsage))
        guard let result = results[profile.homeDirectory.path] else {
            throw .invalidResponse
        }
        return try result.get()
    }
}

struct CursorStubKeychain: CursorKeychainReading {
    let records: [String: Result<CursorKeychainRecord?, CursorProviderError>]

    func readGenericPassword(
        service: String,
        account _: String,
    ) throws(CursorProviderError) -> CursorKeychainRecord? {
        try records[service, default: .success(nil)].get()
    }
}

extension URLRequest {
    var cursorBearerToken: String? {
        value(forHTTPHeaderField: "Authorization")?
            .replacingOccurrences(of: "Bearer ", with: "")
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

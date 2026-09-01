import Foundation
import PaceCore
@testable import PaceProviders

enum GitHubCopilotTestSupport {
    static let observedAt = Date(timeIntervalSince1970: 1_788_134_400)

    static func profile(
        _ login: String = "personal",
        expectedIdentity: ProviderIdentity? = nil,
        configurationDirectory: URL? = nil,
    ) -> GitHubCopilotProfile {
        GitHubCopilotProfile(
            githubLogin: login,
            configurationDirectory: configurationDirectory,
            displayName: login.capitalized,
            expectedIdentity: expectedIdentity,
        )
    }

    static func identity(
        userID: Int64 = 101,
        login: String = "personal",
    ) -> GitHubCopilotIdentity {
        GitHubCopilotIdentity(userID: userID, login: login, displayName: login.capitalized)
    }

    static func result(
        identity: GitHubCopilotIdentity = identity(),
        metrics: [GitHubCopilotMetric] = [
            .percentage(GitHubCopilotPercentageMetric(
                id: "credits",
                label: "Credits",
                usedFraction: 0.42,
                resetsAt: observedAt.addingTimeInterval(2_592_000),
                windowDuration: 2_592_000,
            )),
        ],
        isOrganizationManaged: Bool = false,
    ) -> GitHubCopilotUsageResult {
        GitHubCopilotUsageResult(
            identity: identity,
            planName: "Individual",
            metrics: metrics,
            isOrganizationManaged: isOrganizationManaged,
            observedAt: observedAt,
        )
    }

    static func account(
        profile: GitHubCopilotProfile = profile(),
        identity: GitHubCopilotIdentity = identity(),
    ) -> ProviderAccount {
        ProviderAccount(
            id: AccountID(),
            providerID: .githubCopilot,
            identity: identity.providerIdentity,
            credentialBinding: profile.credentialBinding,
            addedAt: observedAt,
            displayName: profile.displayName ?? profile.githubLogin,
            planName: nil,
            isEnabled: true,
            order: 0,
            connectionState: .needsAuthentication,
        )
    }

    static func identityResponse(
        userID: Int64 = 101,
        login: String = "personal",
    ) -> GitHubCopilotHTTPResponse {
        GitHubCopilotHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {"id":\(userID),"login":"\(login)","name":"Personal"}
                """.utf8,
            ),
        )
    }

    static func usageResponse() -> GitHubCopilotHTTPResponse {
        GitHubCopilotHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "copilot_plan": "individual",
                  "quota_reset_date_utc": "2026-10-01T00:00:00Z",
                  "quota_snapshots": {
                    "premium_interactions": {
                      "entitlement": 300,
                      "remaining": 174,
                      "percent_remaining": 58,
                      "unlimited": false,
                      "overage_permitted": false
                    }
                  }
                }
                """.utf8,
            ),
        )
    }
}

actor GitHubCopilotStubReader: GitHubCopilotUsageReading {
    private let results: [String: Result<GitHubCopilotUsageResult, GitHubCopilotProviderError>]
    private(set) var reads: [(GitHubCopilotProfile, Bool)] = []

    init(
        results: [String: Result<GitHubCopilotUsageResult, GitHubCopilotProviderError>],
    ) {
        self.results = results
    }

    func read(
        profile: GitHubCopilotProfile,
        includeUsage: Bool,
    ) throws -> GitHubCopilotUsageResult {
        reads.append((profile, includeUsage))
        guard let result = results[profile.githubLogin.lowercased()] else {
            throw GitHubCopilotProviderError.invalidResponse
        }
        return try result.get()
    }
}

struct GitHubCopilotStubCredentialLoader: GitHubCopilotCredentialLoading {
    let token: String

    func load(for _: GitHubCopilotProfile) -> GitHubCopilotCredential {
        GitHubCopilotCredential(token: token)
    }
}

actor GitHubCopilotStubTransport: GitHubCopilotHTTPTransport {
    typealias Handler = @Sendable (URLRequest) throws -> GitHubCopilotHTTPResponse

    private let handler: Handler
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest) throws -> GitHubCopilotHTTPResponse {
        requests.append(request)
        return try handler(request)
    }
}

actor GitHubCLIStubExecutor: GitHubCLIExecuting {
    struct Invocation: Sendable {
        let arguments: [String]
        let environment: [String: String]
    }

    private let result: Result<GitHubCLIOutput, GitHubCopilotProviderError>
    private(set) var invocations: [Invocation] = []

    init(result: Result<GitHubCLIOutput, GitHubCopilotProviderError>) {
        self.result = result
    }

    func run(
        arguments: [String],
        environment: [String: String],
    ) throws -> GitHubCLIOutput {
        invocations.append(Invocation(arguments: arguments, environment: environment))
        return try result.get()
    }
}

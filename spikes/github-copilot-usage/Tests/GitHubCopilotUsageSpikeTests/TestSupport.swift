import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
@testable import GitHubCopilotUsageSpikeCore

enum GitHubCopilotTestSupport {
    typealias HTTPResponse = GitHubCopilotHTTPResponse

    static let referenceDate = Date(timeIntervalSince1970: 1_788_134_400)

    static func profile(
        login: String = "octocat",
        expectedIdentity: GitHubIdentity? = nil,
    ) -> GitHubCopilotProfileBinding {
        GitHubCopilotProfileBinding(
            githubLogin: login,
            expectedIdentity: expectedIdentity,
        )
    }

    static func identity(
        id: Int64 = 42,
        login: String = "octocat",
    ) -> GitHubIdentity {
        GitHubIdentity(userID: id, login: login)
    }

    static func identityResponse(id: Int64 = 42, login: String = "octocat") -> HTTPResponse {
        GitHubCopilotHTTPResponse(
            statusCode: 200,
            body: Data(#"{"id":\#(id),"login":"\#(login)","name":"Hidden"}"#.utf8),
        )
    }

    static func usageResponse() -> GitHubCopilotHTTPResponse {
        GitHubCopilotHTTPResponse(
            statusCode: 200,
            body: Data(
                """
                {
                  "copilot_plan": "pro",
                  "quota_reset_date": "2026-09-01T00:00:00Z",
                  "quota_snapshots": {
                    "premium_interactions": {
                      "entitlement": 300,
                      "remaining": 120,
                      "percent_remaining": 40,
                      "overage_permitted": true,
                      "overage_count": 2
                    },
                    "chat": {"entitlement": -1, "remaining": -1, "unlimited": true},
                    "completions": {"entitlement": -1, "remaining": -1}
                  }
                }
                """.utf8,
            ),
        )
    }
}

struct StubCredentialLoader: GitHubCopilotCredentialLoading {
    let credentialsByLogin: [String: GitHubCopilotCredential]

    init(profile: GitHubCopilotProfileBinding, token: String = "redacted-token") {
        credentialsByLogin = [profile.githubLogin: GitHubCopilotCredential(token: token)]
    }

    init(credentialsByLogin: [String: GitHubCopilotCredential]) {
        self.credentialsByLogin = credentialsByLogin
    }

    func load(for profile: GitHubCopilotProfileBinding) throws -> GitHubCopilotCredential {
        guard let credential = credentialsByLogin[profile.githubLogin] else {
            throw GitHubCopilotSpikeError.signedOut
        }
        return credential
    }
}

actor StubHTTPTransport: GitHubCopilotHTTPTransport {
    typealias Handler = @Sendable (URLRequest) throws -> GitHubCopilotHTTPResponse

    private let handler: Handler
    private var recordedRequests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest) throws -> GitHubCopilotHTTPResponse {
        recordedRequests.append(request)
        return try handler(request)
    }

    func requests() -> [URLRequest] {
        recordedRequests
    }
}

final class StubGitHubCLIExecutor: GitHubCLIExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private let output: GitHubCLIOutput
    private var recordedArguments: [[String]] = []
    private var recordedEnvironments: [[String: String]] = []

    init(status: Int32 = 0, stdout: String) {
        output = GitHubCLIOutput(status: status, stdout: Data(stdout.utf8))
    }

    func run(arguments: [String], environment: [String: String]) -> GitHubCLIOutput {
        lock.withLock {
            recordedArguments.append(arguments)
            recordedEnvironments.append(environment)
        }
        return output
    }

    func invocations() -> (arguments: [[String]], environments: [[String: String]]) {
        lock.withLock {
            (recordedArguments, recordedEnvironments)
        }
    }
}

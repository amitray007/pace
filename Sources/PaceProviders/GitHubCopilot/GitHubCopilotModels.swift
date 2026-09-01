import Foundation
import PaceCore

public struct GitHubCopilotProfile: Equatable, Sendable {
    public static let credentialTool = "github-cli:github.com"

    public let githubLogin: String
    public let configurationDirectory: URL?
    public let displayName: String?
    public let expectedIdentity: ProviderIdentity?

    public init(
        githubLogin: String,
        configurationDirectory: URL? = nil,
        displayName: String? = nil,
        expectedIdentity: ProviderIdentity? = nil,
    ) {
        self.githubLogin = githubLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configurationDirectory = configurationDirectory?
            .standardizedFileURL
            .resolvingSymlinksInPath()
        self.displayName = displayName
        self.expectedIdentity = expectedIdentity
    }

    var credentialBinding: CredentialBinding {
        .commandLineAccount(
            tool: Self.credentialTool,
            account: githubLogin.lowercased(),
            configurationDirectory: configurationDirectory,
        )
    }

    func expecting(_ identity: ProviderIdentity) -> Self {
        Self(
            githubLogin: githubLogin,
            configurationDirectory: configurationDirectory,
            displayName: displayName,
            expectedIdentity: identity,
        )
    }
}

struct GitHubCopilotIdentity: Equatable, Hashable, Sendable {
    let userID: Int64
    let login: String
    let displayName: String?

    var providerIdentity: ProviderIdentity {
        ProviderIdentity(subjectID: "github:\(userID)")
    }
}

struct GitHubCopilotCredential: Equatable, Sendable {
    let token: String
}

struct GitHubCopilotPercentageMetric: Equatable, Sendable {
    let id: String
    let label: String
    let usedFraction: Double
    let resetsAt: Date?
    let windowDuration: TimeInterval?
}

struct GitHubCopilotAmountMetric: Equatable, Sendable {
    let id: String
    let label: String
    let used: Decimal
    let limit: Decimal?
    let unit: String
    let resetsAt: Date?
}

enum GitHubCopilotMetric: Equatable, Sendable {
    case amount(GitHubCopilotAmountMetric)
    case percentage(GitHubCopilotPercentageMetric)
}

struct GitHubCopilotUsageResult: Equatable, Sendable {
    let identity: GitHubCopilotIdentity
    let planName: String?
    let metrics: [GitHubCopilotMetric]
    let isOrganizationManaged: Bool
    let observedAt: Date
}

enum GitHubCopilotProviderError: Error, Equatable, Sendable {
    case cliFailed
    case cliUnavailable
    case identityMismatch
    case invalidCredential
    case invalidProfile
    case invalidResponse
    case quotaUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    case reauthenticationRequired
    case requestFailed(statusCode: Int)
    case signedOut
    case transportFailed
}

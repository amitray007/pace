import Foundation
import PaceCore

public struct GrokProfile: Equatable, Sendable {
    public let directory: URL
    public let ownership: ProfileOwnership
    public let displayName: String?
    public let expectedIdentity: ProviderIdentity?

    public init(
        directory: URL,
        ownership: ProfileOwnership,
        displayName: String? = nil,
        expectedIdentity: ProviderIdentity? = nil,
    ) {
        self.directory = directory.standardizedFileURL
        self.ownership = ownership
        self.displayName = displayName
        self.expectedIdentity = expectedIdentity
    }

    func expecting(_ identity: ProviderIdentity) -> Self {
        Self(
            directory: directory,
            ownership: ownership,
            displayName: displayName,
            expectedIdentity: identity,
        )
    }
}

struct GrokIdentity: Equatable, Hashable, Sendable {
    let userID: String
    let principalID: String?
    let teamID: String?
    let email: String?
    let displayName: String?

    var stableKey: String {
        "\(userID.lowercased())|\(principalID?.lowercased() ?? "no-principal")|"
            + "\(teamID?.lowercased() ?? "personal")"
    }

    var providerIdentity: ProviderIdentity {
        ProviderIdentity(
            subjectID: "grok:\(stableKey)",
            email: email,
            organizationID: teamID,
        )
    }
}

struct GrokCredential: Equatable, Sendable {
    let accessToken: String
    let expiresAt: Date?
}

struct GrokPercentageMetric: Equatable, Sendable {
    let id: String
    let label: String
    let usedFraction: Double
    let resetsAt: Date?
    let windowDuration: TimeInterval?
}

struct GrokAmountMetric: Equatable, Sendable {
    let id: String
    let label: String
    let used: Decimal
    let limit: Decimal?
    let resetsAt: Date?
}

enum GrokMetric: Equatable, Sendable {
    case amount(GrokAmountMetric)
    case percentage(GrokPercentageMetric)
}

struct GrokUsageResult: Equatable, Sendable {
    let identity: GrokIdentity
    let planName: String?
    let metrics: [GrokMetric]
    let observedAt: Date
}

enum GrokProviderError: Error, Equatable, Sendable {
    case ambiguousCredential
    case credentialReadFailed
    case identityMismatch
    case insecureCredentialFile
    case invalidCredential
    case invalidResponse
    case rateLimited(retryAfter: TimeInterval?)
    case reauthenticationRequired
    case requestFailed(statusCode: Int)
    case signedOut
    case transportFailed
    case unsupportedCredential
}

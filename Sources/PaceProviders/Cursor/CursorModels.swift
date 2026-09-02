import Foundation
import PaceCore

public struct CursorProfile: Equatable, Sendable {
    public let homeDirectory: URL
    public let credentialSource: CursorCredentialSource
    public let ownership: ProfileOwnership
    public let displayName: String?
    public let expectedIdentity: ProviderIdentity?

    public init(
        homeDirectory: URL,
        credentialSource: CursorCredentialSource,
        ownership: ProfileOwnership,
        displayName: String? = nil,
        expectedIdentity: ProviderIdentity? = nil,
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.credentialSource = credentialSource
        self.ownership = ownership
        self.displayName = displayName
        self.expectedIdentity = expectedIdentity
    }

    public static func current(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        ownership: ProfileOwnership = .existing,
    ) -> Self {
        Self(
            homeDirectory: homeDirectory,
            credentialSource: .defaultKeychain,
            ownership: ownership,
        )
    }

    public static func isolated(
        homeDirectory: URL,
        ownership: ProfileOwnership = .existing,
        displayName: String? = nil,
        expectedIdentity: ProviderIdentity? = nil,
    ) -> Self {
        Self(
            homeDirectory: homeDirectory,
            credentialSource: .isolatedFile,
            ownership: ownership,
            displayName: displayName,
            expectedIdentity: expectedIdentity,
        )
    }

    var cursorDirectory: URL {
        homeDirectory.appending(path: ".cursor", directoryHint: .isDirectory)
    }

    var credentialFile: URL {
        cursorDirectory.appending(path: "auth.json", directoryHint: .notDirectory)
    }

    var configurationFile: URL {
        cursorDirectory.appending(path: "cli-config.json", directoryHint: .notDirectory)
    }

    var credentialBinding: CredentialBinding {
        .cursorProfile(CursorCredentialBinding(
            homeDirectory: homeDirectory,
            credentialSource: credentialSource,
            ownership: ownership,
        ))
    }

    func expecting(_ identity: ProviderIdentity) -> Self {
        Self(
            homeDirectory: homeDirectory,
            credentialSource: credentialSource,
            ownership: ownership,
            displayName: displayName,
            expectedIdentity: identity,
        )
    }
}

struct CursorCredential: Equatable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let authenticationID: String
    let source: CursorCredentialSource
}

struct CursorIdentity: Equatable, Sendable {
    let userID: String
    let teamID: String?
    let email: String?
    let displayName: String?

    var providerIdentity: ProviderIdentity {
        ProviderIdentity(subjectID: userID, email: email, organizationID: teamID)
    }
}

struct CursorPercentageMetric: Equatable, Sendable {
    let id: String
    let label: String
    let usedFraction: Double
    let resetsAt: Date?
    let windowDuration: TimeInterval?
}

struct CursorAmountMetric: Equatable, Sendable {
    let id: String
    let label: String
    let used: Decimal
    let limit: Decimal?
    let unit: String
    let resetsAt: Date?
}

enum CursorMetric: Equatable, Sendable {
    case amount(CursorAmountMetric)
    case percentage(CursorPercentageMetric)
}

struct CursorUsageResult: Equatable, Sendable {
    let identity: CursorIdentity
    let planName: String?
    let metrics: [CursorMetric]
    let observedAt: Date
}

enum CursorProviderError: Error, Equatable, Sendable {
    case cancelled
    /// macOS would not release a keychain item without asking the user, and
    /// asking was not allowed. The credential exists and is intact; a read
    /// under `KeychainInteractionPolicy.allowingPrompts` resolves it.
    case credentialAccessDenied
    case credentialChanged
    case credentialReadFailed
    case identityMismatch
    case insecureCredentialFile
    case invalidCredential
    case invalidProfile
    case invalidResponse
    case rateLimited(retryAfter: TimeInterval?)
    case reauthenticationRequired
    case requestFailed(statusCode: Int)
    case signedOut
    case transportFailed
}

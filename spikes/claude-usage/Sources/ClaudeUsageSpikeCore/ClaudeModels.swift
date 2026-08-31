import Foundation

public struct ClaudeIdentity: Equatable, Hashable, Sendable {
    public let accountID: String
    public let organizationID: String
    public let email: String?
    public let accountName: String?
    public let organizationName: String?

    public init(
        accountID: String,
        organizationID: String,
        email: String? = nil,
        accountName: String? = nil,
        organizationName: String? = nil,
    ) {
        self.accountID = accountID
        self.organizationID = organizationID
        self.email = email
        self.accountName = accountName
        self.organizationName = organizationName
    }

    public var stableKey: String {
        "\(accountID.lowercased())|\(organizationID.lowercased())"
    }
}

public struct ClaudeProfileBinding: Equatable, Hashable, Sendable {
    public let configDirectory: URL
    public let expectedIdentity: ClaudeIdentity?

    public init(configDirectory: URL, expectedIdentity: ClaudeIdentity? = nil) {
        self.configDirectory = configDirectory.standardizedFileURL
        self.expectedIdentity = expectedIdentity
    }

    public static var defaultProfile: Self {
        Self(
            configDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".claude", directoryHint: .isDirectory),
        )
    }
}

public enum ClaudeCredentialSource: Equatable, Hashable, Sendable {
    case file
    case keychain

    public var label: String {
        switch self {
        case .file:
            "file"
        case .keychain:
            "keychain"
        }
    }
}

public struct ClaudeCredential: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let subscriptionType: String?
    let rateLimitTier: String?
    let scopes: Set<String>?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        subscriptionType: String? = nil,
        rateLimitTier: String? = nil,
        scopes: Set<String>? = nil,
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
        self.scopes = scopes
    }

    var canReadUsage: Bool {
        guard let scopes, !scopes.isEmpty else {
            return true
        }
        return scopes.contains("user:profile")
    }
}

public struct ClaudeCredentialCandidate: Equatable, Sendable {
    public let credential: ClaudeCredential
    public let source: ClaudeCredentialSource

    public init(credential: ClaudeCredential, source: ClaudeCredentialSource) {
        self.credential = credential
        self.source = source
    }
}

public struct ClaudePercentageMetric: Equatable, Sendable {
    public let id: String
    public let label: String
    public let usedFraction: Double
    public let windowDuration: TimeInterval?
    public let resetsAt: Date?

    public init(
        id: String,
        label: String,
        usedFraction: Double,
        windowDuration: TimeInterval?,
        resetsAt: Date?,
    ) {
        self.id = id
        self.label = label
        self.usedFraction = usedFraction
        self.windowDuration = windowDuration
        self.resetsAt = resetsAt
    }
}

public enum ClaudeAmountSemantic: String, Equatable, Sendable {
    case remaining
    case used
}

public struct ClaudeAmountMetric: Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: Decimal
    public let limit: Decimal?
    public let unit: String
    public let semantic: ClaudeAmountSemantic

    public init(
        id: String,
        label: String,
        value: Decimal,
        limit: Decimal?,
        unit: String,
        semantic: ClaudeAmountSemantic,
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.limit = limit
        self.unit = unit
        self.semantic = semantic
    }
}

public enum ClaudeMetric: Equatable, Sendable {
    case amount(ClaudeAmountMetric)
    case percentage(ClaudePercentageMetric)
}

public struct ClaudeProbeResult: Equatable, Sendable {
    public let identity: ClaudeIdentity
    public let planName: String?
    public let metrics: [ClaudeMetric]
    public let observedAt: Date
    public let credentialSource: ClaudeCredentialSource

    public init(
        identity: ClaudeIdentity,
        planName: String?,
        metrics: [ClaudeMetric],
        observedAt: Date,
        credentialSource: ClaudeCredentialSource,
    ) {
        self.identity = identity
        self.planName = planName
        self.metrics = metrics
        self.observedAt = observedAt
        self.credentialSource = credentialSource
    }
}

public enum ClaudeSpikeError: Error, Equatable, Sendable {
    case credentialReadFailed
    case duplicateIdentity
    case identityMismatch
    case invalidCredential
    case invalidResponse
    case missingProfileScope
    case rateLimited(retryAfter: TimeInterval?)
    case requestFailed(statusCode: Int)
    case signedOut
    case transportFailed
}

extension ClaudeSpikeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .credentialReadFailed:
            "Claude credentials could not be read without interaction."
        case .duplicateIdentity:
            "Two profile directories resolved to the same Claude identity."
        case .identityMismatch:
            "The Claude profile no longer matches its registered identity."
        case .invalidCredential:
            "The Claude credential is malformed."
        case .invalidResponse:
            "Claude returned an invalid response."
        case .missingProfileScope:
            "The Claude login cannot read usage because it lacks user:profile access."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "Claude rate-limited the usage request. Retry after \(Int(retryAfter)) seconds."
            } else {
                "Claude rate-limited the usage request."
            }
        case let .requestFailed(statusCode):
            "Claude returned HTTP \(statusCode)."
        case .signedOut:
            "No Claude login exists for this profile directory."
        case .transportFailed:
            "The Claude request failed before a response arrived."
        }
    }
}

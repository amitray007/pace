import Foundation

public struct GrokIdentity: Equatable, Hashable, Sendable {
    public let userID: String
    public let principalID: String?
    public let teamID: String?
    public let email: String?
    public let displayName: String?

    public init(
        userID: String,
        principalID: String? = nil,
        teamID: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
    ) {
        self.userID = userID
        self.principalID = principalID
        self.teamID = teamID
        self.email = email
        self.displayName = displayName
    }

    public var stableKey: String {
        "\(userID.lowercased())|\(principalID?.lowercased() ?? "no-principal")|"
            + "\(teamID?.lowercased() ?? "personal")"
    }
}

public struct GrokProfileBinding: Equatable, Hashable, Sendable {
    public let grokHome: URL
    public let expectedIdentity: GrokIdentity?

    public init(grokHome: URL, expectedIdentity: GrokIdentity? = nil) {
        self.grokHome = grokHome.standardizedFileURL
        self.expectedIdentity = expectedIdentity
    }

    public static var defaultProfile: Self {
        Self(
            grokHome: FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".grok", directoryHint: .isDirectory),
        )
    }

    public var credentialFile: URL {
        grokHome.appending(path: "auth.json", directoryHint: .notDirectory)
    }

    public func processEnvironment(inheriting base: [String: String]) -> [String: String] {
        var environment = base
        environment["GROK_HOME"] = grokHome.path
        return environment
    }
}

public struct GrokCredential: Equatable, Sendable {
    let accessToken: String
    let localIdentity: GrokIdentity
    public let expiresAt: Date?

    public init(accessToken: String, localIdentity: GrokIdentity, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.localIdentity = localIdentity
        self.expiresAt = expiresAt
    }
}

public struct GrokPercentageMetric: Equatable, Sendable {
    public let id: String
    public let label: String
    public let usedFraction: Double
    public let resetsAt: Date?
    public let windowDuration: TimeInterval?

    public init(
        id: String,
        label: String,
        usedFraction: Double,
        resetsAt: Date?,
        windowDuration: TimeInterval?,
    ) {
        self.id = id
        self.label = label
        self.usedFraction = usedFraction
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
    }
}

public struct GrokAmountMetric: Equatable, Sendable {
    public let id: String
    public let label: String
    public let used: Decimal
    public let limit: Decimal?
    public let unit: String
    public let resetsAt: Date?

    public init(
        id: String,
        label: String,
        used: Decimal,
        limit: Decimal?,
        unit: String,
        resetsAt: Date?,
    ) {
        self.id = id
        self.label = label
        self.used = used
        self.limit = limit
        self.unit = unit
        self.resetsAt = resetsAt
    }
}

public enum GrokMetric: Equatable, Sendable {
    case amount(GrokAmountMetric)
    case percentage(GrokPercentageMetric)
}

public struct GrokProbeResult: Equatable, Sendable {
    public let identity: GrokIdentity
    public let planName: String?
    public let metrics: [GrokMetric]
    public let observedAt: Date

    public init(
        identity: GrokIdentity,
        planName: String?,
        metrics: [GrokMetric],
        observedAt: Date,
    ) {
        self.identity = identity
        self.planName = planName
        self.metrics = metrics
        self.observedAt = observedAt
    }
}

public enum GrokSpikeError: Error, Equatable, Sendable {
    case ambiguousCredential
    case credentialReadFailed
    case duplicateIdentity
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

extension GrokSpikeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .ambiguousCredential:
            "The Grok profile contains more than one usable session credential."
        case .credentialReadFailed:
            "The selected Grok credential file could not be read."
        case .duplicateIdentity:
            "Two Grok profiles resolved to the same account."
        case .identityMismatch:
            "The Grok profile no longer matches its registered identity."
        case .insecureCredentialFile:
            "The Grok credential file is not private to the current user."
        case .invalidCredential:
            "The selected Grok session credential is malformed or expired."
        case .invalidResponse:
            "Grok returned an invalid usage response."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "Grok rate-limited the request. Retry after \(Int(retryAfter)) seconds."
            } else {
                "Grok rate-limited the request."
            }
        case .reauthenticationRequired:
            "The Grok session is no longer accepted. Run grok login for this profile."
        case let .requestFailed(statusCode):
            "Grok returned HTTP \(statusCode)."
        case .signedOut:
            "No Grok session login exists for this profile."
        case .transportFailed:
            "The Grok request failed before a response arrived."
        case .unsupportedCredential:
            "Pace requires a first-party Grok session; API keys and custom OIDC issuers are not "
                + "sent to xAI's subscription endpoint."
        }
    }
}

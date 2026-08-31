import Foundation

public struct GitHubIdentity: Equatable, Hashable, Sendable {
    public let userID: Int64
    public let login: String
    public let displayName: String?

    public init(userID: Int64, login: String, displayName: String? = nil) {
        self.userID = userID
        self.login = login
        self.displayName = displayName
    }

    public var stableKey: String {
        String(userID)
    }
}

public struct GitHubCopilotProfileBinding: Equatable, Hashable, Sendable {
    public let githubLogin: String
    public let configDirectory: URL?
    public let expectedIdentity: GitHubIdentity?

    public init(
        githubLogin: String,
        configDirectory: URL? = nil,
        expectedIdentity: GitHubIdentity? = nil,
    ) {
        self.githubLogin = githubLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configDirectory = configDirectory?.standardizedFileURL
        self.expectedIdentity = expectedIdentity
    }
}

public struct GitHubCopilotCredential: Equatable, Sendable {
    let token: String

    public init(token: String) {
        self.token = token
    }
}

public struct GitHubCopilotPercentageMetric: Equatable, Sendable {
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

public struct GitHubCopilotAmountMetric: Equatable, Sendable {
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

public enum GitHubCopilotMetric: Equatable, Sendable {
    case amount(GitHubCopilotAmountMetric)
    case percentage(GitHubCopilotPercentageMetric)
}

public struct GitHubCopilotProbeResult: Equatable, Sendable {
    public let identity: GitHubIdentity
    public let planName: String?
    public let metrics: [GitHubCopilotMetric]
    public let isOrganizationManaged: Bool
    public let observedAt: Date

    public init(
        identity: GitHubIdentity,
        planName: String?,
        metrics: [GitHubCopilotMetric],
        isOrganizationManaged: Bool,
        observedAt: Date,
    ) {
        self.identity = identity
        self.planName = planName
        self.metrics = metrics
        self.isOrganizationManaged = isOrganizationManaged
        self.observedAt = observedAt
    }
}

public enum GitHubCopilotSpikeError: Error, Equatable, Sendable {
    case cliFailed
    case cliUnavailable
    case duplicateIdentity
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

extension GitHubCopilotSpikeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cliFailed:
            "GitHub CLI could not read the selected account without interaction."
        case .cliUnavailable:
            "GitHub CLI is not installed in a standard location or PATH."
        case .duplicateIdentity:
            "Two GitHub CLI profiles resolved to the same GitHub account."
        case .identityMismatch:
            "The selected GitHub CLI account no longer matches its registered identity."
        case .invalidCredential:
            "GitHub CLI returned an empty or invalid token."
        case .invalidProfile:
            "The GitHub account binding is invalid."
        case .invalidResponse:
            "GitHub returned an invalid Copilot response."
        case .quotaUnavailable:
            "GitHub identified the Copilot plan but returned no usable quota buckets."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "GitHub rate-limited the request. Retry after \(Int(retryAfter)) seconds."
            } else {
                "GitHub rate-limited the request."
            }
        case .reauthenticationRequired:
            "The selected GitHub CLI account is no longer accepted. Reauthenticate it with gh."
        case let .requestFailed(statusCode):
            "GitHub returned HTTP \(statusCode)."
        case .signedOut:
            "No authenticated GitHub.com account is available for this binding."
        case .transportFailed:
            "The GitHub request failed before a response arrived."
        }
    }
}

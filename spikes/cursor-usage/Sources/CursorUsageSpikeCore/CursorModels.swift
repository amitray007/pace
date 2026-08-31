import Foundation

public struct CursorIdentity: Equatable, Hashable, Sendable {
    public let userID: String
    public let teamID: String?
    public let email: String?
    public let displayName: String?

    public init(
        userID: String,
        teamID: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
    ) {
        self.userID = userID
        self.teamID = teamID
        self.email = email
        self.displayName = displayName
    }

    public var stableKey: String {
        "\(userID.lowercased())|\(teamID?.lowercased() ?? "personal")"
    }
}

public enum CursorCredentialStore: String, Equatable, Hashable, Sendable {
    case defaultKeychain
    case isolatedFile

    public var label: String {
        switch self {
        case .defaultKeychain:
            "keychain"
        case .isolatedFile:
            "file"
        }
    }
}

public struct CursorProfileBinding: Equatable, Hashable, Sendable {
    public let homeDirectory: URL
    public let credentialStore: CursorCredentialStore
    public let expectedIdentity: CursorIdentity?

    public init(
        homeDirectory: URL,
        credentialStore: CursorCredentialStore,
        expectedIdentity: CursorIdentity? = nil,
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.credentialStore = credentialStore
        self.expectedIdentity = expectedIdentity
    }

    public static var defaultProfile: Self {
        Self(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            credentialStore: .defaultKeychain,
        )
    }

    public static func isolated(
        homeDirectory: URL,
        expectedIdentity: CursorIdentity? = nil,
    ) -> Self {
        Self(
            homeDirectory: homeDirectory,
            credentialStore: .isolatedFile,
            expectedIdentity: expectedIdentity,
        )
    }

    public var cursorDirectory: URL {
        homeDirectory.appending(path: ".cursor", directoryHint: .isDirectory)
    }

    public var credentialFile: URL {
        cursorDirectory.appending(path: "auth.json", directoryHint: .notDirectory)
    }

    public var cliConfigFile: URL {
        cursorDirectory.appending(path: "cli-config.json", directoryHint: .notDirectory)
    }

    public func processEnvironment(inheriting base: [String: String]) -> [String: String] {
        guard credentialStore == .isolatedFile else {
            return base
        }
        var environment = base
        environment["HOME"] = homeDirectory.path
        environment["CURSOR_CONFIG_DIR"] = cursorDirectory.path
        environment["CURSOR_DATA_DIR"] = cursorDirectory.path
        environment["AGENT_CLI_CREDENTIAL_STORE"] = "file"
        return environment
    }
}

public struct CursorCredential: Equatable, Sendable {
    let accessToken: String
    let authID: String
    public let source: CursorCredentialStore

    public init(
        accessToken: String,
        authID: String,
        source: CursorCredentialStore,
    ) {
        self.accessToken = accessToken
        self.authID = authID
        self.source = source
    }
}

public struct CursorPercentageMetric: Equatable, Sendable {
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

public struct CursorAmountMetric: Equatable, Sendable {
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

public enum CursorMetric: Equatable, Sendable {
    case amount(CursorAmountMetric)
    case percentage(CursorPercentageMetric)
}

public struct CursorProbeResult: Equatable, Sendable {
    public let identity: CursorIdentity
    public let planName: String?
    public let metrics: [CursorMetric]
    public let observedAt: Date
    public let credentialSource: CursorCredentialStore

    public init(
        identity: CursorIdentity,
        planName: String?,
        metrics: [CursorMetric],
        observedAt: Date,
        credentialSource: CursorCredentialStore,
    ) {
        self.identity = identity
        self.planName = planName
        self.metrics = metrics
        self.observedAt = observedAt
        self.credentialSource = credentialSource
    }
}

public enum CursorSpikeError: Error, Equatable, Sendable {
    case cliUnavailable
    case credentialReadFailed
    case duplicateIdentity
    case identityMismatch
    case insecureCredentialFile
    case invalidCredential
    case invalidResponse
    case rateLimited(retryAfter: TimeInterval?)
    case requestFailed(statusCode: Int)
    case signedOut
    case statusFailed
    case transportFailed
}

extension CursorSpikeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cliUnavailable:
            "Cursor Agent is not installed or cannot be launched."
        case .credentialReadFailed:
            "Cursor credentials could not be read without interaction."
        case .duplicateIdentity:
            "Two Cursor profiles resolved to the same user and team."
        case .identityMismatch:
            "The Cursor profile no longer matches its registered identity."
        case .insecureCredentialFile:
            "The isolated Cursor credential file is not private to the current user."
        case .invalidCredential:
            "The Cursor credential is malformed or does not match the verified user."
        case .invalidResponse:
            "Cursor returned an invalid response."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "Cursor rate-limited the request. Retry after \(Int(retryAfter)) seconds."
            } else {
                "Cursor rate-limited the request."
            }
        case let .requestFailed(statusCode):
            "Cursor returned HTTP \(statusCode)."
        case .signedOut:
            "No Cursor Agent login exists for this profile."
        case .statusFailed:
            "Cursor Agent could not verify this profile with Cursor."
        case .transportFailed:
            "The Cursor request failed before a response arrived."
        }
    }
}

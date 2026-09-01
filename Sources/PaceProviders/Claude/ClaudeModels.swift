import CryptoKit
import Foundation
import PaceCore

public struct ClaudeProfile: Equatable, Sendable {
    public static let baseKeychainService = "Claude Code-credentials"

    public let directory: URL
    public let secureStorageDirectory: URL
    public let keychainService: String
    public let keychainAccount: String
    public let isCredentialBindingValid: Bool
    public let ownership: ProfileOwnership
    public let displayName: String?
    public let expectedIdentity: ProviderIdentity?

    public init(
        directory: URL,
        ownership: ProfileOwnership,
        displayName: String? = nil,
        expectedIdentity: ProviderIdentity? = nil,
        secureStorageDirectory: URL? = nil,
        keychainService: String? = nil,
        keychainAccount: String? = nil,
        usesScopedSecureStorage: Bool = true,
        isCredentialBindingValid: Bool = true,
    ) {
        self.directory = Self.normalized(directory)
        let storageDirectory = Self.normalized(secureStorageDirectory ?? directory)
        self.secureStorageDirectory = storageDirectory
        self.keychainService = keychainService ?? Self.keychainService(
            selector: storageDirectory.path,
            isScoped: usesScopedSecureStorage,
        )
        self.keychainAccount = keychainAccount ?? Self.defaultKeychainAccount()
        self.isCredentialBindingValid = isCredentialBindingValid
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
            secureStorageDirectory: secureStorageDirectory,
            keychainService: keychainService,
            keychainAccount: keychainAccount,
            isCredentialBindingValid: isCredentialBindingValid,
        )
    }

    public static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        ownership: ProfileOwnership = .existing,
    ) -> Self {
        let defaultDirectory = homeDirectory.appending(
            path: ".claude",
            directoryHint: .isDirectory,
        )
        let configurationSelector = environment["CLAUDE_CONFIG_DIR"]
        let configurationDirectory = configurationSelector.map {
            URL(filePath: $0, directoryHint: .isDirectory)
        } ?? defaultDirectory
        let secureStorageSelector = environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"]
        let secureStorageDirectory: URL
        let keychainSelector: String
        let isScoped: Bool
        if let secureStorageSelector {
            secureStorageDirectory = secureStorageSelector.isEmpty
                ? defaultDirectory
                : URL(filePath: secureStorageSelector, directoryHint: .isDirectory)
            keychainSelector = secureStorageSelector
            isScoped = !secureStorageSelector.isEmpty
        } else {
            secureStorageDirectory = configurationDirectory
            keychainSelector = configurationSelector ?? defaultDirectory.path
            isScoped = configurationSelector.map { !$0.isEmpty } ?? false
        }
        return Self(
            directory: configurationDirectory,
            ownership: ownership,
            secureStorageDirectory: secureStorageDirectory,
            keychainService: keychainService(selector: keychainSelector, isScoped: isScoped),
            keychainAccount: defaultKeychainAccount(environment: environment),
            isCredentialBindingValid: (configurationSelector.map(isAbsolutePath) ?? true)
                && (secureStorageSelector.map { $0.isEmpty || isAbsolutePath($0) } ?? true),
        )
    }

    public var credentialBinding: CredentialBinding {
        .claudeProfile(ClaudeCredentialBinding(
            configurationDirectory: directory,
            secureStorageDirectory: secureStorageDirectory,
            keychainService: keychainService,
            keychainAccount: keychainAccount,
            ownership: ownership,
        ))
    }

    static func keychainService(selector: String, isScoped: Bool) -> String {
        guard isScoped else {
            return baseKeychainService
        }
        let normalized = selector.precomposedStringWithCanonicalMapping
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(baseKeychainService)-\(suffix)"
    }

    static func defaultKeychainAccount(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> String {
        let candidate = environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? NSUserName()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"
            + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !candidate.isEmpty,
              candidate.unicodeScalars.allSatisfy(allowed.contains)
        else {
            return "claude-code-user"
        }
        return candidate
    }

    private static func normalized(_ url: URL) -> URL {
        URL(
            filePath: url.path.precomposedStringWithCanonicalMapping,
            directoryHint: .isDirectory,
        )
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        NSString(string: path).isAbsolutePath
    }
}

struct ClaudeIdentity: Equatable, Hashable, Sendable {
    let accountID: String
    let organizationID: String
    let email: String?
    let accountName: String?
    let organizationName: String?

    var stableKey: String {
        "\(accountID.lowercased())|\(organizationID.lowercased())"
    }

    var providerIdentity: ProviderIdentity {
        ProviderIdentity(
            subjectID: "claude:\(stableKey)",
            email: email,
            organizationID: organizationID,
        )
    }
}

struct ClaudeCredential: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    let subscriptionType: String?
    let rateLimitTier: String?
    let scopes: Set<String>?

    var canReadUsage: Bool {
        guard let scopes else {
            return true
        }
        return scopes.contains("user:profile")
    }
}

enum ClaudeCredentialLocation: Equatable, Hashable, Sendable {
    case file(URL)
    case keychain(service: String, account: String)
}

enum ClaudeCredentialEncoding: Equatable, Sendable {
    case hex
    case json
}

struct ClaudeCredentialCandidate: Equatable, Sendable {
    var credential: ClaudeCredential
    let location: ClaudeCredentialLocation
    let encoding: ClaudeCredentialEncoding
    let originalDocument: Data
}

struct ClaudeCredentialGeneration: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let credential: ClaudeCredential
        let location: ClaudeCredentialLocation
    }

    let entries: [Entry]

    init(_ candidates: [ClaudeCredentialCandidate]) {
        entries = candidates.map {
            Entry(credential: $0.credential, location: $0.location)
        }
    }
}

struct ClaudePercentageMetric: Equatable, Sendable {
    let id: String
    let label: String
    let usedFraction: Double
    let windowDuration: TimeInterval?
    let resetsAt: Date?
}

struct ClaudeAmountMetric: Equatable, Sendable {
    let id: String
    let label: String
    let used: Decimal
    let limit: Decimal?
    let unit: String
}

enum ClaudeMetric: Equatable, Sendable {
    case amount(ClaudeAmountMetric)
    case percentage(ClaudePercentageMetric)
}

struct ClaudeUsageResult: Equatable, Sendable {
    let identity: ClaudeIdentity
    let planName: String?
    let metrics: [ClaudeMetric]
    let observedAt: Date
}

enum ClaudeProviderError: Error, Equatable, Sendable {
    case cancelled
    case credentialChanged
    case credentialReadFailed
    case credentialWriteFailed
    case identityMismatch
    case insecureCredentialFile
    case invalidCredential
    case invalidProfile
    case invalidResponse
    case missingProfileScope
    case rateLimited(retryAfter: TimeInterval?)
    case reauthenticationRequired
    case requestFailed(statusCode: Int)
    case refreshLocked
    case signedOut
    case transportFailed
}

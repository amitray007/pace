import Foundation

public struct ProviderIdentity: Codable, Equatable, Hashable, Sendable {
    public let subjectID: String
    public let email: String?
    public let organizationID: String?

    public init(
        subjectID: String,
        email: String? = nil,
        organizationID: String? = nil,
    ) {
        self.subjectID = subjectID
        self.email = email
        self.organizationID = organizationID
    }
}

public enum ProfileOwnership: String, Codable, Sendable {
    case existing
    case paceManaged
}

public struct ClaudeCredentialBinding: Codable, Equatable, Sendable {
    public let configurationDirectory: URL
    public let secureStorageDirectory: URL
    public let keychainService: String
    public let keychainAccount: String
    public let ownership: ProfileOwnership

    public init(
        configurationDirectory: URL,
        secureStorageDirectory: URL,
        keychainService: String,
        keychainAccount: String,
        ownership: ProfileOwnership,
    ) {
        self.configurationDirectory = configurationDirectory
        self.secureStorageDirectory = secureStorageDirectory
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
        self.ownership = ownership
    }
}

public enum CursorCredentialSource: String, Codable, Equatable, Hashable, Sendable {
    case defaultKeychain
    case isolatedFile
}

public struct CursorCredentialBinding: Codable, Equatable, Sendable {
    public let homeDirectory: URL
    public let credentialSource: CursorCredentialSource
    public let ownership: ProfileOwnership

    public init(
        homeDirectory: URL,
        credentialSource: CursorCredentialSource,
        ownership: ProfileOwnership,
    ) {
        self.homeDirectory = homeDirectory
        self.credentialSource = credentialSource
        self.ownership = ownership
    }
}

public enum CredentialBinding: Codable, Equatable, Sendable {
    case claudeProfile(ClaudeCredentialBinding)
    case cursorProfile(CursorCredentialBinding)
    case commandLineAccount(
        tool: String,
        account: String,
        configurationDirectory: URL?,
    )
    case providerProfile(directory: URL, ownership: ProfileOwnership)
    case keychain(service: String, account: String)
    case simulated
}

enum CredentialSourceKey: Equatable, Hashable, Sendable {
    case claudeProfile(
        configurationPath: String,
        secureStoragePath: String,
        keychainService: String,
        keychainAccount: String,
    )
    case commandLineAccount(tool: String, account: String, configurationPath: String?)
    case cursorProfile(homePath: String, credentialSource: CursorCredentialSource)
    case providerProfile(path: String)
    case keychain(service: String, account: String)
}

extension CredentialBinding {
    var sourceKey: CredentialSourceKey? {
        switch self {
        case let .claudeProfile(binding):
            .claudeProfile(
                configurationPath: binding.configurationDirectory.path,
                secureStoragePath: binding.secureStorageDirectory.path,
                keychainService: binding.keychainService,
                keychainAccount: binding.keychainAccount,
            )
        case let .commandLineAccount(tool, account, configurationDirectory):
            .commandLineAccount(
                tool: tool.lowercased(),
                account: account.lowercased(),
                configurationPath: configurationDirectory.map {
                    $0.standardizedFileURL.resolvingSymlinksInPath().path
                },
            )
        case let .cursorProfile(binding):
            .cursorProfile(
                homePath: binding.homeDirectory.standardizedFileURL
                    .resolvingSymlinksInPath().path,
                credentialSource: binding.credentialSource,
            )
        case let .providerProfile(directory, _):
            .providerProfile(
                path: directory.standardizedFileURL.resolvingSymlinksInPath().path,
            )
        case let .keychain(service, account):
            .keychain(service: service, account: account)
        case .simulated:
            nil
        }
    }
}

public enum AccountConnectionState: Codable, Equatable, Sendable {
    case connected(lastVerifiedAt: Date)
    case needsAuthentication
    case identityMismatch
    case rateLimited(retryAt: Date?)
    case unavailable(code: String)
    case failed(code: String)
}

public struct ProviderAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: AccountID
    public let providerID: ProviderID
    public let identity: ProviderIdentity
    public let credentialBinding: CredentialBinding
    public let addedAt: Date
    public var displayName: String
    public var planName: String?
    public var isEnabled: Bool
    public var order: Int
    public var connectionState: AccountConnectionState

    public init(
        id: AccountID,
        providerID: ProviderID,
        identity: ProviderIdentity,
        credentialBinding: CredentialBinding,
        addedAt: Date,
        displayName: String,
        planName: String?,
        isEnabled: Bool,
        order: Int,
        connectionState: AccountConnectionState,
    ) {
        self.id = id
        self.providerID = providerID
        self.identity = identity
        self.credentialBinding = credentialBinding
        self.addedAt = addedAt
        self.displayName = displayName
        self.planName = planName
        self.isEnabled = isEnabled
        self.order = order
        self.connectionState = connectionState
    }
}

public struct DiscoveredAccount: Codable, Equatable, Sendable {
    public let providerID: ProviderID
    public let identity: ProviderIdentity
    public let suggestedDisplayName: String
    public let planName: String?
    public let credentialBinding: CredentialBinding

    public init(
        providerID: ProviderID,
        identity: ProviderIdentity,
        suggestedDisplayName: String,
        planName: String? = nil,
        credentialBinding: CredentialBinding,
    ) {
        self.providerID = providerID
        self.identity = identity
        self.suggestedDisplayName = suggestedDisplayName
        self.planName = planName
        self.credentialBinding = credentialBinding
    }
}

public enum AccountMutationError: Error, Equatable, Sendable {
    case duplicateCredentialBinding(providerID: ProviderID)
    case duplicateDisplayName(providerID: ProviderID, displayName: String)
    case duplicateIdentity(providerID: ProviderID, subjectID: String)
    case emptyDisplayName
    case invalidOrder(providerID: ProviderID)
    case unknownAccount(AccountID)
    case accountDisabled(AccountID)
    case providerMismatch(AccountID)
    case invalidSnapshots(AccountID)
}

import Foundation

public struct ProviderCapabilities: Codable, Equatable, Sendable {
    public let supportsAccountDiscovery: Bool
    public let supportsMultipleAccounts: Bool
    public let supportsStreamingUpdates: Bool

    public init(
        supportsAccountDiscovery: Bool,
        supportsMultipleAccounts: Bool,
        supportsStreamingUpdates: Bool,
    ) {
        self.supportsAccountDiscovery = supportsAccountDiscovery
        self.supportsMultipleAccounts = supportsMultipleAccounts
        self.supportsStreamingUpdates = supportsStreamingUpdates
    }
}

public enum ProviderFailure: Error, Equatable, Sendable {
    case failed(code: String)
    case rateLimited(retryAt: Date?)
    case signedOut
    case unavailable(code: String)
}

public struct ProviderRefreshResult: Equatable, Sendable {
    public let identity: ProviderIdentity
    public let planName: String?
    public let snapshots: [LimitSnapshot]
    public let verifiedAt: Date

    public init(
        identity: ProviderIdentity,
        planName: String?,
        snapshots: [LimitSnapshot],
        verifiedAt: Date,
    ) {
        self.identity = identity
        self.planName = planName
        self.snapshots = snapshots
        self.verifiedAt = verifiedAt
    }
}

public protocol ProviderAdapter: Sendable {
    nonisolated var providerID: ProviderID { get }
    nonisolated var capabilities: ProviderCapabilities { get }

    func discoverAccounts() async throws(ProviderFailure) -> [DiscoveredAccount]
    func refresh(_ account: ProviderAccount) async throws(ProviderFailure) -> ProviderRefreshResult
}

public enum ProviderUpdate: Sendable {
    case failure(ProviderFailure)
    case refresh(ProviderRefreshResult)
}

public protocol ProviderUpdateStreamingAdapter: ProviderAdapter {
    func updates(for account: ProviderAccount) async -> AsyncStream<ProviderUpdate>
}

public enum AccountRefreshOutcome: Sendable {
    case failure(accountID: AccountID, failure: ProviderFailure)
    case success(accountID: AccountID, result: ProviderRefreshResult)

    public var accountID: AccountID {
        switch self {
        case let .failure(accountID, _), let .success(accountID, _):
            accountID
        }
    }
}

public enum ProviderUpdateDelivery: Sendable {
    case applied(AccountRefreshOutcome)
    case persistenceFailed(accountID: AccountID)
}

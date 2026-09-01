import Foundation

public enum UsageDataFreshness: String, Codable, Equatable, Sendable {
    case aging
    case current
    case noData
    case stale
}

public enum AccountConnectionIssue: Codable, Equatable, Sendable {
    case failed(code: String)
    case identityMismatch
    case needsAuthentication
    case rateLimited(retryAt: Date?)
    case unavailable(code: String)
}

public struct AccountUsageStatus: Codable, Equatable, Sendable {
    public let dataFreshness: UsageDataFreshness
    public let connectionIssue: AccountConnectionIssue?
    public let observedAt: Date?

    public var hasData: Bool {
        dataFreshness != .noData
    }

    public init(account: ProviderAccount, snapshots: [LimitSnapshot]) {
        dataFreshness = Self.dataFreshness(for: snapshots)
        connectionIssue = Self.connectionIssue(for: account.connectionState)
        observedAt = snapshots.map(\.observedAt).max()
    }

    private static func dataFreshness(
        for snapshots: [LimitSnapshot],
    ) -> UsageDataFreshness {
        guard !snapshots.isEmpty else {
            return .noData
        }
        if snapshots.contains(where: { snapshot in
            switch snapshot.freshness {
            case .failed, .signedOut, .stale, .unavailable:
                true
            case .aging, .current:
                false
            }
        }) {
            return .stale
        }
        return snapshots.contains(where: { $0.freshness == .aging }) ? .aging : .current
    }

    private static func connectionIssue(
        for state: AccountConnectionState,
    ) -> AccountConnectionIssue? {
        switch state {
        case .connected:
            nil
        case .needsAuthentication:
            .needsAuthentication
        case .identityMismatch:
            .identityMismatch
        case let .rateLimited(retryAt):
            .rateLimited(retryAt: retryAt)
        case let .unavailable(code):
            .unavailable(code: code)
        case let .failed(code):
            .failed(code: code)
        }
    }
}

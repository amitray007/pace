import Foundation

public enum AccountDiscoveryStatus: Equatable, Sendable {
    case available
    case registered(accountID: AccountID)
    case credentialInUse(accountID: AccountID)
    case identityInUse(accountID: AccountID)
}

public struct AccountDiscoveryCandidate: Equatable, Sendable {
    public let account: DiscoveredAccount
    public let status: AccountDiscoveryStatus
}

public enum AccountCoordinatorError: Error, Equatable, Sendable {
    case candidateUnavailable(AccountDiscoveryStatus)
    case providerMismatch(expected: ProviderID, actual: ProviderID)
}

public struct AccountCoordinator: Sendable {
    private let refreshCoordinator: RefreshCoordinator
    private let store: PaceStore

    public init(store: PaceStore, refreshCoordinator: RefreshCoordinator) {
        self.store = store
        self.refreshCoordinator = refreshCoordinator
    }

    public func discover(
        for providerID: ProviderID,
    ) async throws -> [AccountDiscoveryCandidate] {
        let discoveredAccounts = try await refreshCoordinator.discoverAccounts(for: providerID)
        for account in discoveredAccounts where account.providerID != providerID {
            throw AccountCoordinatorError.providerMismatch(
                expected: providerID,
                actual: account.providerID,
            )
        }

        let registeredAccounts = await store.accounts(
            for: providerID,
            includeDisabled: true,
        )
        return discoveredAccounts.map { account in
            AccountDiscoveryCandidate(
                account: account,
                status: Self.status(for: account, registeredAccounts: registeredAccounts),
            )
        }
    }

    @discardableResult
    public func add(
        _ candidate: AccountDiscoveryCandidate,
        displayName: String? = nil,
        id: AccountID = AccountID(),
        addedAt: Date = Date(),
    ) async throws -> ProviderAccount {
        let registeredAccounts = await store.accounts(
            for: candidate.account.providerID,
            includeDisabled: true,
        )
        let currentStatus = Self.status(
            for: candidate.account,
            registeredAccounts: registeredAccounts,
        )
        guard currentStatus == .available else {
            throw AccountCoordinatorError.candidateUnavailable(currentStatus)
        }
        return try await store.register(
            candidate.account,
            displayName: displayName,
            id: id,
            addedAt: addedAt,
        )
    }

    public func rename(_ accountID: AccountID, to displayName: String) async throws {
        try await store.renameAccount(accountID, to: displayName)
    }

    public func setEnabled(_ accountID: AccountID, isEnabled: Bool) async throws {
        try await store.setAccount(accountID, isEnabled: isEnabled)
    }

    @discardableResult
    public func refresh(_ accountID: AccountID) async throws -> AccountRefreshOutcome {
        try await refreshCoordinator.refresh(accountID)
    }

    @discardableResult
    public func remove(_ accountID: AccountID) async throws -> ProviderAccount {
        try await store.removeAccount(accountID)
    }

    private static func status(
        for discoveredAccount: DiscoveredAccount,
        registeredAccounts: [ProviderAccount],
    ) -> AccountDiscoveryStatus {
        if let sourceKey = discoveredAccount.credentialBinding.sourceKey {
            if let existing = registeredAccounts.first(where: {
                $0.credentialBinding.sourceKey == sourceKey
            }) {
                return existing.identity.subjectID == discoveredAccount.identity.subjectID
                    ? .registered(accountID: existing.id)
                    : .credentialInUse(accountID: existing.id)
            }
        }
        if let existing = registeredAccounts.first(where: {
            $0.identity.subjectID == discoveredAccount.identity.subjectID
        }) {
            return .identityInUse(accountID: existing.id)
        }
        return .available
    }
}

import Foundation

public actor PaceStore {
    private let persistence: any PaceStatePersistence
    private var state: PaceState

    public init(
        initialState: PaceState = PaceState(),
        persistence: any PaceStatePersistence,
    ) {
        state = initialState
        self.persistence = persistence
    }

    public static func open(
        persistence: any PaceStatePersistence,
    ) async throws -> PaceStore {
        let state = try await persistence.load() ?? PaceState()
        return PaceStore(initialState: state, persistence: persistence)
    }

    public func currentState() -> PaceState {
        state
    }

    public func accounts(
        for providerID: ProviderID,
        includeDisabled: Bool = false,
    ) -> [ProviderAccount] {
        state.accounts
            .filter { account in
                account.providerID == providerID && (includeDisabled || account.isEnabled)
            }
            .sorted(by: Self.accountPrecedes)
    }

    public func selectedAccount(for providerID: ProviderID) -> ProviderAccount? {
        guard let accountID = state.selections.first(where: {
            $0.providerID == providerID
        })?.accountID else {
            return nil
        }
        return state.accounts.first(where: { $0.id == accountID && $0.isEnabled })
    }

    @discardableResult
    public func register(
        _ discoveredAccount: DiscoveredAccount,
        displayName: String? = nil,
        id: AccountID = AccountID(),
        addedAt: Date = Date(),
    ) async throws -> ProviderAccount {
        let resolvedName = try normalizedDisplayName(
            displayName ?? discoveredAccount.suggestedDisplayName,
        )
        try ensureIdentityIsUnique(
            discoveredAccount.identity,
            providerID: discoveredAccount.providerID,
        )
        try ensureDisplayNameIsUnique(resolvedName, providerID: discoveredAccount.providerID)

        let providerAccounts = state.accounts.filter {
            $0.providerID == discoveredAccount.providerID
        }
        let order = (providerAccounts.map(\.order).max() ?? -1) + 1
        let account = ProviderAccount(
            id: id,
            providerID: discoveredAccount.providerID,
            identity: discoveredAccount.identity,
            credentialBinding: discoveredAccount.credentialBinding,
            addedAt: addedAt,
            displayName: resolvedName,
            planName: discoveredAccount.planName,
            isEnabled: true,
            order: order,
            connectionState: .connected(lastVerifiedAt: addedAt),
        )

        var next = state
        next.accounts.append(account)
        if !next.selections.contains(where: { $0.providerID == account.providerID }) {
            next.selections.append(
                ProviderSelection(providerID: account.providerID, accountID: account.id),
            )
        }
        try await commit(next)
        return account
    }

    public func renameAccount(_ accountID: AccountID, to displayName: String) async throws {
        guard let index = state.accounts.firstIndex(where: { $0.id == accountID }) else {
            throw AccountMutationError.unknownAccount(accountID)
        }
        let normalizedName = try normalizedDisplayName(displayName)
        let account = state.accounts[index]
        try ensureDisplayNameIsUnique(
            normalizedName,
            providerID: account.providerID,
            excluding: accountID,
        )

        var next = state
        next.accounts[index].displayName = normalizedName
        try await commit(next)
    }

    public func setAccount(_ accountID: AccountID, isEnabled: Bool) async throws {
        guard let index = state.accounts.firstIndex(where: { $0.id == accountID }) else {
            throw AccountMutationError.unknownAccount(accountID)
        }

        var next = state
        next.accounts[index].isEnabled = isEnabled
        reconcileSelection(for: next.accounts[index].providerID, in: &next)
        try await commit(next)
    }

    public func reorderAccounts(
        for providerID: ProviderID,
        accountIDs: [AccountID],
    ) async throws {
        let currentIDs = Set(state.accounts.lazy.filter {
            $0.providerID == providerID
        }.map(\.id))
        guard currentIDs == Set(accountIDs), currentIDs.count == accountIDs.count else {
            throw AccountMutationError.invalidOrder(providerID: providerID)
        }

        var next = state
        for (order, accountID) in accountIDs.enumerated() {
            guard let index = next.accounts.firstIndex(where: { $0.id == accountID }) else {
                throw AccountMutationError.unknownAccount(accountID)
            }
            next.accounts[index].order = order
        }
        try await commit(next)
    }

    @discardableResult
    public func removeAccount(_ accountID: AccountID) async throws -> ProviderAccount {
        guard let account = state.accounts.first(where: { $0.id == accountID }) else {
            throw AccountMutationError.unknownAccount(accountID)
        }

        var next = state
        next.accounts.removeAll(where: { $0.id == accountID })
        next.snapshots.removeAll(where: { $0.id.accountID == accountID })
        next.selections.removeAll(where: { $0.accountID == accountID })
        reconcileSelection(for: account.providerID, in: &next)
        try await commit(next)
        return account
    }

    public func selectAccount(_ accountID: AccountID, for providerID: ProviderID) async throws {
        guard let account = state.accounts.first(where: { $0.id == accountID }) else {
            throw AccountMutationError.unknownAccount(accountID)
        }
        guard account.providerID == providerID else {
            throw AccountMutationError.providerMismatch(accountID)
        }
        guard account.isEnabled else {
            throw AccountMutationError.accountDisabled(accountID)
        }

        var next = state
        next.selections.removeAll(where: { $0.providerID == providerID })
        next.selections.append(ProviderSelection(providerID: providerID, accountID: accountID))
        try await commit(next)
    }

    public func replaceSnapshots(
        for accountID: AccountID,
        with snapshots: [LimitSnapshot],
    ) async throws {
        guard let account = state.accounts.first(where: { $0.id == accountID }) else {
            throw AccountMutationError.unknownAccount(accountID)
        }
        guard snapshots.allSatisfy({ snapshot in
            snapshot.id.accountID == accountID && snapshot.id.providerID == account.providerID
        }) else {
            throw AccountMutationError.invalidSnapshots(accountID)
        }

        var next = state
        next.snapshots.removeAll(where: { $0.id.accountID == accountID })
        next.snapshots.append(contentsOf: snapshots)
        try await commit(next)
    }

    public func applyRefreshOutcomes(_ outcomes: [AccountRefreshOutcome]) async throws {
        var next = state

        for outcome in outcomes {
            guard let accountIndex = next.accounts.firstIndex(where: {
                $0.id == outcome.accountID
            }) else {
                continue
            }

            switch outcome {
            case let .failure(accountID, failure):
                next.accounts[accountIndex].connectionState = Self.connectionState(for: failure)
                Self.markSnapshotsStale(for: accountID, in: &next)

            case let .success(accountID, result):
                let account = next.accounts[accountIndex]
                guard result.identity.subjectID == account.identity.subjectID else {
                    next.accounts[accountIndex].connectionState = .identityMismatch
                    Self.markSnapshotsStale(for: accountID, in: &next)
                    continue
                }
                guard result.snapshots.allSatisfy({ snapshot in
                    snapshot.id.providerID == account.providerID &&
                        snapshot.id.accountID == accountID
                }) else {
                    next.accounts[accountIndex].connectionState = .failed(
                        code: "invalid-snapshot-owner",
                    )
                    Self.markSnapshotsStale(for: accountID, in: &next)
                    continue
                }

                next.accounts[accountIndex].planName = result.planName
                next.accounts[accountIndex].connectionState = .connected(
                    lastVerifiedAt: result.verifiedAt,
                )
                next.snapshots.removeAll(where: { $0.id.accountID == accountID })
                next.snapshots.append(contentsOf: result.snapshots)
            }
        }

        try await commit(next)
    }

    private static func accountPrecedes(_ lhs: ProviderAccount, _ rhs: ProviderAccount) -> Bool {
        if lhs.order == rhs.order {
            return lhs.addedAt < rhs.addedAt
        }
        return lhs.order < rhs.order
    }

    private func normalizedDisplayName(_ displayName: String) throws -> String {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw AccountMutationError.emptyDisplayName
        }
        return normalizedName
    }

    private func ensureIdentityIsUnique(
        _ identity: ProviderIdentity,
        providerID: ProviderID,
    ) throws {
        if state.accounts.contains(where: { account in
            account.providerID == providerID && account.identity.subjectID == identity.subjectID
        }) {
            throw AccountMutationError.duplicateIdentity(
                providerID: providerID,
                subjectID: identity.subjectID,
            )
        }
    }

    private func ensureDisplayNameIsUnique(
        _ displayName: String,
        providerID: ProviderID,
        excluding accountID: AccountID? = nil,
    ) throws {
        if state.accounts.contains(where: { account in
            account.id != accountID &&
                account.providerID == providerID &&
                account.displayName.caseInsensitiveCompare(displayName) == .orderedSame
        }) {
            throw AccountMutationError.duplicateDisplayName(
                providerID: providerID,
                displayName: displayName,
            )
        }
    }

    private func reconcileSelection(for providerID: ProviderID, in state: inout PaceState) {
        let selectedAccountID = state.selections.first(where: {
            $0.providerID == providerID
        })?.accountID
        let selectionIsValid = state.accounts.contains(where: { account in
            account.id == selectedAccountID && account.isEnabled
        })
        guard !selectionIsValid else {
            return
        }

        state.selections.removeAll(where: { $0.providerID == providerID })
        let replacement = state.accounts
            .filter { $0.providerID == providerID && $0.isEnabled }
            .min(by: Self.accountPrecedes)
        if let replacement {
            state.selections.append(
                ProviderSelection(providerID: providerID, accountID: replacement.id),
            )
        }
    }

    private static func connectionState(for failure: ProviderFailure) -> AccountConnectionState {
        switch failure {
        case let .failed(code):
            .failed(code: code)
        case let .rateLimited(retryAt):
            .rateLimited(retryAt: retryAt)
        case .signedOut:
            .needsAuthentication
        case let .unavailable(code):
            .unavailable(code: code)
        }
    }

    private static func markSnapshotsStale(for accountID: AccountID, in state: inout PaceState) {
        let matchingIndices = state.snapshots.indices.filter {
            state.snapshots[$0].id.accountID == accountID
        }
        for index in matchingIndices {
            state.snapshots[index].freshness = .stale
        }
    }

    private func commit(_ next: PaceState) async throws {
        try await persistence.save(next)
        state = next
    }
}

import Foundation

public enum RefreshCoordinatorError: Error, Equatable, Sendable {
    case duplicateAdapter(ProviderID)
    case missingAdapter(ProviderID)
}

public struct RefreshCoordinator: Sendable {
    private let adapters: [ProviderID: any ProviderAdapter]
    private let store: PaceStore

    public init(store: PaceStore, adapters: [any ProviderAdapter]) throws {
        var adaptersByProvider: [ProviderID: any ProviderAdapter] = [:]
        for adapter in adapters {
            let previousAdapter = adaptersByProvider.updateValue(
                adapter,
                forKey: adapter.providerID,
            )
            guard previousAdapter == nil else {
                throw RefreshCoordinatorError.duplicateAdapter(adapter.providerID)
            }
        }
        self.adapters = adaptersByProvider
        self.store = store
    }

    public func discoverAccounts(
        for providerID: ProviderID,
    ) async throws -> [DiscoveredAccount] {
        guard let adapter = adapters[providerID] else {
            throw RefreshCoordinatorError.missingAdapter(providerID)
        }
        return try await adapter.discoverAccounts()
    }

    @discardableResult
    public func refreshAll() async throws -> [AccountRefreshOutcome] {
        let state = await store.currentState()
        let accounts = state.accounts.filter(\.isEnabled)
        var outcomes: [AccountRefreshOutcome] = []

        await withTaskGroup(of: AccountRefreshOutcome.self) { group in
            for account in accounts {
                guard let adapter = adapters[account.providerID] else {
                    outcomes.append(
                        .failure(
                            accountID: account.id,
                            failure: .unavailable(code: "adapter-missing"),
                        ),
                    )
                    continue
                }

                group.addTask {
                    await Self.refreshOutcome(account: account, adapter: adapter)
                }
            }

            for await outcome in group {
                outcomes.append(outcome)
            }
        }

        outcomes.sort { $0.accountID < $1.accountID }
        try await store.applyRefreshOutcomes(outcomes)
        return outcomes
    }

    @discardableResult
    public func refresh(_ accountID: AccountID) async throws -> AccountRefreshOutcome {
        let state = await store.currentState()
        guard let account = state.accounts.first(where: { $0.id == accountID }) else {
            throw AccountMutationError.unknownAccount(accountID)
        }
        guard account.isEnabled else {
            throw AccountMutationError.accountDisabled(accountID)
        }
        guard let adapter = adapters[account.providerID] else {
            let outcome = AccountRefreshOutcome.failure(
                accountID: account.id,
                failure: .unavailable(code: "adapter-missing"),
            )
            try await store.applyRefreshOutcomes([outcome])
            return outcome
        }

        let outcome = await Self.refreshOutcome(account: account, adapter: adapter)
        try await store.applyRefreshOutcomes([outcome])
        return outcome
    }

    public func updateStream() async -> AsyncStream<ProviderUpdateDelivery> {
        AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let supervisorTask = Task {
                var monitorTasks: [AccountID: Task<Void, Never>] = [:]
                let stateUpdates = await store.stateUpdates()

                for await state in stateUpdates {
                    guard !Task.isCancelled else {
                        break
                    }
                    let accounts = state.accounts.filter(\.isEnabled)
                    let desiredIDs = Set(accounts.map(\.id))

                    let retiredIDs = monitorTasks.keys.filter { !desiredIDs.contains($0) }
                    for accountID in retiredIDs {
                        monitorTasks.removeValue(forKey: accountID)?.cancel()
                    }

                    for account in accounts where monitorTasks[account.id] == nil {
                        guard let adapter = adapters[account.providerID]
                            as? any ProviderUpdateStreamingAdapter
                        else {
                            continue
                        }
                        monitorTasks[account.id] = Task {
                            let updates = await adapter.updates(for: account)
                            for await update in updates {
                                guard !Task.isCancelled else {
                                    break
                                }
                                let outcome = Self.outcome(for: account.id, update: update)
                                do {
                                    try await store.applyRefreshOutcomes([outcome])
                                    continuation.yield(.applied(outcome))
                                } catch {
                                    continuation.yield(
                                        .persistenceFailed(accountID: account.id),
                                    )
                                }
                            }
                        }
                    }
                }

                monitorTasks.values.forEach { $0.cancel() }
                continuation.finish()
            }
            continuation.onTermination = { _ in supervisorTask.cancel() }
        }
    }

    private static func outcome(
        for accountID: AccountID,
        update: ProviderUpdate,
    ) -> AccountRefreshOutcome {
        switch update {
        case let .failure(failure):
            .failure(accountID: accountID, failure: failure)
        case let .refresh(result):
            .success(accountID: accountID, result: result)
        }
    }

    private static func refreshOutcome(
        account: ProviderAccount,
        adapter: any ProviderAdapter,
    ) async -> AccountRefreshOutcome {
        do {
            let result = try await adapter.refresh(account)
            return .success(accountID: account.id, result: result)
        } catch let failure {
            return .failure(accountID: account.id, failure: failure)
        }
    }
}

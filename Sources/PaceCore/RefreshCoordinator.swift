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
                    do {
                        let result = try await adapter.refresh(account)
                        return .success(accountID: account.id, result: result)
                    } catch let failure as ProviderFailure {
                        return .failure(accountID: account.id, failure: failure)
                    } catch {
                        return .failure(
                            accountID: account.id,
                            failure: .failed(code: "unexpected-adapter-error"),
                        )
                    }
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
}

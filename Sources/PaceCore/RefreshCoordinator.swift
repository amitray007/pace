import Foundation

public enum RefreshCoordinatorError: Error, Equatable, Sendable {
    case duplicateAdapter(ProviderID)
    case missingAdapter(ProviderID)
}

public struct RefreshCoordinator: Sendable {
    private let adapters: [ProviderID: any ProviderAdapter]
    private let store: PaceStore
    private let updateSupervisors = UpdateSupervisorRegistry()

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
        let accounts = Self.activeAccounts(in: state)
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
        let initialState = await store.currentState()
        let pair = AsyncStream<ProviderUpdateDelivery>.makeStream(
            bufferingPolicy: .bufferingNewest(64),
        )
        let supervisorID = UUID()
        let supervisorTask = Task {
            var monitors: [AccountID: AccountMonitor] = [:]
            await reconcileMonitors(
                for: initialState,
                continuation: pair.continuation,
                monitors: &monitors,
            )
            let stateUpdates = await store.stateUpdates()

            for await state in stateUpdates {
                guard !Task.isCancelled else {
                    break
                }
                await reconcileMonitors(
                    for: state,
                    continuation: pair.continuation,
                    monitors: &monitors,
                )
            }

            let remainingMonitors = Array(monitors.values)
            remainingMonitors.forEach { $0.task.cancel() }
            for monitor in remainingMonitors {
                await monitor.adapter.stopUpdates(for: monitor.account)
                await monitor.task.value
            }
            pair.continuation.finish()
            await updateSupervisors.remove(supervisorID)
        }
        await updateSupervisors.insert(supervisorTask, id: supervisorID)
        pair.continuation.onTermination = { _ in supervisorTask.cancel() }
        return pair.stream
    }

    public func shutdownUpdates() async {
        await updateSupervisors.shutdown()
    }

    public func shutdownAdapters() async {
        await shutdownUpdates()
        await withTaskGroup(of: Void.self) { group in
            for adapter in adapters.values {
                guard let lifecycle = adapter as? any ProviderAdapterLifecycle else {
                    continue
                }
                group.addTask {
                    await lifecycle.shutdown()
                }
            }
        }
    }

    private func reconcileMonitors(
        for state: PaceState,
        continuation: AsyncStream<ProviderUpdateDelivery>.Continuation,
        monitors: inout [AccountID: AccountMonitor],
    ) async {
        let accounts = Self.activeAccounts(in: state)
        let desiredIDs = Set(accounts.map(\.id))

        let retiredIDs = monitors.keys.filter { !desiredIDs.contains($0) }
        for accountID in retiredIDs {
            if let monitor = monitors.removeValue(forKey: accountID) {
                monitor.task.cancel()
                await monitor.adapter.stopUpdates(for: monitor.account)
                await monitor.task.value
            }
        }

        for account in accounts where monitors[account.id] == nil {
            guard let adapter = adapters[account.providerID]
                as? any ProviderUpdateStreamingAdapter
            else {
                continue
            }
            let task = Task {
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
                        continuation.yield(.persistenceFailed(accountID: account.id))
                    }
                }
            }
            monitors[account.id] = AccountMonitor(
                account: account,
                adapter: adapter,
                task: task,
            )
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

    private static func activeAccounts(in state: PaceState) -> [ProviderAccount] {
        let enabledAccounts = state.accounts.filter(\.isEnabled)
        let providersWithLiveAccounts = Set(enabledAccounts.compactMap { account in
            guard case .simulated = account.credentialBinding else {
                return account.providerID
            }
            return nil
        })
        return enabledAccounts.filter { account in
            guard providersWithLiveAccounts.contains(account.providerID) else {
                return true
            }
            guard case .simulated = account.credentialBinding else {
                return true
            }
            return false
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

private struct AccountMonitor: Sendable {
    let account: ProviderAccount
    let adapter: any ProviderUpdateStreamingAdapter
    let task: Task<Void, Never>
}

private actor UpdateSupervisorRegistry {
    private var isShutdown = false
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func insert(_ task: Task<Void, Never>, id: UUID) async {
        guard !isShutdown else {
            task.cancel()
            await task.value
            return
        }
        tasks[id] = task
    }

    func remove(_ id: UUID) {
        tasks.removeValue(forKey: id)
    }

    func shutdown() async {
        isShutdown = true
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        activeTasks.forEach { $0.cancel() }
        for task in activeTasks {
            await task.value
        }
    }
}

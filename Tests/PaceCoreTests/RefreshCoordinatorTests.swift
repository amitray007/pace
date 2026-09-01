@testable import PaceCore
import Testing

@Suite("Refresh coordinator")
struct RefreshCoordinatorTests {
    @Test
    func `contains provider failure to one account and preserves last-good data`() async throws {
        let setup = try await makeTwoAccountStore()
        let store = setup.store
        let personal = setup.personal
        let work = setup.work
        try await store.replaceSnapshots(
            for: TestSupport.workID,
            with: [TestSupport.snapshot(accountID: TestSupport.workID, usedFraction: 0.4)],
        )

        let personalSnapshot = try TestSupport.snapshot(
            accountID: TestSupport.personalID,
            usedFraction: 0.7,
        )
        let adapter = SimulatedProviderAdapter(
            providerID: .claude,
            discoveredAccounts: [personal, work],
            refreshSteps: [
                TestSupport.personalID: [
                    .result(
                        TestSupport.result(
                            for: personal,
                            accountID: TestSupport.personalID,
                            snapshots: [personalSnapshot],
                        ),
                    ),
                ],
                TestSupport.workID: [.failure(.unavailable(code: "maintenance"))],
            ],
        )
        let coordinator = try RefreshCoordinator(store: store, adapters: [adapter])

        try await coordinator.refreshAll()

        let state = await store.currentState()
        let personalState = try #require(state.accounts.first(where: {
            $0.id == TestSupport.personalID
        }))
        let workState = try #require(state.accounts.first(where: {
            $0.id == TestSupport.workID
        }))
        #expect(personalState.connectionState == .connected(
            lastVerifiedAt: TestSupport.referenceDate,
        ))
        #expect(workState.connectionState == .unavailable(code: "maintenance"))
        #expect(state.snapshots.first(where: {
            $0.id.accountID == TestSupport.personalID
        })?.usedFraction == 0.7)
        #expect(state.snapshots.first(where: {
            $0.id.accountID == TestSupport.workID
        })?.freshness == .stale)
    }

    @Test
    func `marks identity changes without replacing account data`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let personal = TestSupport.discoveredAccount(
            subjectID: "claude-personal",
            displayName: "Personal",
        )
        try await store.register(
            personal,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        let lastGood = try TestSupport.snapshot(
            accountID: TestSupport.personalID,
            usedFraction: 0.3,
        )
        try await store.replaceSnapshots(for: TestSupport.personalID, with: [lastGood])

        let changedIdentity = try ProviderRefreshResult(
            identity: ProviderIdentity(subjectID: "claude-other"),
            planName: "Claude Pro",
            snapshots: [
                TestSupport.snapshot(
                    accountID: TestSupport.personalID,
                    usedFraction: 0.9,
                ),
            ],
            verifiedAt: TestSupport.referenceDate,
        )
        let adapter = SimulatedProviderAdapter(
            providerID: .claude,
            discoveredAccounts: [personal],
            refreshSteps: [TestSupport.personalID: [.result(changedIdentity)]],
        )
        let coordinator = try RefreshCoordinator(store: store, adapters: [adapter])

        try await coordinator.refreshAll()

        let state = await store.currentState()
        #expect(state.accounts.first?.identity.subjectID == "claude-personal")
        #expect(state.accounts.first?.connectionState == .identityMismatch)
        #expect(state.snapshots.first?.usedFraction == 0.3)
        #expect(state.snapshots.first?.freshness == .stale)
    }

    @Test
    func `skips disabled accounts`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let personal = TestSupport.discoveredAccount(
            subjectID: "claude-personal",
            displayName: "Personal",
        )
        try await store.register(
            personal,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        try await store.setAccount(TestSupport.personalID, isEnabled: false)
        let adapter = SimulatedProviderAdapter(
            providerID: .claude,
            discoveredAccounts: [personal],
            refreshSteps: [
                TestSupport.personalID: [
                    .failure(.failed(code: "must-not-run")),
                ],
            ],
        )
        let coordinator = try RefreshCoordinator(store: store, adapters: [adapter])

        let outcomes = try await coordinator.refreshAll()

        #expect(outcomes.isEmpty)
        #expect(await adapter.refreshCount(for: TestSupport.personalID) == 0)
    }

    @Test
    func `applies streamed provider updates to shared state`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let discovered = TestSupport.discoveredAccount(
            subjectID: "claude-personal",
            displayName: "Personal",
        )
        let account = try await store.register(
            discovered,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        let adapter = StreamingTestAdapter(discoveredAccount: discovered)
        let coordinator = try RefreshCoordinator(store: store, adapters: [adapter])
        let updates = await coordinator.updateStream()
        let firstUpdate = Task<ProviderUpdateDelivery?, Never> {
            for await update in updates {
                return update
            }
            return nil
        }
        let snapshot = try TestSupport.snapshot(
            accountID: account.id,
            usedFraction: 0.62,
        )

        await adapter.send(
            .refresh(
                TestSupport.result(
                    for: discovered,
                    accountID: account.id,
                    snapshots: [snapshot],
                ),
            ),
        )

        let delivery = await firstUpdate.value
        let state = await store.currentState()
        guard case let .applied(outcome) = delivery else {
            Issue.record("Expected an applied provider update")
            return
        }
        #expect(outcome.accountID == account.id)
        #expect(state.snapshots.map(\.usedFraction) == [0.62])
        #expect(state.accounts.first?.connectionState == .connected(
            lastVerifiedAt: TestSupport.referenceDate,
        ))
        await adapter.finish()
    }

    @Test
    func `reconciles monitors when account lifecycle changes`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let discovered = TestSupport.discoveredAccount(
            subjectID: "claude-personal",
            displayName: "Personal",
        )
        let adapter = LifecycleStreamingTestAdapter(discoveredAccount: discovered)
        let coordinator = try RefreshCoordinator(store: store, adapters: [adapter])
        let updates = await coordinator.updateStream()
        let collector = Task {
            for await _ in updates {}
        }

        let account = try await store.register(
            discovered,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        try await waitUntil {
            await adapter.subscriptionCount(for: account.id) == 1
        }

        try await store.setAccount(account.id, isEnabled: false)
        try await waitUntil {
            await adapter.terminationCount(for: account.id) == 1
        }

        try await store.setAccount(account.id, isEnabled: true)
        try await waitUntil {
            await adapter.subscriptionCount(for: account.id) == 2
        }

        try await store.removeAccount(account.id)
        try await waitUntil {
            await adapter.terminationCount(for: account.id) == 2
        }
        collector.cancel()
        await collector.value
    }

    @Test
    func `separates persistence failure from applied provider updates`() async throws {
        let persistence = FailingPaceStatePersistence()
        let store = try await PaceStore.open(persistence: persistence)
        let discovered = TestSupport.discoveredAccount(
            subjectID: "claude-personal",
            displayName: "Personal",
        )
        let account = try await store.register(
            discovered,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        let adapter = StreamingTestAdapter(discoveredAccount: discovered)
        let coordinator = try RefreshCoordinator(store: store, adapters: [adapter])
        let updates = await coordinator.updateStream()
        let recorder = ProviderDeliveryRecorder()
        let collector = Task {
            for await delivery in updates {
                await recorder.append(delivery)
                if await recorder.count == 2 {
                    return
                }
            }
        }
        let result = try refreshResult(
            for: discovered,
            accountID: account.id,
            usedFraction: 0.64,
        )

        await persistence.failNextSave()
        await adapter.send(.refresh(result))
        try await waitUntil { await recorder.count == 1 }
        let firstDelivery = await recorder.delivery(at: 0)
        guard case let .persistenceFailed(accountID) = firstDelivery else {
            Issue.record("Expected a persistence delivery failure")
            collector.cancel()
            return
        }
        #expect(accountID == account.id)
        #expect(await store.currentState().snapshots.isEmpty)

        await adapter.send(.refresh(result))
        try await waitUntil { await recorder.count == 2 }
        await collector.value
        let secondDelivery = await recorder.delivery(at: 1)
        guard case let .applied(outcome) = secondDelivery else {
            Issue.record("Expected recovery to apply the provider update")
            return
        }
        #expect(outcome.accountID == account.id)
        #expect(await store.currentState().snapshots.map(\.usedFraction) == [0.64])
        await adapter.finish()
    }

    private struct TwoAccountStore {
        let store: PaceStore
        let personal: DiscoveredAccount
        let work: DiscoveredAccount
    }

    private func makeTwoAccountStore() async throws -> TwoAccountStore {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let personal = TestSupport.discoveredAccount(
            subjectID: "claude-personal",
            displayName: "Personal",
        )
        let work = TestSupport.discoveredAccount(
            subjectID: "claude-work",
            displayName: "Work",
        )
        try await store.register(
            personal,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        try await store.register(
            work,
            id: TestSupport.workID,
            addedAt: TestSupport.referenceDate,
        )
        return TwoAccountStore(store: store, personal: personal, work: work)
    }
}

private actor StreamingTestAdapter: ProviderUpdateStreamingAdapter {
    nonisolated let providerID = ProviderID.claude
    nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: true,
    )

    private let discoveredAccount: DiscoveredAccount
    private let stream: AsyncStream<ProviderUpdate>
    private let continuation: AsyncStream<ProviderUpdate>.Continuation

    init(discoveredAccount: DiscoveredAccount) {
        self.discoveredAccount = discoveredAccount
        let streamPair = AsyncStream<ProviderUpdate>.makeStream(
            bufferingPolicy: .bufferingNewest(8),
        )
        stream = streamPair.stream
        continuation = streamPair.continuation
    }

    func discoverAccounts() -> [DiscoveredAccount] {
        [discoveredAccount]
    }

    func refresh(_: ProviderAccount) throws(ProviderFailure) -> ProviderRefreshResult {
        throw .failed(code: "manual-refresh-not-used")
    }

    func updates(for _: ProviderAccount) -> AsyncStream<ProviderUpdate> {
        stream
    }

    func send(_ update: ProviderUpdate) {
        continuation.yield(update)
    }

    func finish() {
        continuation.finish()
    }
}

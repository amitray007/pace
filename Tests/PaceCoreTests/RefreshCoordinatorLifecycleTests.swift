@testable import PaceCore
import Testing

@Suite("Refresh coordinator lifecycle")
struct RefreshCoordinatorLifecycleTests {
    @Test
    func `shuts down lifecycle adapters explicitly`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let adapter = LifecycleTestAdapter()
        let coordinator = try RefreshCoordinator(store: store, adapters: [adapter])

        await coordinator.shutdownAdapters()

        #expect(await adapter.shutdownCount == 1)
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
    func `shutdown waits for active account monitors`() async throws {
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
        let adapter = LifecycleStreamingTestAdapter(discoveredAccount: discovered)
        let coordinator = try RefreshCoordinator(store: store, adapters: [adapter])
        let updates = await coordinator.updateStream()
        let collector = Task {
            for await _ in updates {}
        }
        try await waitUntil {
            await adapter.subscriptionCount(for: account.id) == 1
        }

        collector.cancel()
        await coordinator.shutdownUpdates()
        await collector.value

        #expect(await adapter.terminationCount(for: account.id) == 1)
    }
}

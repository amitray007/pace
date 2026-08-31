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

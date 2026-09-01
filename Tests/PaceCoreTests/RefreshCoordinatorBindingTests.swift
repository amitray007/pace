import Foundation
@testable import PaceCore
import Testing

@Suite("Refresh coordinator credential routing")
struct RefreshCoordinatorBindingTests {
    @Test
    func `keeps retained simulation dormant and restores it after live removal`() async throws {
        let setup = try await makeSetup(providerID: .grok)
        let connectionBeforeRefresh = await connectionState(
            for: TestSupport.personalID,
            in: setup.store,
        )
        let liveAdapter = try makeLiveAdapter(setup)
        let liveRuntime = try RefreshCoordinator(store: setup.store, adapters: [liveAdapter])

        let liveOutcomes = try await liveRuntime.refreshAll()
        let liveState = await setup.store.currentState()

        #expect(liveOutcomes.map(\.accountID) == [TestSupport.workID])
        #expect(await liveAdapter.refreshCount(for: TestSupport.personalID) == 0)
        #expect(await liveAdapter.refreshCount(for: TestSupport.workID) == 1)
        #expect(liveState.accounts.first(where: {
            $0.id == TestSupport.personalID
        })?.connectionState == connectionBeforeRefresh)

        _ = try await setup.store.removeAccount(TestSupport.workID)
        let fallbackAdapter = try makeFallbackAdapter(setup)
        let fallbackRuntime = try RefreshCoordinator(
            store: setup.store,
            adapters: [fallbackAdapter],
        )
        let fallbackOutcomes = try await fallbackRuntime.refreshAll()
        let fallbackState = await setup.store.currentState()

        #expect(fallbackOutcomes.map(\.accountID) == [TestSupport.personalID])
        #expect(fallbackState.accounts.first?.connectionState == .connected(
            lastVerifiedAt: TestSupport.referenceDate,
        ))
        #expect(fallbackState.snapshots.first?.usedFraction == 0.41)
    }

    @Test
    func `does not monitor retained simulation through live adapter`() async throws {
        let setup = try await makeSetup(providerID: .claude)
        let adapter = BindingStreamingAdapter(discoveredAccount: setup.live)
        let coordinator = try RefreshCoordinator(store: setup.store, adapters: [adapter])

        _ = await coordinator.updateStream()
        try await waitUntil { await adapter.monitoredAccountIDs.count == 1 }

        #expect(await adapter.monitoredAccountIDs == [TestSupport.workID])
        await coordinator.shutdownUpdates()
    }

    private func makeSetup(providerID: ProviderID) async throws -> BindingSetup {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let simulated = TestSupport.discoveredAccount(
            providerID: providerID,
            subjectID: "\(providerID.rawValue)-simulated",
            displayName: "Fixture",
        )
        let live = TestSupport.discoveredAccount(
            providerID: providerID,
            subjectID: "\(providerID.rawValue)-live",
            displayName: "Personal",
            credentialBinding: .providerProfile(
                directory: URL(
                    filePath: "/profiles/\(providerID.rawValue)/personal",
                    directoryHint: .isDirectory,
                ),
                ownership: .existing,
            ),
        )
        try await store.register(
            simulated,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        try await store.register(
            live,
            id: TestSupport.workID,
            addedAt: TestSupport.referenceDate,
        )
        return BindingSetup(store: store, simulated: simulated, live: live)
    }

    private func makeLiveAdapter(_ setup: BindingSetup) throws -> SimulatedProviderAdapter {
        let snapshot = try TestSupport.snapshot(
            providerID: setup.live.providerID,
            accountID: TestSupport.workID,
            usedFraction: 0.27,
        )
        return SimulatedProviderAdapter(
            providerID: setup.live.providerID,
            discoveredAccounts: [setup.live],
            refreshSteps: [
                TestSupport.workID: [
                    .result(TestSupport.result(
                        for: setup.live,
                        accountID: TestSupport.workID,
                        snapshots: [snapshot],
                    )),
                ],
            ],
        )
    }

    private func makeFallbackAdapter(_ setup: BindingSetup) throws -> SimulatedProviderAdapter {
        let snapshot = try TestSupport.snapshot(
            providerID: setup.simulated.providerID,
            accountID: TestSupport.personalID,
            usedFraction: 0.41,
        )
        return SimulatedProviderAdapter(
            providerID: setup.simulated.providerID,
            discoveredAccounts: [setup.simulated],
            refreshSteps: [
                TestSupport.personalID: [
                    .result(TestSupport.result(
                        for: setup.simulated,
                        accountID: TestSupport.personalID,
                        snapshots: [snapshot],
                    )),
                ],
            ],
        )
    }

    private func connectionState(
        for accountID: AccountID,
        in store: PaceStore,
    ) async -> AccountConnectionState? {
        await store.currentState().accounts.first { $0.id == accountID }?.connectionState
    }
}

private struct BindingSetup {
    let store: PaceStore
    let simulated: DiscoveredAccount
    let live: DiscoveredAccount
}

private actor BindingStreamingAdapter: ProviderUpdateStreamingAdapter {
    nonisolated let providerID: ProviderID
    nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: true,
    )

    private let discoveredAccount: DiscoveredAccount
    private let stream: AsyncStream<ProviderUpdate>
    private(set) var monitoredAccountIDs: [AccountID] = []

    init(discoveredAccount: DiscoveredAccount) {
        self.discoveredAccount = discoveredAccount
        providerID = discoveredAccount.providerID
        stream = AsyncStream { _ in }
    }

    func discoverAccounts() -> [DiscoveredAccount] {
        [discoveredAccount]
    }

    func refresh(_: ProviderAccount) throws(ProviderFailure) -> ProviderRefreshResult {
        throw .failed(code: "manual-refresh-not-used")
    }

    func updates(for account: ProviderAccount) -> AsyncStream<ProviderUpdate> {
        monitoredAccountIDs.append(account.id)
        return stream
    }
}

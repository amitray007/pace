import Foundation
@testable import PaceCore
import Testing

@Suite("Simulated account retirement")
struct SimulatedAccountRetirementTests {
    private func makeStore() -> PaceStore {
        PaceStore(persistence: InMemoryPaceStatePersistence())
    }

    private func simulated(
        _ providerID: ProviderID,
        subject: String,
    ) -> DiscoveredAccount {
        TestSupport.discoveredAccount(
            providerID: providerID,
            subjectID: subject,
            displayName: "Demo \(subject)",
        )
    }

    private func live(
        _ providerID: ProviderID,
        subject: String,
    ) -> DiscoveredAccount {
        TestSupport.discoveredAccount(
            providerID: providerID,
            subjectID: subject,
            displayName: "Live \(subject)",
            credentialBinding: .keychain(service: "svc-\(subject)", account: subject),
        )
    }

    @Test
    func `a simulated account is retired once its provider has a real one`() async throws {
        let store = makeStore()
        let demo = try await store.register(simulated(.claude, subject: "demo"))
        _ = try await store.register(live(.claude, subject: "live"))

        let retired = try await store.retireSimulatedAccounts()

        #expect(retired.map(\.id) == [demo.id])
        let accounts = await store.currentState().accounts
        #expect(accounts.count == 1)
        #expect(accounts.first?.credentialBinding.isSimulated == false)
    }

    @Test
    func `retiring an account removes its stale snapshots`() async throws {
        // This is the point of the operation: nothing refreshes a simulated
        // account, so its snapshots keep the fixture date indefinitely.
        let store = makeStore()
        let demoAccount = simulated(.claude, subject: "demo")
        let demo = try await store.register(demoAccount)
        try await store.applyRefreshOutcomes([
            .success(
                accountID: demo.id,
                result: TestSupport.result(
                    for: demoAccount,
                    accountID: demo.id,
                    snapshots: [TestSupport.snapshot(accountID: demo.id)],
                ),
            ),
        ])
        #expect(await !store.currentState().snapshots.isEmpty)

        _ = try await store.register(live(.claude, subject: "live"))
        try await store.retireSimulatedAccounts()

        let snapshots = await store.currentState().snapshots
        #expect(snapshots.isEmpty)
    }

    @Test
    func `a provider without a real account keeps its demonstration data`() async throws {
        // Removing it would leave that provider's tab empty rather than
        // illustrative, which is worse than showing sample data.
        let store = makeStore()
        _ = try await store.register(simulated(.codex, subject: "demo"))
        _ = try await store.register(live(.claude, subject: "live"))

        let retired = try await store.retireSimulatedAccounts()

        #expect(retired.isEmpty)
        let accounts = await store.currentState().accounts
        #expect(accounts.count == 2)
    }

    @Test
    func `retirement moves the selection to the real account`() async throws {
        // The simulated account is registered first, so it holds the selection
        // until it is removed.
        let store = makeStore()
        _ = try await store.register(simulated(.claude, subject: "demo"))
        let liveAccount = try await store.register(live(.claude, subject: "live"))

        try await store.retireSimulatedAccounts()

        let selected = await store.selectedAccount(for: .claude)
        #expect(selected?.id == liveAccount.id)
    }

    @Test
    func `retiring twice is harmless`() async throws {
        let store = makeStore()
        _ = try await store.register(simulated(.claude, subject: "demo"))
        _ = try await store.register(live(.claude, subject: "live"))

        try await store.retireSimulatedAccounts()
        let second = try await store.retireSimulatedAccounts()

        #expect(second.isEmpty)
    }
}

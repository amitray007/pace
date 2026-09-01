import Foundation
@testable import PaceCore
import Testing

@Suite("Account coordinator")
struct AccountCoordinatorTests {
    @Test
    func `discovers without registering and adds only the selected candidate`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let personal = discoveredProfile(
            subjectID: "codex-personal",
            name: "Personal",
            path: "/profiles/codex/personal",
        )
        let work = discoveredProfile(
            subjectID: "codex-work",
            name: "Work",
            path: "/profiles/codex/work",
        )
        let adapter = try refreshingAdapter(personal: personal, work: work)
        let refreshCoordinator = try RefreshCoordinator(store: store, adapters: [adapter])
        let coordinator = AccountCoordinator(
            store: store,
            refreshCoordinator: refreshCoordinator,
        )

        let candidates = try await coordinator.discover(for: .codex)

        #expect(candidates.map(\.status) == [.available, .available])
        #expect(await store.accounts(for: .codex).isEmpty)
        #expect(await adapter.refreshCount(for: TestSupport.workID) == 0)

        let registered = try await coordinator.add(
            candidates[1],
            displayName: "Client",
            id: TestSupport.workID,
            addedAt: TestSupport.referenceDate,
        )
        #expect(registered.displayName == "Client")
        #expect(await store.accounts(for: .codex).map(\.id) == [TestSupport.workID])

        let outcome = try await coordinator.refresh(registered.id)
        #expect(outcome.accountID == registered.id)
        #expect(await adapter.refreshCount(for: registered.id) == 1)
        #expect(await store.currentState().snapshots.map(\.usedFraction) == [0.42])
    }

    @Test
    func `classifies registered identity and credential conflicts`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let original = discoveredProfile(
            subjectID: "codex-personal",
            name: "Personal",
            path: "/profiles/codex/personal",
        )
        try await store.register(
            original,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        let alreadyRegistered = original
        let credentialConflict = discoveredProfile(
            subjectID: "codex-other",
            name: "Changed profile",
            path: "/profiles/codex/personal",
        )
        let identityConflict = discoveredProfile(
            subjectID: "codex-personal",
            name: "Duplicate identity",
            path: "/profiles/codex/other",
        )
        let adapter = SimulatedProviderAdapter(
            providerID: .codex,
            discoveredAccounts: [alreadyRegistered, credentialConflict, identityConflict],
            refreshSteps: [:],
        )
        let refreshCoordinator = try RefreshCoordinator(store: store, adapters: [adapter])
        let coordinator = AccountCoordinator(
            store: store,
            refreshCoordinator: refreshCoordinator,
        )

        let candidates = try await coordinator.discover(for: .codex)

        #expect(candidates.map(\.status) == [
            .registered(accountID: TestSupport.personalID),
            .credentialInUse(accountID: TestSupport.personalID),
            .identityInUse(accountID: TestSupport.personalID),
        ])
        await #expect(
            throws: AccountCoordinatorError.candidateUnavailable(
                .registered(accountID: TestSupport.personalID),
            ),
        ) {
            try await coordinator.add(candidates[0])
        }
    }

    @Test
    func `renames disables reenables and removes through one account boundary`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let discovered = discoveredProfile(
            subjectID: "codex-personal",
            name: "Personal",
            path: "/profiles/codex/personal",
        )
        let adapter = SimulatedProviderAdapter(
            providerID: .codex,
            discoveredAccounts: [discovered],
            refreshSteps: [:],
        )
        let refreshCoordinator = try RefreshCoordinator(store: store, adapters: [adapter])
        let coordinator = AccountCoordinator(
            store: store,
            refreshCoordinator: refreshCoordinator,
        )
        let candidate = try #require(
            try await coordinator.discover(for: .codex).first,
        )
        let account = try await coordinator.add(
            candidate,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )

        try await coordinator.rename(account.id, to: "Main")
        try await coordinator.setEnabled(account.id, isEnabled: false)
        #expect(await store.accounts(for: .codex).isEmpty)
        #expect(await store.accounts(for: .codex, includeDisabled: true).first?
            .displayName == "Main")

        try await coordinator.setEnabled(account.id, isEnabled: true)
        #expect(await store.selectedAccount(for: .codex)?.id == account.id)

        let removed = try await coordinator.remove(account.id)
        #expect(removed.id == account.id)
        #expect(await store.accounts(for: .codex, includeDisabled: true).isEmpty)
    }

    @Test
    func `rejects a discovery result owned by another provider`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let wrongProvider = TestSupport.discoveredAccount(
            providerID: .claude,
            subjectID: "claude-personal",
            displayName: "Personal",
        )
        let adapter = MismatchedDiscoveryAdapter(discoveredAccount: wrongProvider)
        let refreshCoordinator = try RefreshCoordinator(store: store, adapters: [adapter])
        let coordinator = AccountCoordinator(
            store: store,
            refreshCoordinator: refreshCoordinator,
        )

        await #expect(
            throws: AccountCoordinatorError.providerMismatch(
                expected: .codex,
                actual: .claude,
            ),
        ) {
            _ = try await coordinator.discover(for: .codex)
        }
        #expect(await store.currentState().accounts.isEmpty)
    }

    private func discoveredProfile(
        subjectID: String,
        name: String,
        path: String,
    ) -> DiscoveredAccount {
        TestSupport.discoveredAccount(
            providerID: .codex,
            subjectID: subjectID,
            displayName: name,
            credentialBinding: .providerProfile(
                directory: URL(filePath: path, directoryHint: .isDirectory),
                ownership: .existing,
            ),
        )
    }

    private func refreshingAdapter(
        personal: DiscoveredAccount,
        work: DiscoveredAccount,
    ) throws -> SimulatedProviderAdapter {
        let snapshot = try TestSupport.snapshot(
            providerID: .codex,
            accountID: TestSupport.workID,
            usedFraction: 0.42,
        )
        let result = TestSupport.result(
            for: work,
            accountID: TestSupport.workID,
            snapshots: [snapshot],
        )
        return SimulatedProviderAdapter(
            providerID: .codex,
            discoveredAccounts: [personal, work],
            refreshSteps: [TestSupport.workID: [.result(result)]],
        )
    }
}

private struct MismatchedDiscoveryAdapter: ProviderAdapter {
    let providerID = ProviderID.codex
    let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: false,
    )
    let discoveredAccount: DiscoveredAccount

    func discoverAccounts() -> [DiscoveredAccount] {
        [discoveredAccount]
    }

    func refresh(_: ProviderAccount) throws(ProviderFailure) -> ProviderRefreshResult {
        throw .failed(code: "unused")
    }
}

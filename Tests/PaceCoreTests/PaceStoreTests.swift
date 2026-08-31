@testable import PaceCore
import Testing

@Suite("Pace store")
struct PaceStoreTests {
    @Test
    func `registers, names, orders, and selects accounts per provider`() async throws {
        let persistence = InMemoryPaceStatePersistence()
        let store = try await PaceStore.open(persistence: persistence)
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

        var accounts = await store.accounts(for: .claude)
        #expect(accounts.map(\.displayName) == ["Personal", "Work"])
        #expect(await store.selectedAccount(for: .claude)?.id == TestSupport.personalID)

        try await store.renameAccount(TestSupport.workID, to: "Acme")
        try await store.reorderAccounts(
            for: .claude,
            accountIDs: [TestSupport.workID, TestSupport.personalID],
        )
        try await store.selectAccount(TestSupport.workID, for: .claude)

        accounts = await store.accounts(for: .claude)
        #expect(accounts.map(\.displayName) == ["Acme", "Personal"])
        #expect(await store.selectedAccount(for: .claude)?.id == TestSupport.workID)
    }

    @Test
    func `rejects duplicate identities and display names`() async throws {
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

        await #expect(throws: AccountMutationError.self) {
            try await store.register(
                personal,
                id: TestSupport.workID,
                addedAt: TestSupport.referenceDate,
            )
        }

        let work = TestSupport.discoveredAccount(
            subjectID: "claude-work",
            displayName: "personal",
        )
        await #expect(throws: AccountMutationError.self) {
            try await store.register(
                work,
                id: TestSupport.workID,
                addedAt: TestSupport.referenceDate,
            )
        }
    }

    @Test
    func `disabling and removing an account reconciles shared selection`() async throws {
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
        try await store.replaceSnapshots(
            for: TestSupport.personalID,
            with: [TestSupport.snapshot(accountID: TestSupport.personalID)],
        )

        try await store.setAccount(TestSupport.personalID, isEnabled: false)
        #expect(await store.selectedAccount(for: .claude)?.id == TestSupport.workID)

        try await store.removeAccount(TestSupport.personalID)
        let state = await store.currentState()
        #expect(!state.accounts.contains(where: { $0.id == TestSupport.personalID }))
        #expect(!state.snapshots.contains(where: {
            $0.id.accountID == TestSupport.personalID
        }))
        #expect(await store.selectedAccount(for: .claude)?.id == TestSupport.workID)
    }

    @Test
    func `does not allow snapshots to cross account identities`() async throws {
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
        let wrongSnapshot = try TestSupport.snapshot(accountID: TestSupport.workID)

        await #expect(throws: AccountMutationError.self) {
            try await store.replaceSnapshots(
                for: TestSupport.personalID,
                with: [wrongSnapshot],
            )
        }
    }
}

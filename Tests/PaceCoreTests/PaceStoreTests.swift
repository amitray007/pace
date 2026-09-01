import Foundation
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

        try await registerTestAccounts(personal, work, in: store)

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
    func `rejects the same provider credential source under another identity`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let profile = URL(filePath: "/profiles/claude/personal", directoryHint: .isDirectory)
        let personal = TestSupport.discoveredAccount(
            subjectID: "claude-personal",
            displayName: "Personal",
            credentialBinding: .providerProfile(directory: profile, ownership: .existing),
        )
        try await store.register(
            personal,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        let changedIdentity = TestSupport.discoveredAccount(
            subjectID: "claude-other",
            displayName: "Other",
            credentialBinding: .providerProfile(
                directory: profile.deletingLastPathComponent().appending(path: "personal"),
                ownership: .paceManaged,
            ),
        )

        await #expect(
            throws: AccountMutationError.duplicateCredentialBinding(providerID: .claude),
        ) {
            try await store.register(
                changedIdentity,
                id: TestSupport.workID,
                addedAt: TestSupport.referenceDate,
            )
        }
    }

    @Test
    func `rejects the same keychain source under another identity`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let binding = CredentialBinding.keychain(service: "github-cli", account: "amit")
        let personal = TestSupport.discoveredAccount(
            providerID: .githubCopilot,
            subjectID: "github-100",
            displayName: "Personal",
            credentialBinding: binding,
        )
        try await store.register(
            personal,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        let changedIdentity = TestSupport.discoveredAccount(
            providerID: .githubCopilot,
            subjectID: "github-200",
            displayName: "Other",
            credentialBinding: binding,
        )

        await #expect(
            throws: AccountMutationError.duplicateCredentialBinding(providerID: .githubCopilot),
        ) {
            try await store.register(
                changedIdentity,
                id: TestSupport.workID,
                addedAt: TestSupport.referenceDate,
            )
        }
    }

    @Test
    func `rejects the same command line account with different casing`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let first = TestSupport.discoveredAccount(
            providerID: .githubCopilot,
            subjectID: "github:100",
            displayName: "Personal",
            credentialBinding: .commandLineAccount(
                tool: "github-cli:github.com",
                account: "AmitRay007",
                configurationDirectory: nil,
            ),
        )
        try await store.register(
            first,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        let duplicate = TestSupport.discoveredAccount(
            providerID: .githubCopilot,
            subjectID: "github:200",
            displayName: "Other",
            credentialBinding: .commandLineAccount(
                tool: "GITHUB-CLI:GITHUB.COM",
                account: "amitray007",
                configurationDirectory: nil,
            ),
        )

        await #expect(
            throws: AccountMutationError.duplicateCredentialBinding(
                providerID: .githubCopilot,
            ),
        ) {
            try await store.register(
                duplicate,
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

    @Test
    func `serializes durable mutations across concurrent account updates`() async throws {
        let persistence = SuspendingPaceStatePersistence()
        let store = try await PaceStore.open(persistence: persistence)
        let personal = TestSupport.discoveredAccount(
            subjectID: "claude-personal",
            displayName: "Personal",
        )
        let work = TestSupport.discoveredAccount(
            subjectID: "claude-work",
            displayName: "Work",
        )
        try await registerTestAccounts(personal, work, in: store)
        let baselineSaveCount = await persistence.saveCount
        await persistence.suspendSaves()

        let personalUpdate = Task {
            try await store.applyRefreshOutcomes([
                successfulOutcome(
                    for: personal,
                    accountID: TestSupport.personalID,
                    usedFraction: 0.31,
                ),
            ])
        }
        let workUpdate = Task {
            try await store.applyRefreshOutcomes([
                successfulOutcome(
                    for: work,
                    accountID: TestSupport.workID,
                    usedFraction: 0.72,
                ),
            ])
        }

        await persistence.waitForSaveCount(baselineSaveCount + 1)
        await persistence.releaseNextSave()
        await persistence.waitForSaveCount(baselineSaveCount + 2)
        await persistence.releaseNextSave()
        try await personalUpdate.value
        try await workUpdate.value

        let state = await store.currentState()
        let persistedState = await persistence.storedState
        #expect(Set(state.snapshots.map(\.id.accountID)) == [
            TestSupport.personalID,
            TestSupport.workID,
        ])
        #expect(persistedState == state)
    }
}

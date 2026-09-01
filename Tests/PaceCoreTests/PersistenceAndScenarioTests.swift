import Foundation
@testable import PaceCore
import Testing

@Suite("Persistence and deterministic scenarios")
struct PersistenceAndScenarioTests {
    @Test
    func `round-trips normalized state without credential secrets`() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "pace-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fileURL = directoryURL.appending(path: "state.json")
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let persistence = FilePaceStatePersistence(fileURL: fileURL)
        let store = try await PaceStore.open(persistence: persistence)
        let account = DiscoveredAccount(
            providerID: .claude,
            identity: ProviderIdentity(subjectID: "claude-personal"),
            suggestedDisplayName: "Personal",
            planName: "Claude Pro",
            credentialBinding: .claudeProfile(ClaudeCredentialBinding(
                configurationDirectory: URL(
                    filePath: "/profiles/claude-personal",
                    directoryHint: .isDirectory,
                ),
                secureStorageDirectory: URL(
                    filePath: "/secure/claude-personal",
                    directoryHint: .isDirectory,
                ),
                keychainService: "Claude Code-credentials-01234567",
                keychainAccount: "test-user",
                ownership: .paceManaged,
            )),
        )
        try await store.register(
            account,
            id: TestSupport.personalID,
            addedAt: TestSupport.referenceDate,
        )
        try await store.replaceSnapshots(
            for: TestSupport.personalID,
            with: [TestSupport.snapshot(accountID: TestSupport.personalID)],
        )
        let expectedState = await store.currentState()

        let reopenedStore = try await PaceStore.open(persistence: persistence)
        let reopenedState = await reopenedStore.currentState()
        let data = try Data(contentsOf: fileURL)
        let contents = try #require(String(data: data, encoding: .utf8))
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)

        #expect(reopenedState == expectedState)
        #expect(!contents.localizedCaseInsensitiveContains("accessToken"))
        #expect(!contents.localizedCaseInsensitiveContains("refreshToken"))
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test
    func `round-trips command line account binding without a token`() throws {
        let binding = CredentialBinding.commandLineAccount(
            tool: "github-cli:github.com",
            account: "amitray007",
            configurationDirectory: URL(
                filePath: "/profiles/github-cli",
                directoryHint: .isDirectory,
            ),
        )

        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(CredentialBinding.self, from: data)
        let contents = try #require(String(data: data, encoding: .utf8))

        #expect(decoded == binding)
        #expect(contents.contains("amitray007"))
        #expect(!contents.localizedCaseInsensitiveContains("token"))
    }

    @Test
    func `standard simulated scenario is stable and covers every planned provider`() async throws {
        let firstState = try await runStandardScenario()
        let secondState = try await runStandardScenario()

        #expect(firstState == secondState)
        #expect(firstState.accounts.count == 6)
        #expect(firstState.snapshots.count == 12)
        #expect(Set(firstState.accounts.map(\.providerID)) == Set([
            .claude,
            .codex,
            .cursor,
            .githubCopilot,
            .grok,
        ]))
        #expect(firstState.accounts.filter { $0.providerID == .claude }.count == 2)
    }

    private func runStandardScenario() async throws -> PaceState {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let scenario = try SimulatedScenarios.standard()
        try await scenario.seed(store)
        let coordinator = try RefreshCoordinator(store: store, adapters: scenario.adapters)
        try await coordinator.refreshAll()
        return await store.currentState()
    }
}

import Foundation
import PaceCore
import PaceProviders
import Testing

@Suite("Codex live smoke")
struct CodexLiveSmokeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PACE_LIVE_CODEX_TEST"] == "1"))
    func `reads the selected profile through the supported app server`() async throws {
        let environment = ProcessInfo.processInfo.environment
        let profileDirectory = environment["CODEX_HOME"].map { URL(filePath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex", directoryHint: .isDirectory)
        let adapter = CodexProviderAdapter(
            profiles: [
                CodexProfile(
                    directory: profileDirectory,
                    ownership: .existing,
                    displayName: "Live smoke",
                ),
            ],
        )

        let discovered = try await adapter.discoverAccounts()
        let account = try #require(discovered.first)
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let registered = try await store.register(account)
        let refreshed = try await adapter.refresh(registered)

        #expect(discovered.count == 1)
        #expect(account.providerID == .codex)
        #expect(refreshed.identity.subjectID == account.identity.subjectID)
        #expect(!refreshed.snapshots.isEmpty)
        #expect(refreshed.snapshots.allSatisfy { $0.id.accountID == registered.id })
    }
}

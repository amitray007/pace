import Foundation
import PaceCore
import PaceProviders
import Testing

@Suite("Grok live smoke")
struct GrokLiveSmokeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PACE_LIVE_GROK_TEST"] == "1"))
    func `reads selected profile without a running Grok process`() async throws {
        let environment = ProcessInfo.processInfo.environment
        let profileDirectory = environment["GROK_HOME"].map { URL(filePath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".grok", directoryHint: .isDirectory)
        let adapter = GrokProviderAdapter(profiles: [
            GrokProfile(
                directory: profileDirectory,
                ownership: .existing,
                displayName: "Live smoke",
            ),
        ])

        let discovered = try await adapter.discoverAccounts()
        let candidate = try #require(discovered.first)
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let account = try await store.register(candidate)
        let refreshed = try await adapter.refresh(account)

        #expect(discovered.count == 1)
        #expect(candidate.providerID == .grok)
        #expect(refreshed.identity.subjectID == candidate.identity.subjectID)
        #expect(!refreshed.snapshots.isEmpty)
        #expect(refreshed.snapshots.allSatisfy { $0.id.accountID == account.id })
    }
}

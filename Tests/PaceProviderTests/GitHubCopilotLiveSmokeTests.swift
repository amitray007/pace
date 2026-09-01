import Foundation
import PaceCore
import PaceProviders
import Testing

@Suite("GitHub Copilot live smoke")
struct GitHubCopilotLiveSmokeTests {
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["PACE_LIVE_GITHUB_COPILOT_TEST"] == "1",
    ))
    func `reads every selected git hub CLI account without editor or harness`() async throws {
        let logins = try await GitHubCopilotAccountOnboarding().availableLogins()
        let adapter = GitHubCopilotProviderAdapter(
            profiles: logins.map { GitHubCopilotProfile(githubLogin: $0) },
        )

        let discovered = try await adapter.discoverAccounts()
        #expect(discovered.count == logins.count)
        #expect(Set(discovered.map(\.identity.subjectID)).count == discovered.count)

        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        for candidate in discovered {
            let account = try await store.register(candidate)
            let refreshed = try await adapter.refresh(account)

            #expect(refreshed.identity == candidate.identity)
            #expect(refreshed.snapshots.allSatisfy { $0.id.accountID == account.id })
        }
    }
}

import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("GitHub Copilot account onboarding")
struct GitHubCopilotAccountOnboardingTests {
    @Test
    func `lists available git hub CLI logins`() async throws {
        let onboarding = GitHubCopilotAccountOnboarding(
            discoverAccounts: { _ in [
                GitHubCopilotTestSupport.profile("personal"),
                GitHubCopilotTestSupport.profile("work"),
            ] },
            makeAdapter: { _ in
                GitHubCopilotOnboardingAdapter(
                    profile: GitHubCopilotTestSupport.profile(),
                    identity: GitHubCopilotTestSupport.identity().providerIdentity,
                )
            },
        )

        #expect(try await onboarding.availableLogins() == ["personal", "work"])
    }

    @Test
    func `maps missing git hub CLI during account discovery`() async {
        let onboarding = makeDiscoveryFailureOnboarding(.cliUnavailable)

        await #expect(throws: ProviderFailure.unavailable(code: "github-cli-unavailable")) {
            try await onboarding.availableLogins()
        }
    }

    @Test
    func `maps malformed git hub CLI status during account discovery`() async {
        let onboarding = makeDiscoveryFailureOnboarding(.cliFailed)

        await #expect(throws: ProviderFailure.unavailable(code: "github-cli-failed")) {
            try await onboarding.availableLogins()
        }
    }

    @Test
    func `maps signed out git hub CLI during account discovery`() async {
        let onboarding = makeDiscoveryFailureOnboarding(.signedOut)

        await #expect(throws: ProviderFailure.signedOut) {
            try await onboarding.availableLogins()
        }
    }

    @Test
    func `adds selected login and retains simulation fallback`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        _ = try await store.register(DiscoveredAccount(
            providerID: .githubCopilot,
            identity: ProviderIdentity(subjectID: "simulated:github-copilot"),
            suggestedDisplayName: "Personal",
            planName: "Simulation",
            credentialBinding: .simulated,
        ))
        let identity = GitHubCopilotTestSupport.identity(userID: 202, login: "work")
        let onboarding = makeOnboarding(identity: identity.providerIdentity)

        let accountID = try await onboarding.addAccount(githubLogin: "work", to: store)
        let state = await store.currentState()
        let account = try #require(state.accounts.first { $0.id == accountID })

        #expect(account.identity == identity.providerIdentity)
        #expect(account.credentialBinding == GitHubCopilotTestSupport.profile("work")
            .credentialBinding)
        #expect(state.accounts.contains { $0.credentialBinding == .simulated })
        #expect(state.selections.first {
            $0.providerID == .githubCopilot
        }?.accountID == accountID)
    }

    @Test
    func `failed first refresh rolls back registration`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let onboarding = makeOnboarding(
            identity: GitHubCopilotTestSupport.identity().providerIdentity,
            refreshFailure: .signedOut,
        )

        await #expect(throws: ProviderFailure.signedOut) {
            try await onboarding.addAccount(githubLogin: "personal", to: store)
        }
        #expect(await store.currentState().accounts.isEmpty)
    }

    private func makeOnboarding(
        identity: ProviderIdentity,
        refreshFailure: ProviderFailure? = nil,
    ) -> GitHubCopilotAccountOnboarding {
        GitHubCopilotAccountOnboarding(
            discoverAccounts: { _ in [
                GitHubCopilotTestSupport.profile("personal"),
                GitHubCopilotTestSupport.profile("work"),
            ] },
            makeAdapter: { profile in
                GitHubCopilotOnboardingAdapter(
                    profile: profile,
                    identity: identity,
                    refreshFailure: refreshFailure,
                )
            },
        )
    }

    private func makeDiscoveryFailureOnboarding(
        _ failure: GitHubCopilotProviderError,
    ) -> GitHubCopilotAccountOnboarding {
        GitHubCopilotAccountOnboarding(
            discoverAccounts: { _ in throw failure },
            makeAdapter: { _ in
                GitHubCopilotOnboardingAdapter(
                    profile: GitHubCopilotTestSupport.profile(),
                    identity: GitHubCopilotTestSupport.identity().providerIdentity,
                )
            },
        )
    }
}

private struct GitHubCopilotOnboardingAdapter: ProviderAdapter {
    nonisolated let providerID = ProviderID.githubCopilot
    nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: false,
    )
    let profile: GitHubCopilotProfile
    let identity: ProviderIdentity
    let refreshFailure: ProviderFailure?

    init(
        profile: GitHubCopilotProfile,
        identity: ProviderIdentity,
        refreshFailure: ProviderFailure? = nil,
    ) {
        self.profile = profile
        self.identity = identity
        self.refreshFailure = refreshFailure
    }

    func discoverAccounts() -> [DiscoveredAccount] {
        [
            DiscoveredAccount(
                providerID: .githubCopilot,
                identity: identity,
                suggestedDisplayName: profile.githubLogin,
                planName: "Individual",
                credentialBinding: profile.credentialBinding,
            ),
        ]
    }

    func refresh(_: ProviderAccount) throws(ProviderFailure) -> ProviderRefreshResult {
        if let refreshFailure {
            throw refreshFailure
        }
        return ProviderRefreshResult(
            identity: identity,
            planName: "Individual",
            snapshots: [],
            verifiedAt: GitHubCopilotTestSupport.observedAt,
        )
    }
}

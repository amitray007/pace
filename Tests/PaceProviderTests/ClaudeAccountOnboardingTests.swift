import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Claude account onboarding")
struct ClaudeAccountOnboardingTests {
    @Test
    func `successful onboarding selects real account and retains simulation fallback`(
    ) async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        _ = try await store.register(DiscoveredAccount(
            providerID: .claude,
            identity: ProviderIdentity(subjectID: "simulated:claude"),
            suggestedDisplayName: "Personal",
            planName: "Simulation",
            credentialBinding: .simulated,
        ))
        let directory = URL(filePath: "/profiles/claude/work", directoryHint: .isDirectory)
        let identity = ClaudeTestSupport.identity()
        let onboarding = ClaudeAccountOnboarding { profile in
            ClaudeOnboardingAdapter(profile: profile, identity: identity.providerIdentity)
        }

        let accountID = try await onboarding.addProfile(at: directory, to: store)

        let state = await store.currentState()
        let account = try #require(state.accounts.first { $0.id == accountID })
        #expect(account.providerID == .claude)
        #expect(account.displayName == "account-a@example.invalid")
        #expect(state.accounts.contains { $0.credentialBinding == .simulated })
        #expect(state.selections.first { $0.providerID == .claude }?.accountID == accountID)
    }

    @Test
    func `failed first refresh removes new Claude registration`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let directory = URL(filePath: "/profiles/claude/signed-out", directoryHint: .isDirectory)
        let onboarding = ClaudeAccountOnboarding { profile in
            ClaudeOnboardingAdapter(
                profile: profile,
                identity: ClaudeTestSupport.identity().providerIdentity,
                refreshFailure: .signedOut,
            )
        }

        await #expect(throws: ProviderFailure.signedOut) {
            try await onboarding.addProfile(at: directory, to: store)
        }

        #expect(await store.currentState().accounts.isEmpty)
    }
}

private struct ClaudeOnboardingAdapter: ProviderAdapter {
    nonisolated let providerID = ProviderID.claude
    nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: false,
    )
    let profile: ClaudeProfile
    let identity: ProviderIdentity
    let refreshFailure: ProviderFailure?

    init(
        profile: ClaudeProfile,
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
                providerID: .claude,
                identity: identity,
                suggestedDisplayName: "Personal",
                planName: "Max 20x",
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
            planName: "Max 20x",
            snapshots: [],
            verifiedAt: ClaudeTestSupport.observedAt,
        )
    }
}

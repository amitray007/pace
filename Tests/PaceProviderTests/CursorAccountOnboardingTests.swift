import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Cursor account onboarding")
struct CursorAccountOnboardingTests {
    @Test
    func `successful onboarding selects real account and retains simulation fallback`(
    ) async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        _ = try await store.register(DiscoveredAccount(
            providerID: .cursor,
            identity: ProviderIdentity(subjectID: "simulated:cursor"),
            suggestedDisplayName: "Personal",
            planName: "Simulation",
            credentialBinding: .simulated,
        ))
        let profile = CursorTestSupport.profile("work")
        let identity = CursorTestSupport.identity(userID: "user-work")
        let onboarding = CursorAccountOnboarding { profile in
            CursorOnboardingAdapter(profile: profile, identity: identity.providerIdentity)
        }

        let accountID = try await onboarding.addProfile(profile, to: store)

        let state = await store.currentState()
        let account = try #require(state.accounts.first { $0.id == accountID })
        #expect(account.providerID == .cursor)
        #expect(account.displayName == "user-work@example.invalid")
        #expect(state.accounts.contains { $0.credentialBinding == .simulated })
        #expect(state.selections.first { $0.providerID == .cursor }?.accountID == accountID)
    }

    @Test
    func `failed first refresh removes new Cursor registration`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let profile = CursorTestSupport.profile("signed-out")
        let onboarding = CursorAccountOnboarding { profile in
            CursorOnboardingAdapter(
                profile: profile,
                identity: CursorTestSupport.identity().providerIdentity,
                refreshFailure: .signedOut,
            )
        }

        await #expect(throws: ProviderFailure.signedOut) {
            try await onboarding.addProfile(profile, to: store)
        }

        #expect(await store.currentState().accounts.isEmpty)
    }
}

private struct CursorOnboardingAdapter: ProviderAdapter {
    nonisolated let providerID = ProviderID.cursor
    nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: false,
    )
    let profile: CursorProfile
    let identity: ProviderIdentity
    let refreshFailure: ProviderFailure?

    init(
        profile: CursorProfile,
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
                providerID: .cursor,
                identity: identity,
                suggestedDisplayName: "Personal",
                planName: "Team",
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
            planName: "Team",
            snapshots: [],
            verifiedAt: CursorTestSupport.observedAt,
        )
    }
}

import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Grok account onboarding")
struct GrokAccountOnboardingTests {
    @Test
    func `successful onboarding selects real account and retains simulation fallback`(
    ) async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        _ = try await store.register(DiscoveredAccount(
            providerID: .grok,
            identity: ProviderIdentity(subjectID: "simulated:grok"),
            suggestedDisplayName: "Personal",
            planName: "Simulation",
            credentialBinding: .simulated,
        ))
        let profile = URL(filePath: "/profiles/grok/work", directoryHint: .isDirectory)
        let identity = GrokTestSupport.identity()
        let onboarding = GrokAccountOnboarding { requestedProfile in
            GrokOnboardingAdapter(
                profile: requestedProfile,
                identity: identity.providerIdentity,
            )
        }

        let accountID = try await onboarding.addProfile(at: profile, to: store)

        let state = await store.currentState()
        let account = try #require(state.accounts.first { $0.id == accountID })
        #expect(account.providerID == .grok)
        #expect(account.displayName == "user-a@example.invalid")
        #expect(state.accounts.contains { $0.credentialBinding == .simulated })
        #expect(state.selections.first { $0.providerID == .grok }?.accountID == accountID)
    }

    @Test
    func `failed first refresh removes new Grok registration`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let profile = URL(filePath: "/profiles/grok/signed-out", directoryHint: .isDirectory)
        let onboarding = GrokAccountOnboarding { requestedProfile in
            GrokOnboardingAdapter(
                profile: requestedProfile,
                identity: GrokTestSupport.identity().providerIdentity,
                refreshFailure: .signedOut,
            )
        }

        await #expect(throws: ProviderFailure.signedOut) {
            try await onboarding.addProfile(at: profile, to: store)
        }

        #expect(await store.currentState().accounts.isEmpty)
    }
}

private struct GrokOnboardingAdapter: ProviderAdapter {
    nonisolated let providerID = ProviderID.grok
    nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: false,
    )
    let profile: GrokProfile
    let identity: ProviderIdentity
    let refreshFailure: ProviderFailure?

    init(
        profile: GrokProfile,
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
                providerID: .grok,
                identity: identity,
                suggestedDisplayName: "Personal",
                planName: "SuperGrok",
                credentialBinding: .providerProfile(
                    directory: profile.directory,
                    ownership: profile.ownership,
                ),
            ),
        ]
    }

    func refresh(_: ProviderAccount) throws(ProviderFailure) -> ProviderRefreshResult {
        if let refreshFailure {
            throw refreshFailure
        }
        return ProviderRefreshResult(
            identity: identity,
            planName: "SuperGrok",
            snapshots: [],
            verifiedAt: GrokTestSupport.observedAt,
        )
    }
}

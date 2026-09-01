import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Codex account onboarding")
struct CodexAccountOnboardingTests {
    @Test
    func `failed first refresh removes a newly registered account`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let simulated = try await registerSimulatedAccount(in: store)
        let profile = profileURL("failed-new")
        let recorder = ShutdownRecorder()
        let onboarding = onboarding(refresh: .failure(.signedOut), recorder: recorder)

        await #expect(throws: ProviderFailure.signedOut) {
            try await onboarding.addProfile(at: profile, to: store)
        }

        let state = await store.currentState()
        #expect(state.accounts.map(\.id) == [simulated.id])
        #expect(await recorder.count == 1)
    }

    @Test
    func `failed first refresh restores a disabled registered account`() async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let profile = profileURL("failed-existing")
        let existing = try await store.register(discoveredAccount(profile: profile))
        try await store.setAccount(existing.id, isEnabled: false)
        let onboarding = onboarding(refresh: .failure(.signedOut))

        await #expect(throws: ProviderFailure.signedOut) {
            try await onboarding.addProfile(at: profile, to: store)
        }

        let account = await store.currentState().accounts.first { $0.id == existing.id }
        #expect(account?.isEnabled == false)
    }

    @Test
    func `successful onboarding keeps simulation and resolves a duplicate default name`(
    ) async throws {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        _ = try await registerSimulatedAccount(in: store)
        let profile = profileURL("work")
        let onboarding = onboarding(refresh: .success(()))

        let accountID = try await onboarding.addProfile(at: profile, to: store)

        let state = await store.currentState()
        let account = try #require(state.accounts.first { $0.id == accountID })
        #expect(account.displayName == "person@example.invalid")
        #expect(state.accounts.contains { $0.credentialBinding == .simulated })
        #expect(state.selections.first { $0.providerID == .codex }?.accountID == accountID)
    }

    private func onboarding(
        refresh: Result<Void, ProviderFailure>,
        recorder: ShutdownRecorder = ShutdownRecorder(),
    ) -> CodexAccountOnboarding {
        CodexAccountOnboarding { requestedProfile in
            TestCodexOnboardingAdapter(
                discovered: discoveredAccount(profile: requestedProfile.directory),
                refresh: refresh,
                recorder: recorder,
            )
        }
    }

    private func discoveredAccount(profile: URL) -> DiscoveredAccount {
        DiscoveredAccount(
            providerID: .codex,
            identity: ProviderIdentity(
                subjectID: "chatgpt:person@example.invalid",
                email: "person@example.invalid",
            ),
            suggestedDisplayName: "Personal",
            planName: "ChatGPT Plus",
            credentialBinding: .providerProfile(directory: profile, ownership: .existing),
        )
    }

    private func registerSimulatedAccount(in store: PaceStore) async throws -> ProviderAccount {
        try await store.register(
            DiscoveredAccount(
                providerID: .codex,
                identity: ProviderIdentity(subjectID: "simulated:codex"),
                suggestedDisplayName: "Personal",
                planName: "Simulation",
                credentialBinding: .simulated,
            ),
        )
    }

    private func profileURL(_ name: String) -> URL {
        URL(filePath: "/profiles/codex/\(name)", directoryHint: .isDirectory)
    }
}

private struct TestCodexOnboardingAdapter: ProviderAdapterLifecycle {
    nonisolated let providerID = ProviderID.codex
    nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: false,
    )
    let discovered: DiscoveredAccount
    let refresh: Result<Void, ProviderFailure>
    let recorder: ShutdownRecorder

    func discoverAccounts() -> [DiscoveredAccount] {
        [discovered]
    }

    func refresh(_ account: ProviderAccount) throws(ProviderFailure) -> ProviderRefreshResult {
        switch refresh {
        case .success:
            return ProviderRefreshResult(
                identity: account.identity,
                planName: "ChatGPT Plus",
                snapshots: [],
                verifiedAt: Date(timeIntervalSince1970: 1_788_134_400),
            )
        case let .failure(failure):
            throw failure
        }
    }

    func shutdown() async {
        await recorder.record()
    }
}

private actor ShutdownRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

import Foundation
import PaceCore

public typealias ClaudeAccountOnboardingError = ProviderProfileAccountOnboardingError

public struct ClaudeAccountOnboarding: Sendable {
    private let makeAdapter: @Sendable (ClaudeProfile) -> any ProviderAdapter

    public init() {
        makeAdapter = { ClaudeProviderAdapter(profiles: [$0]) }
    }

    init(makeAdapter: @escaping @Sendable (ClaudeProfile) -> any ProviderAdapter) {
        self.makeAdapter = makeAdapter
    }

    public func addProfile(
        at directory: URL,
        to store: PaceStore,
    ) async throws -> AccountID {
        try await addProfile(
            ClaudeProfile(directory: directory, ownership: .existing),
            to: store,
        )
    }

    public func addProfile(
        _ profile: ClaudeProfile,
        to store: PaceStore,
    ) async throws -> AccountID {
        let expectedBinding = profile.credentialBinding
        return try await ProviderAccountOnboarding(providerID: .claude).addAccount(
            with: makeAdapter(profile),
            to: store,
        ) { account in
            account.credentialBinding == expectedBinding
        }
    }
}

import Foundation
import PaceCore

public typealias CursorAccountOnboardingError = ProviderProfileAccountOnboardingError

public struct CursorAccountOnboarding: Sendable {
    private let makeAdapter: @Sendable (CursorProfile) -> any ProviderAdapter

    public init() {
        makeAdapter = { CursorProviderAdapter(profiles: [$0]) }
    }

    init(makeAdapter: @escaping @Sendable (CursorProfile) -> any ProviderAdapter) {
        self.makeAdapter = makeAdapter
    }

    public func addCurrentProfile(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        to store: PaceStore,
    ) async throws -> AccountID {
        try await addProfile(CursorProfile.current(homeDirectory: homeDirectory), to: store)
    }

    public func addIsolatedProfile(
        at homeDirectory: URL,
        to store: PaceStore,
    ) async throws -> AccountID {
        try await addProfile(CursorProfile.isolated(homeDirectory: homeDirectory), to: store)
    }

    public func addProfile(
        _ profile: CursorProfile,
        to store: PaceStore,
    ) async throws -> AccountID {
        let expectedBinding = profile.credentialBinding
        return try await ProviderAccountOnboarding(providerID: .cursor).addAccount(
            with: makeAdapter(profile),
            to: store,
        ) { account in
            account.credentialBinding == expectedBinding
        }
    }
}

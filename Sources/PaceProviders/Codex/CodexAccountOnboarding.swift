import Foundation
import PaceCore

public typealias CodexAccountOnboardingError = ProviderProfileAccountOnboardingError

public struct CodexAccountOnboarding: Sendable {
    private let onboarding: ProviderProfileAccountOnboarding

    public init() {
        onboarding = ProviderProfileAccountOnboarding(providerID: .codex) { directory in
            CodexProviderAdapter(profiles: [
                CodexProfile(directory: directory, ownership: .existing),
            ])
        }
    }

    init(
        makeAdapter: @escaping @Sendable (CodexProfile) -> any ProviderAdapterLifecycle,
    ) {
        onboarding = ProviderProfileAccountOnboarding(providerID: .codex) { directory in
            makeAdapter(CodexProfile(directory: directory, ownership: .existing))
        }
    }

    public func addProfile(
        at directory: URL,
        to store: PaceStore,
    ) async throws -> AccountID {
        try await onboarding.addProfile(at: directory, to: store)
    }
}

import Foundation
import PaceCore

public typealias GrokAccountOnboardingError = ProviderProfileAccountOnboardingError

public struct GrokAccountOnboarding: Sendable {
    private let onboarding: ProviderProfileAccountOnboarding

    public init() {
        onboarding = ProviderProfileAccountOnboarding(providerID: .grok) { directory in
            GrokProviderAdapter(profiles: [
                GrokProfile(directory: directory, ownership: .existing),
            ])
        }
    }

    init(
        makeAdapter: @escaping @Sendable (GrokProfile) -> any ProviderAdapter,
    ) {
        onboarding = ProviderProfileAccountOnboarding(providerID: .grok) { directory in
            makeAdapter(GrokProfile(directory: directory, ownership: .existing))
        }
    }

    public func addProfile(
        at directory: URL,
        to store: PaceStore,
    ) async throws -> AccountID {
        try await onboarding.addProfile(at: directory, to: store)
    }
}

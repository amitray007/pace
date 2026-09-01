import Foundation
import PaceCore

public struct GitHubCopilotAccountOnboarding: Sendable {
    private let discoverAccounts: @Sendable (URL?) async throws -> [GitHubCopilotProfile]
    private let makeAdapter: @Sendable (GitHubCopilotProfile) -> any ProviderAdapter

    public init() {
        discoverAccounts = { configurationDirectory in
            try await GitHubCLIAccountDiscovery(
                configurationDirectory: configurationDirectory,
            ).profiles()
        }
        makeAdapter = { profile in
            GitHubCopilotProviderAdapter(profiles: [profile])
        }
    }

    init(
        discoverAccounts: @escaping @Sendable (URL?) async throws -> [GitHubCopilotProfile],
        makeAdapter: @escaping @Sendable (GitHubCopilotProfile) -> any ProviderAdapter,
    ) {
        self.discoverAccounts = discoverAccounts
        self.makeAdapter = makeAdapter
    }

    public func availableLogins(
        configurationDirectory: URL? = nil,
    ) async throws -> [String] {
        do {
            return try await discoverAccounts(configurationDirectory).map(\.githubLogin)
        } catch let error as GitHubCopilotProviderError {
            throw GitHubCopilotFailureMapper.providerFailure(for: error, now: Date())
        }
    }

    public func addAccount(
        githubLogin: String,
        configurationDirectory: URL? = nil,
        to store: PaceStore,
    ) async throws -> AccountID {
        let profile = GitHubCopilotProfile(
            githubLogin: githubLogin,
            configurationDirectory: configurationDirectory,
        )
        guard GitHubCLICredentialLoader.isValidLogin(profile.githubLogin) else {
            throw GitHubCopilotProviderError.invalidProfile
        }
        return try await ProviderAccountOnboarding(providerID: .githubCopilot).addAccount(
            with: makeAdapter(profile),
            to: store,
        ) { account in
            account.credentialBinding == profile.credentialBinding
        }
    }
}

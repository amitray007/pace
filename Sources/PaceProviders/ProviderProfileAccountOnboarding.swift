import Foundation
import PaceCore

public enum ProviderProfileAccountOnboardingError: Error, Equatable, Sendable {
    case identityAlreadyRegistered
    case profileIdentityChanged
    case profileNotDiscovered
}

struct ProviderProfileAccountOnboarding: Sendable {
    private let providerID: ProviderID
    private let makeAdapter: @Sendable (URL) -> any ProviderAdapter

    init(
        providerID: ProviderID,
        makeAdapter: @escaping @Sendable (URL) -> any ProviderAdapter,
    ) {
        self.providerID = providerID
        self.makeAdapter = makeAdapter
    }

    func addProfile(
        at directory: URL,
        to store: PaceStore,
    ) async throws -> AccountID {
        let canonicalDirectory = directory.resolvingSymlinksInPath()
        let adapter = makeAdapter(canonicalDirectory)
        return try await ProviderAccountOnboarding(providerID: providerID).addAccount(
            with: adapter,
            to: store,
        ) { account in
            account.credentialBinding.profileDirectory?.resolvingSymlinksInPath()
                == canonicalDirectory
        }
    }
}

struct ProviderAccountOnboarding: Sendable {
    private let providerID: ProviderID

    init(providerID: ProviderID) {
        self.providerID = providerID
    }

    func addAccount(
        with adapter: any ProviderAdapter,
        to store: PaceStore,
        matching matches: @Sendable (DiscoveredAccount) -> Bool,
    ) async throws -> AccountID {
        let runtime = try RefreshCoordinator(store: store, adapters: [adapter])
        let coordinator = AccountCoordinator(store: store, refreshCoordinator: runtime)

        do {
            let candidate = try await discoverAccount(with: coordinator, matching: matches)
            let registration = try await register(
                candidate,
                with: coordinator,
                store: store,
            )
            do {
                let outcome = try await coordinator.refresh(registration.accountID)
                guard case .success = outcome else {
                    guard case let .failure(_, failure) = outcome else {
                        throw ProviderProfileAccountOnboardingError.profileNotDiscovered
                    }
                    throw failure
                }
                try await store.selectAccount(registration.accountID, for: providerID)
                await runtime.shutdownAdapters()
                return registration.accountID
            } catch {
                try await rollback(registration, with: coordinator)
                throw error
            }
        } catch {
            await runtime.shutdownAdapters()
            throw error
        }
    }

    private func discoverAccount(
        with coordinator: AccountCoordinator,
        matching matches: @Sendable (DiscoveredAccount) -> Bool,
    ) async throws -> AccountDiscoveryCandidate {
        let candidates = try await coordinator.discover(for: providerID)
        guard let candidate = candidates.first(where: { matches($0.account) }) else {
            throw ProviderProfileAccountOnboardingError.profileNotDiscovered
        }
        return candidate
    }

    private func register(
        _ candidate: AccountDiscoveryCandidate,
        with coordinator: AccountCoordinator,
        store: PaceStore,
    ) async throws -> ProfileRegistration {
        switch candidate.status {
        case .available:
            let displayName = await uniqueDisplayName(for: candidate.account, in: store)
            return try await .added(coordinator.add(candidate, displayName: displayName).id)
        case let .registered(existingAccountID):
            let wasEnabled = await store.currentState().accounts.first {
                $0.id == existingAccountID
            }?.isEnabled ?? true
            try await coordinator.setEnabled(existingAccountID, isEnabled: true)
            return wasEnabled ? .unchanged(existingAccountID) : .reenabled(existingAccountID)
        case .credentialInUse:
            throw ProviderProfileAccountOnboardingError.profileIdentityChanged
        case .identityInUse:
            throw ProviderProfileAccountOnboardingError.identityAlreadyRegistered
        }
    }

    private func rollback(
        _ registration: ProfileRegistration,
        with coordinator: AccountCoordinator,
    ) async throws {
        switch registration {
        case let .added(accountID):
            _ = try await coordinator.remove(accountID)
        case let .reenabled(accountID):
            try await coordinator.setEnabled(accountID, isEnabled: false)
        case .unchanged:
            break
        }
    }

    private func uniqueDisplayName(
        for discoveredAccount: DiscoveredAccount,
        in store: PaceStore,
    ) async -> String {
        let existingNames = await Set(
            store.accounts(for: discoveredAccount.providerID, includeDisabled: true)
                .map { $0.displayName.lowercased() },
        )
        let preferredName = discoveredAccount.suggestedDisplayName
        guard existingNames.contains(preferredName.lowercased()) else {
            return preferredName
        }
        if let email = discoveredAccount.identity.email {
            if !existingNames.contains(email.lowercased()) {
                return email
            }
        }
        var suffix = 2
        while existingNames.contains("\(preferredName) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(preferredName) \(suffix)"
    }
}

private enum ProfileRegistration {
    case added(AccountID)
    case reenabled(AccountID)
    case unchanged(AccountID)

    var accountID: AccountID {
        switch self {
        case let .added(accountID), let .reenabled(accountID), let .unchanged(accountID):
            accountID
        }
    }
}

private extension CredentialBinding {
    var profileDirectory: URL? {
        switch self {
        case let .claudeProfile(binding):
            binding.configurationDirectory
        case let .providerProfile(directory, _):
            directory
        default:
            nil
        }
    }
}

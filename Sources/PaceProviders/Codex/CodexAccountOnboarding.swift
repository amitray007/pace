import Foundation
import PaceCore

public enum CodexAccountOnboardingError: Error, Equatable, Sendable {
    case identityAlreadyRegistered
    case profileIdentityChanged
    case profileNotDiscovered
}

public struct CodexAccountOnboarding: Sendable {
    private let makeAdapter: @Sendable (CodexProfile) -> any ProviderAdapterLifecycle

    public init() {
        makeAdapter = { CodexProviderAdapter(profiles: [$0]) }
    }

    init(
        makeAdapter: @escaping @Sendable (CodexProfile) -> any ProviderAdapterLifecycle,
    ) {
        self.makeAdapter = makeAdapter
    }

    public func addProfile(
        at directory: URL,
        to store: PaceStore,
    ) async throws -> AccountID {
        let profile = CodexProfile(
            directory: directory.resolvingSymlinksInPath(),
            ownership: .existing,
        )
        let adapter = makeAdapter(profile)
        let runtime = try RefreshCoordinator(store: store, adapters: [adapter])
        let coordinator = AccountCoordinator(store: store, refreshCoordinator: runtime)

        do {
            let candidate = try await discoverProfile(profile, with: coordinator)
            let registration = try await register(
                candidate,
                with: coordinator,
                store: store,
            )
            do {
                let outcome = try await coordinator.refresh(registration.accountID)
                guard case .success = outcome else {
                    guard case let .failure(_, failure) = outcome else {
                        throw CodexAccountOnboardingError.profileNotDiscovered
                    }
                    throw failure
                }
                try await store.selectAccount(registration.accountID, for: .codex)
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

    private func discoverProfile(
        _ profile: CodexProfile,
        with coordinator: AccountCoordinator,
    ) async throws -> AccountDiscoveryCandidate {
        let candidates = try await coordinator.discover(for: .codex)
        let canonicalDirectory = profile.directory.resolvingSymlinksInPath()
        guard let candidate = candidates.first(where: {
            $0.account.credentialBinding.profileDirectory?.resolvingSymlinksInPath()
                == canonicalDirectory
        }) else {
            throw CodexAccountOnboardingError.profileNotDiscovered
        }
        return candidate
    }

    private func register(
        _ candidate: AccountDiscoveryCandidate,
        with coordinator: AccountCoordinator,
        store: PaceStore,
    ) async throws -> Registration {
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
            throw CodexAccountOnboardingError.profileIdentityChanged
        case .identityInUse:
            throw CodexAccountOnboardingError.identityAlreadyRegistered
        }
    }

    private func rollback(
        _ registration: Registration,
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

private enum Registration {
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
        guard case let .providerProfile(directory, _) = self else {
            return nil
        }
        return directory
    }
}

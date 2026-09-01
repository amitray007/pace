import Foundation
import PaceCore
import PaceProviders

extension PacePresentationModel {
    var dataSourceDescription: String {
        let liveProviders = Set(state.accounts.compactMap { account -> ProviderID? in
            guard !account.credentialBinding.isSimulated else {
                return nil
            }
            return account.providerID
        })
        let hasSimulation = state.accounts.contains { $0.credentialBinding.isSimulated }
        if liveProviders == [.codex], hasSimulation {
            return "Live Codex; other providers simulated"
        }
        if !liveProviders.isEmpty {
            return "Live provider accounts"
        }
        return state.accounts.isEmpty ? "No accounts configured" : "Deterministic simulation"
    }

    func managedAccounts(for providerID: ProviderID) -> [ProviderAccount] {
        state.accounts
            .filter {
                $0.providerID == providerID && !$0.credentialBinding.isSimulated
            }
            .sorted { lhs, rhs in
                lhs.order == rhs.order ? lhs.addedAt < rhs.addedAt : lhs.order < rhs.order
            }
    }

    func addDefaultCodexAccount() async {
        await addCodexProfile(at: defaultCodexProfileDirectory)
    }

    func addCodexProfile(at directory: URL) async {
        guard !isReferencePreview, !isLoading, !isManagingAccounts, !isRefreshing,
              let store, let scenario = simulatedScenario
        else {
            return
        }
        guard Self.directoryExists(directory) else {
            accountActionError = "The selected Codex profile folder does not exist."
            return
        }

        isManagingAccounts = true
        defer { isManagingAccounts = false }
        accountActionError = nil
        await shutdownProviderRuntime()

        do {
            _ = try await CodexAccountOnboarding().addProfile(
                at: directory,
                to: store,
            )
            try await configureProviderRuntime(
                store: store,
                scenario: scenario,
                refreshAll: false,
            )
            state = await store.currentState()
            activeProviderID = .codex
        } catch {
            do {
                try await configureProviderRuntime(
                    store: store,
                    scenario: scenario,
                    refreshAll: false,
                )
                accountActionError = Self.accountErrorMessage(error)
            } catch let recoveryError {
                accountActionError = Self.accountErrorMessage(error)
                    + " Usage updates could not be restarted: "
                    + Self.accountErrorMessage(recoveryError)
            }
        }
    }

    @discardableResult
    func renameManagedAccount(_ accountID: AccountID, to displayName: String) async -> Bool {
        guard !isLoading, !isManagingAccounts, !isRefreshing, let accountCoordinator else {
            return false
        }
        isManagingAccounts = true
        defer { isManagingAccounts = false }
        do {
            try await accountCoordinator.rename(accountID, to: displayName)
            state = await store?.currentState() ?? state
            accountActionError = nil
            return true
        } catch {
            accountActionError = Self.accountErrorMessage(error)
            return false
        }
    }

    func setManagedAccount(_ accountID: AccountID, isEnabled: Bool) async {
        guard !isLoading, !isManagingAccounts, !isRefreshing, let accountCoordinator else {
            return
        }
        isManagingAccounts = true
        defer { isManagingAccounts = false }
        do {
            try await accountCoordinator.setEnabled(accountID, isEnabled: isEnabled)
            state = await store?.currentState() ?? state
            accountActionError = nil
        } catch {
            accountActionError = Self.accountErrorMessage(error)
        }
    }

    func removeManagedAccount(_ accountID: AccountID) async {
        guard !isLoading, !isManagingAccounts, !isRefreshing, let accountCoordinator,
              let store, let scenario = simulatedScenario
        else {
            return
        }
        isManagingAccounts = true
        defer { isManagingAccounts = false }
        do {
            _ = try await accountCoordinator.remove(accountID)
            try await configureProviderRuntime(
                store: store,
                scenario: scenario,
                refreshAll: false,
            )
            reconcileActiveProvider()
            accountActionError = nil
        } catch {
            state = await store.currentState()
            accountActionError = Self.accountErrorMessage(error)
        }
    }

    func reportAccountPickerError(_: any Error) {
        accountActionError = "The Codex profile folder could not be opened."
    }
}

extension PacePresentationModel {
    func configureProviderRuntime(
        store: PaceStore,
        scenario: SimulatedScenario,
        refreshAll shouldRefresh: Bool,
    ) async throws {
        await shutdownProviderRuntime()
        let startingState = await store.currentState()
        let productionAdapters = ProductionProviderCatalog.adapters(for: startingState.accounts)
        let productionProviderIDs = Set(productionAdapters.map(\.providerID))
        let simulatedProviderIDs = Set(startingState.accounts.compactMap { account -> ProviderID? in
            account.credentialBinding.isSimulated ? account.providerID : nil
        })
        let simulatedAdapters = scenario.adapters.filter { adapter in
            simulatedProviderIDs.contains(adapter.providerID)
                && !productionProviderIDs.contains(adapter.providerID)
        }
        let runtime = try RefreshCoordinator(
            store: store,
            adapters: productionAdapters + simulatedAdapters,
        )
        if shouldRefresh {
            for _ in 0 ..< scenario.refreshCycles {
                try await runtime.refreshAll()
            }
        }

        refreshCoordinator = runtime
        accountCoordinator = AccountCoordinator(store: store, refreshCoordinator: runtime)
        state = await store.currentState()
        monitorProviderUpdates(coordinator: runtime, store: store)
        reconcileActiveProvider()
    }

    func shutdownProviderRuntime() async {
        await stopProviderUpdatesAndWait()
        let runtime = refreshCoordinator
        refreshCoordinator = nil
        accountCoordinator = nil
        await runtime?.shutdownAdapters()
    }

    private func reconcileActiveProvider() {
        let providerIDs = visibleProviderIDs
        guard !providerIDs.contains(activeProviderID),
              let firstProviderID = providerIDs.first
        else {
            return
        }
        activeProviderID = firstProviderID
        if railPreviewState.detailProviderID != nil {
            railPreviewState = RailPreviewState(providerID: firstProviderID) ?? .rail
        }
    }

    private static func directoryExists(_ directory: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(
            atPath: directory.standardizedFileURL.path,
            isDirectory: &isDirectory,
        ) && isDirectory.boolValue
    }

    private static func accountErrorMessage(_ error: any Error) -> String {
        if let failure = error as? ProviderFailure {
            return providerFailureMessage(failure)
        }
        if let actionError = error as? CodexAccountOnboardingError {
            return actionError.message
        }
        if let mutationError = error as? AccountMutationError {
            return accountMutationErrorMessage(mutationError)
        }
        return "The account change could not be completed."
    }

    private static func providerFailureMessage(_ failure: ProviderFailure) -> String {
        switch failure {
        case .signedOut:
            "Codex is signed out in this profile. Sign in with Codex, then try again."
        case .rateLimited:
            "Codex is temporarily rate limited. Try again later."
        case .failed:
            "Codex could not verify this profile."
        case let .unavailable(code):
            code == "codex-executable-unavailable"
                ? "Install the Codex CLI before adding this account."
                : "Codex is unavailable for this profile."
        }
    }

    private static func accountMutationErrorMessage(_ error: AccountMutationError) -> String {
        switch error {
        case .emptyDisplayName:
            "Account names cannot be empty."
        case .duplicateDisplayName:
            "Choose a different account name for this provider."
        case .duplicateCredentialBinding:
            "This provider profile is already registered."
        default:
            "The account change could not be saved."
        }
    }
}

private extension CodexAccountOnboardingError {
    var message: String {
        switch self {
        case .identityAlreadyRegistered:
            "This Codex identity is already registered from another profile folder."
        case .profileIdentityChanged:
            "This profile folder now belongs to a different Codex identity. "
                + "Remove the old account before adding it again."
        case .profileNotDiscovered:
            "Codex did not return an account for the selected profile folder."
        }
    }
}

extension CredentialBinding {
    var isSimulated: Bool {
        if case .simulated = self {
            return true
        }
        return false
    }
}

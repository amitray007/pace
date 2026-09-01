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
        if !liveProviders.isEmpty {
            let names = liveProviders.sorted().map { ProviderStyle.resolve($0).name }
            let liveDescription = "Live \(Self.formattedProviderList(names))"
            return hasSimulation ? "\(liveDescription); other providers simulated" : liveDescription
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
        await addProviderProfile(at: directory, providerID: .codex)
    }

    func addDefaultGrokAccount() async {
        await addGrokProfile(at: defaultGrokProfileDirectory)
    }

    func addGrokProfile(at directory: URL) async {
        await addProviderProfile(at: directory, providerID: .grok)
    }

    private func addProviderProfile(at directory: URL, providerID: ProviderID) async {
        guard !isReferencePreview, !isLoading, !isManagingAccounts, !isRefreshing,
              let store, let scenario = simulatedScenario
        else {
            return
        }
        guard Self.directoryExists(directory) else {
            accountActionError = "The selected \(Self.providerName(providerID)) profile folder "
                + "does not exist."
            return
        }

        isManagingAccounts = true
        defer { isManagingAccounts = false }
        accountActionError = nil
        await shutdownProviderRuntime()

        do {
            switch providerID {
            case .codex:
                _ = try await CodexAccountOnboarding().addProfile(at: directory, to: store)
            case .grok:
                _ = try await GrokAccountOnboarding().addProfile(at: directory, to: store)
            default:
                preconditionFailure("Unsupported profile provider: \(providerID.rawValue)")
            }
            try await configureProviderRuntime(
                store: store,
                scenario: scenario,
                refreshAll: false,
            )
            state = await store.currentState()
            activeProviderID = providerID
        } catch {
            do {
                try await configureProviderRuntime(
                    store: store,
                    scenario: scenario,
                    refreshAll: false,
                )
                accountActionError = Self.accountErrorMessage(error, providerID: providerID)
            } catch let recoveryError {
                accountActionError = Self.accountErrorMessage(error, providerID: providerID)
                    + " Usage updates could not be restarted: "
                    + Self.accountErrorMessage(recoveryError, providerID: providerID)
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
        guard !isLoading, !isManagingAccounts, !isRefreshing, let accountCoordinator,
              let store, let scenario = simulatedScenario,
              let account = state.accounts.first(where: { $0.id == accountID })
        else {
            return
        }
        isManagingAccounts = true
        defer { isManagingAccounts = false }
        do {
            try await accountCoordinator.setEnabled(accountID, isEnabled: isEnabled)
            try await configureProviderRuntime(
                store: store,
                scenario: scenario,
                refreshAll: false,
            )
            if isEnabled {
                try await refreshAccountIfAvailable(accountID)
            } else {
                try await refreshSimulatedFallbackIfNeeded(for: account.providerID)
            }
            accountActionError = nil
        } catch {
            state = await store.currentState()
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
            let removedAccount = try await accountCoordinator.remove(accountID)
            try await configureProviderRuntime(
                store: store,
                scenario: scenario,
                refreshAll: false,
            )
            try await refreshSimulatedFallbackIfNeeded(for: removedAccount.providerID)
            reconcileActiveProvider()
            accountActionError = nil
        } catch {
            state = await store.currentState()
            accountActionError = Self.accountErrorMessage(error)
        }
    }

    func reportAccountPickerError(_: any Error, providerID: ProviderID) {
        accountActionError = "The \(Self.providerName(providerID)) profile folder could not be "
            + "opened."
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
        let enabledProductionProviderIDs = Set(
            startingState.accounts.compactMap { account -> ProviderID? in
                guard account.isEnabled, !account.credentialBinding.isSimulated else {
                    return nil
                }
                return account.providerID
            },
        )
        let productionAdapters = ProductionProviderCatalog.adapters(for: startingState.accounts)
            .filter { enabledProductionProviderIDs.contains($0.providerID) }
        let simulatedProviderIDs = Set(startingState.accounts.compactMap { account -> ProviderID? in
            account.credentialBinding.isSimulated ? account.providerID : nil
        })
        let simulatedAdapters = scenario.adapters.filter { adapter in
            simulatedProviderIDs.contains(adapter.providerID)
                && !enabledProductionProviderIDs.contains(adapter.providerID)
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

    private func refreshAccountIfAvailable(_ accountID: AccountID) async throws {
        guard let refreshCoordinator else {
            return
        }
        _ = try await refreshCoordinator.refresh(accountID)
        state = await store?.currentState() ?? state
    }

    private func refreshSimulatedFallbackIfNeeded(for providerID: ProviderID) async throws {
        let currentState = await store?.currentState() ?? state
        let hasEnabledLiveAccount = currentState.accounts.contains { account in
            account.providerID == providerID
                && account.isEnabled
                && !account.credentialBinding.isSimulated
        }
        guard !hasEnabledLiveAccount,
              let fallback = currentState.accounts.first(where: { account in
                  account.providerID == providerID
                      && account.isEnabled
                      && account.credentialBinding.isSimulated
              })
        else {
            state = currentState
            return
        }
        try await refreshAccountIfAvailable(fallback.id)
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

    private static func accountErrorMessage(
        _ error: any Error,
        providerID: ProviderID? = nil,
    ) -> String {
        if let failure = error as? ProviderFailure {
            return providerFailureMessage(failure, providerID: providerID)
        }
        if let actionError = error as? ProviderProfileAccountOnboardingError {
            return actionError.message(providerID: providerID)
        }
        if let mutationError = error as? AccountMutationError {
            return accountMutationErrorMessage(mutationError)
        }
        return "The account change could not be completed."
    }

    private static func providerFailureMessage(
        _ failure: ProviderFailure,
        providerID: ProviderID?,
    ) -> String {
        let providerName = providerName(providerID)
        return switch failure {
        case .signedOut:
            "\(providerName) is signed out in this profile. Sign in with \(providerName), then "
                + "try again."
        case .identityMismatch:
            "This profile now belongs to a different \(providerName) account."
        case .rateLimited:
            "\(providerName) is temporarily rate limited. Try again later."
        case .failed:
            "\(providerName) could not verify this profile."
        case let .unavailable(code):
            if code == "codex-executable-unavailable" {
                "Install the Codex CLI before adding this account."
            } else if code == "grok-credential-unsupported" {
                "This Grok profile uses an API key or custom issuer. Pace only reads first-party "
                    + "Grok sessions."
            } else {
                "\(providerName) is unavailable for this profile."
            }
        }
    }

    private static func providerName(_ providerID: ProviderID?) -> String {
        switch providerID {
        case .codex:
            "Codex"
        case .grok:
            "Grok"
        default:
            "Provider"
        }
    }

    private static func formattedProviderList(_ names: [String]) -> String {
        guard let last = names.last else {
            return "provider accounts"
        }
        guard names.count > 1 else {
            return last
        }
        return names.dropLast().joined(separator: ", ") + " and \(last)"
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

private extension ProviderProfileAccountOnboardingError {
    func message(providerID: ProviderID?) -> String {
        let providerName = switch providerID {
        case .codex: "Codex"
        case .grok: "Grok"
        default: "provider"
        }
        return switch self {
        case .identityAlreadyRegistered:
            "This \(providerName) identity is already registered from another profile folder."
        case .profileIdentityChanged:
            "This profile folder now belongs to a different \(providerName) identity. "
                + "Remove the old account before adding it again."
        case .profileNotDiscovered:
            "\(providerName) did not return an account for the selected profile folder."
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

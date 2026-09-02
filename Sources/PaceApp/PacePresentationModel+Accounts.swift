import Foundation
import PaceCore
import PaceProviders

extension PacePresentationModel {
    var dataSourceDescription: String {
        if isReferencePreview {
            return "Deterministic simulation"
        }
        let liveProviders = Set(state.accounts.compactMap { account -> ProviderID? in
            guard !account.credentialBinding.isSimulated else {
                return nil
            }
            return account.providerID
        })
        if !liveProviders.isEmpty {
            let names = liveProviders.sorted().map { ProviderStyle.resolve($0).name }
            return "Live \(Self.formattedProviderList(names))"
        }
        return "No accounts configured"
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

    func addDefaultClaudeAccount() async {
        await addProviderProfile(
            at: defaultClaudeProfile.directory,
            providerID: .claude,
            claudeProfile: defaultClaudeProfile,
        )
    }

    func addClaudeProfile(at directory: URL) async {
        await addProviderProfile(at: directory, providerID: .claude)
    }

    func addDefaultCodexAccount() async {
        await addCodexProfile(at: defaultCodexProfileDirectory)
    }

    func addCodexProfile(at directory: URL) async {
        await addProviderProfile(at: directory, providerID: .codex)
    }

    func addDefaultCursorAccount() async {
        await addProviderProfile(
            at: defaultCursorProfile.homeDirectory,
            providerID: .cursor,
            cursorProfile: defaultCursorProfile,
        )
    }

    func addCursorProfile(at directory: URL) async {
        await addProviderProfile(at: directory, providerID: .cursor)
    }

    func addDefaultGrokAccount() async {
        await addGrokProfile(at: defaultGrokProfileDirectory)
    }

    func addGrokProfile(at directory: URL) async {
        await addProviderProfile(at: directory, providerID: .grok)
    }

    func prepareGitHubCopilotAccountSelection() async -> Bool {
        guard !isReferencePreview, !isProviderRuntimeBusy, !isManagingAccounts, !isRefreshing else {
            return false
        }
        isManagingAccounts = true
        defer { isManagingAccounts = false }
        accountActionError = nil
        do {
            let discovered = try await GitHubCopilotAccountOnboarding().availableLogins()
            let registered: Set<String> = Set(
                managedAccounts(for: .githubCopilot).compactMap { account in
                    guard case let .commandLineAccount(tool, login, _) = account.credentialBinding,
                          tool
                              .caseInsensitiveCompare(GitHubCopilotProfile.credentialTool) ==
                              .orderedSame
                    else {
                        return nil
                    }
                    return login.lowercased()
                },
            )
            availableGitHubCopilotLogins = discovered.filter {
                !registered.contains($0.lowercased())
            }
            guard !availableGitHubCopilotLogins.isEmpty else {
                accountActionError = "Every authenticated GitHub CLI account is already added."
                return false
            }
            return true
        } catch {
            accountActionError = Self.accountErrorMessage(error, providerID: .githubCopilot)
            return false
        }
    }

    func addGitHubCopilotAccount(githubLogin: String) async {
        guard !isReferencePreview, !isProviderRuntimeBusy, !isManagingAccounts, !isRefreshing,
              let store, let scenario = simulatedScenario
        else {
            return
        }
        isManagingAccounts = true
        defer { isManagingAccounts = false }
        accountActionError = nil
        await shutdownProviderRuntime()

        do {
            _ = try await GitHubCopilotAccountOnboarding().addAccount(
                githubLogin: githubLogin,
                to: store,
            )
            try await configureProviderRuntime(store: store, scenario: scenario, refreshAll: false)
            state = await store.currentState()
            activeProviderID = .githubCopilot
        } catch {
            do {
                try await configureProviderRuntime(
                    store: store,
                    scenario: scenario,
                    refreshAll: false,
                )
                accountActionError = Self.accountErrorMessage(error, providerID: .githubCopilot)
            } catch let recoveryError {
                accountActionError = Self.accountErrorMessage(error, providerID: .githubCopilot)
                    + " Usage updates could not be restarted: "
                    + Self.accountErrorMessage(recoveryError, providerID: .githubCopilot)
            }
        }
    }

    private func addProviderProfile(
        at directory: URL,
        providerID: ProviderID,
        claudeProfile: ClaudeProfile? = nil,
        cursorProfile: CursorProfile? = nil,
    ) async {
        guard !isReferencePreview, !isProviderRuntimeBusy, !isManagingAccounts, !isRefreshing,
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
            try await onboardProviderProfile(
                at: directory,
                providerID: providerID,
                claudeProfile: claudeProfile,
                cursorProfile: cursorProfile,
                store: store,
            )
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

    private func onboardProviderProfile(
        at directory: URL,
        providerID: ProviderID,
        claudeProfile: ClaudeProfile?,
        cursorProfile: CursorProfile?,
        store: PaceStore,
    ) async throws {
        switch providerID {
        case .claude:
            let profile = claudeProfile ?? ClaudeProfile(
                directory: directory,
                ownership: .existing,
            )
            _ = try await ClaudeAccountOnboarding().addProfile(profile, to: store)
        case .codex:
            _ = try await CodexAccountOnboarding().addProfile(at: directory, to: store)
        case .cursor:
            let profile = cursorProfile ?? CursorProfile.isolated(homeDirectory: directory)
            _ = try await CursorAccountOnboarding().addProfile(profile, to: store)
        case .grok:
            _ = try await GrokAccountOnboarding().addProfile(at: directory, to: store)
        default:
            preconditionFailure("Unsupported profile provider: \(providerID.rawValue)")
        }
    }

    /// Renames an account without taking the `isManagingAccounts` lock.
    ///
    /// A rename is a store-only mutation, so it can run beside a refresh or
    /// another account change. Holding the lock disabled the row that was being
    /// edited, which ended the editing session and rejected the commit that the
    /// resulting blur fired.
    @discardableResult
    func renameManagedAccount(_ accountID: AccountID, to displayName: String) async -> Bool {
        guard !isProviderRuntimeBusy, let accountCoordinator else {
            return false
        }
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
        guard !isProviderRuntimeBusy, !isManagingAccounts, !isRefreshing, let accountCoordinator,
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
        guard !isProviderRuntimeBusy, !isManagingAccounts, !isRefreshing, let accountCoordinator,
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

    func refreshAccountIfAvailable(_ accountID: AccountID) async throws {
        guard let refreshCoordinator else {
            return
        }
        let previousState = state
        _ = try await refreshCoordinator.refresh(accountID)
        let currentState = await store?.currentState() ?? state
        state = currentState
        await deliverNotifications(previous: previousState, current: currentState)
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
}

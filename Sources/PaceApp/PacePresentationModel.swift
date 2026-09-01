import Foundation
import Observation
import PaceCore
import PaceProviders

enum RailPreviewState: String, CaseIterable, Identifiable {
    case claude
    case codex
    case cursor
    case githubCopilot
    case grok
    case mini
    case rail

    var id: Self {
        self
    }

    var detailProviderID: ProviderID? {
        switch self {
        case .claude:
            .claude
        case .codex:
            .codex
        case .cursor:
            .cursor
        case .githubCopilot:
            .githubCopilot
        case .grok:
            .grok
        case .mini, .rail:
            nil
        }
    }
}

@MainActor
@Observable
final class PacePresentationModel {
    var state = PaceState()
    private(set) var preferences: PacePreferences
    private(set) var loadingError: String?
    private(set) var preferencesError: String?
    private(set) var refreshError: String?
    private(set) var isLoading = true
    private(set) var isRefreshing = false
    var availableGitHubCopilotLogins: [String] = []
    var accountActionError: String?
    var isManagingAccounts = false
    var activeProviderID: ProviderID = .claude
    var railPreviewState: RailPreviewState
    let forcesIncreasedContrast: Bool
    let defaultClaudeProfile: ClaudeProfile
    let defaultCodexProfileDirectory: URL
    let defaultCursorProfile: CursorProfile
    let defaultGrokProfileDirectory: URL

    let isReferencePreview: Bool
    private let simulatedPresentationState: SimulatedPresentationState
    private let preferencesPersistence: any PacePreferencesPersistence
    private let statePersistence: any PaceStatePersistence
    private var hasStarted = false
    private var preferencesStore: PacePreferencesStore?
    private var providerUpdateTask: Task<Void, Never>?
    var accountCoordinator: AccountCoordinator?
    var refreshCoordinator: RefreshCoordinator?
    var simulatedScenario: SimulatedScenario?
    var store: PaceStore?
    private var streamPersistenceFailures: Set<AccountID> = []

    isolated deinit {
        stopProviderUpdates()
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferencesPersistence: any PacePreferencesPersistence =
            InMemoryPacePreferencesPersistence(),
        statePersistence: any PaceStatePersistence = InMemoryPaceStatePersistence(),
    ) {
        let previewState = environment["PACE_REFERENCE_PREVIEW"]
            .flatMap(RailPreviewState.init(rawValue:))
        var initialPreferences = PacePreferences()
        if previewState != nil {
            initialPreferences.surfaceMode = .both
        }
        if let previewEdge = environment["PACE_REFERENCE_EDGE"].flatMap(RailEdge.init(rawValue:)) {
            initialPreferences.railEdge = previewEdge
        }
        let previewActivation = environment["PACE_REFERENCE_ACTIVATION"]
            .flatMap(RailActivationMode.init(rawValue:))
        if let previewActivation {
            initialPreferences.activationMode = previewActivation
        }
        preferences = initialPreferences
        railPreviewState = previewState ?? .mini
        isReferencePreview = previewState != nil
        forcesIncreasedContrast = environment["PACE_REFERENCE_CONTRAST"] == "increased"
        defaultClaudeProfile = ClaudeProfile.current(environment: environment)
        defaultCodexProfileDirectory = environment["CODEX_HOME"]
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex", directoryHint: .isDirectory)
        defaultCursorProfile = CursorProfile.current()
        defaultGrokProfileDirectory = environment["GROK_HOME"]
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".grok", directoryHint: .isDirectory)
        simulatedPresentationState = environment["PACE_SIMULATED_STATE"]
            .flatMap(SimulatedPresentationState.init(rawValue:)) ?? .current
        self.preferencesPersistence = preferencesPersistence
        self.statePersistence = statePersistence
    }

    var isRailVisible: Bool {
        preferences.surfaceMode.showsEdgeRail
    }

    var availableDisplays: [PaceDisplayDescriptor] {
        PaceDisplayCatalog.availableDisplays
    }

    var visibleProviderIDs: [ProviderID] {
        let available = Set(state.accounts.map(\.providerID))
        let ordered = preferences.providerOrder.filter(available.contains)
        return ordered + available.subtracting(ordered).sorted()
    }

    var selectedAccount: ProviderAccount? {
        selectedAccount(for: activeProviderID)
    }

    var selectedSnapshots: [LimitSnapshot] {
        guard let selectedAccount else {
            return []
        }
        return snapshots(for: selectedAccount.id)
    }

    var selectedUsageStatus: AccountUsageStatus? {
        guard let selectedAccount else {
            return nil
        }
        return usageStatus(for: selectedAccount)
    }

    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        defer {
            isLoading = false
        }

        if !isReferencePreview {
            do {
                let preferencesStore = try await PacePreferencesStore.open(
                    persistence: preferencesPersistence,
                )
                self.preferencesStore = preferencesStore
                preferences = await preferencesStore.currentPreferences()
            } catch {
                preferencesError = "Settings could not be loaded. Defaults are active."
            }
        }

        do {
            let persistence: any PaceStatePersistence = isReferencePreview
                ? InMemoryPaceStatePersistence()
                : statePersistence
            let store = try await PaceStore.open(persistence: persistence)
            let scenario = try SimulatedScenarios.visualReference(
                presentationState: simulatedPresentationState,
            )
            if await store.currentState().accounts.isEmpty {
                try await scenario.seed(store)
            }
            try await configureProviderRuntime(
                store: store,
                scenario: scenario,
                refreshAll: true,
            )
            self.store = store
            simulatedScenario = scenario
        } catch {
            loadingError = String(describing: error)
        }
    }

    func accounts(for providerID: ProviderID) -> [ProviderAccount] {
        let providerAccounts = state.accounts.filter {
            $0.providerID == providerID && $0.isEnabled
        }
        let hasLiveAccount = providerAccounts.contains {
            !$0.credentialBinding.isSimulated
        }
        return providerAccounts
            .filter { !hasLiveAccount || !$0.credentialBinding.isSimulated }
            .sorted { $0.order < $1.order }
    }

    func selectedAccount(for providerID: ProviderID) -> ProviderAccount? {
        let selection = state.selections.first { $0.providerID == providerID }
        return state.accounts.first {
            $0.id == selection?.accountID && $0.isEnabled
        } ?? accounts(for: providerID).first
    }

    func snapshots(for accountID: AccountID) -> [LimitSnapshot] {
        state.snapshots
            .filter { $0.id.accountID == accountID }
    }

    func usageStatus(for account: ProviderAccount) -> AccountUsageStatus {
        AccountUsageStatus(account: account, snapshots: snapshots(for: account.id))
    }

    func headlineUsage(for providerID: ProviderID) -> Double? {
        guard let account = selectedAccount(for: providerID) else {
            return nil
        }
        let snapshots = snapshots(for: account.id)
        let preferredBucketID: String? = switch providerID {
        case .claude:
            "current-session"
        case .codex:
            "monthly-limit"
        case .cursor:
            "included-usage"
        case .grok:
            "included-weekly"
        case .githubCopilot:
            "credits"
        default:
            nil
        }
        return snapshots.first { $0.id.bucketID.rawValue == preferredBucketID }?.usedFraction
            ?? snapshots.map(\.usedFraction).max()
    }

    func selectProvider(_ providerID: ProviderID) {
        activeProviderID = providerID
        if railPreviewState.detailProviderID != nil {
            railPreviewState = RailPreviewState(providerID: providerID) ?? .rail
        }
    }

    func selectAccount(_ accountID: AccountID, for providerID: ProviderID) async {
        guard let store else {
            return
        }
        do {
            try await store.selectAccount(accountID, for: providerID)
            state = await store.currentState()
        } catch {
            loadingError = String(describing: error)
        }
    }

    func selectAdjacentAccount(offset: Int) async {
        let accounts = accounts(for: activeProviderID)
        guard accounts.count > 1,
              let selectedAccount,
              let currentIndex = accounts.firstIndex(where: { $0.id == selectedAccount.id })
        else {
            return
        }
        let nextIndex = (currentIndex + offset + accounts.count) % accounts.count
        await selectAccount(accounts[nextIndex].id, for: activeProviderID)
    }

    func refreshAll() async {
        guard !isLoading, !isRefreshing, !isManagingAccounts,
              let refreshCoordinator, let store
        else {
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
        }
        do {
            try await refreshCoordinator.refreshAll()
            state = await store.currentState()
            streamPersistenceFailures.removeAll()
            refreshError = nil
        } catch {
            refreshError = "Usage could not be refreshed."
        }
    }

    func stopProviderUpdates() {
        providerUpdateTask?.cancel()
        providerUpdateTask = nil
    }

    func stopProviderUpdatesAndWait() async {
        let task = providerUpdateTask
        providerUpdateTask = nil
        task?.cancel()
        await task?.value
    }

    func monitorProviderUpdates(
        coordinator: RefreshCoordinator,
        store: PaceStore,
    ) {
        stopProviderUpdates()
        providerUpdateTask = Task { [weak self] in
            let updates = await coordinator.updateStream()
            for await update in updates {
                guard !Task.isCancelled, let self else {
                    break
                }
                switch update {
                case let .applied(outcome):
                    state = await store.currentState()
                    streamPersistenceFailures.remove(outcome.accountID)
                    refreshError = streamPersistenceFailures.isEmpty
                        ? nil
                        : "Usage changed, but the update could not be saved."
                case let .persistenceFailed(accountID):
                    streamPersistenceFailures.insert(accountID)
                    refreshError = "Usage changed, but the update could not be saved."
                }
            }
        }
    }

    private func updatePreferences(_ update: (inout PacePreferences) -> Void) {
        var nextPreferences = preferences
        update(&nextPreferences)
        guard nextPreferences != preferences else {
            return
        }
        preferences = nextPreferences

        guard !isReferencePreview, let preferencesStore else {
            return
        }
        Task {
            do {
                try await preferencesStore.replace(with: nextPreferences)
                preferencesError = nil
            } catch {
                preferencesError = "Settings could not be saved."
            }
        }
    }
}

extension PacePresentationModel {
    func toggleRail() {
        setRailVisible(!isRailVisible)
    }

    func toggleRailDetails() {
        if railPreviewState.detailProviderID == nil {
            railPreviewState = RailPreviewState(providerID: activeProviderID) ?? .rail
        } else {
            railPreviewState = .rail
        }
    }

    func showRail() {
        railPreviewState = .rail
    }

    func showRailDetails(for providerID: ProviderID) {
        activeProviderID = providerID
        railPreviewState = RailPreviewState(providerID: providerID) ?? .rail
    }

    func collapseRail() {
        railPreviewState = .mini
    }

    func setRailVisible(_ isVisible: Bool) {
        updatePreferences { preferences in
            preferences.surfaceMode = isVisible ? .both : .menuBar
        }
    }

    func setRailEdge(_ edge: RailEdge) {
        updatePreferences { $0.railEdge = edge }
    }

    func setSelectedDisplayID(_ displayID: String?) {
        updatePreferences { $0.selectedDisplayID = displayID }
    }

    func setRailVerticalPosition(_ position: RailVerticalPosition) {
        updatePreferences { $0.railVerticalPosition = position }
    }

    func setActivationMode(_ mode: RailActivationMode) {
        updatePreferences { $0.activationMode = mode }
    }

    func setActivationModifier(_ modifier: RailActivationModifier) {
        updatePreferences { $0.activationModifier = modifier }
    }

    func setDwellDelay(_ delay: TimeInterval) {
        updatePreferences { $0.dwellDelay = delay }
    }

    func setDismissalDelay(_ delay: TimeInterval) {
        updatePreferences { $0.dismissalDelay = delay }
    }

    func setHideRailInFullScreen(_ isHidden: Bool) {
        updatePreferences { $0.hideRailInFullScreen = isHidden }
    }

    func moveProvider(_ providerID: ProviderID, by offset: Int) {
        let visibleProviderIDs = visibleProviderIDs
        guard let sourceVisibleIndex = visibleProviderIDs.firstIndex(of: providerID) else {
            return
        }
        let destinationVisibleIndex = sourceVisibleIndex + offset
        guard visibleProviderIDs.indices.contains(destinationVisibleIndex),
              let sourceIndex = preferences.providerOrder.firstIndex(of: providerID),
              let destinationIndex = preferences.providerOrder.firstIndex(
                  of: visibleProviderIDs[destinationVisibleIndex],
              )
        else {
            return
        }
        updatePreferences { preferences in
            preferences.providerOrder.swapAt(sourceIndex, destinationIndex)
        }
    }
}

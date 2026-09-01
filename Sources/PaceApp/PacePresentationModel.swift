import Foundation
import Observation
import PaceCore
import PaceProviders

@MainActor
@Observable
final class PacePresentationModel {
    var state = PaceState()
    private(set) var preferences: PacePreferences
    private(set) var loadingError: String?
    private(set) var launchAtLoginError: String?
    private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    var notificationAuthorizationStatus: PaceNotificationAuthorizationStatus = .notDetermined
    var notificationError: String?
    private(set) var preferencesError: String?
    private(set) var refreshError: String?
    private(set) var isLoading = true

    /// When the next automatic refresh is due.
    ///
    /// Surfaces the schedule so a countdown can state it. Nil while no
    /// automatic refresh is scheduled, which is honest: the panel then says
    /// nothing about a refresh rather than counting toward one that will not
    /// happen.
    private(set) var nextRefreshAt: Date?

    private var automaticRefreshTask: Task<Void, Never>?
    private(set) var isChangingLaunchAtLogin = false
    var isChangingNotificationAuthorization = false
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
    private let launchAtLoginSetting: LaunchAtLoginSetting
    let notificationDeliveryController: PaceNotificationDeliveryController
    private let statePersistence: any PaceStatePersistence
    private var hasStarted = false
    var notificationSettingsTask: Task<Void, Never>?
    private var preferencesStore: PacePreferencesStore?
    private var providerUpdateTask: Task<Void, Never>?
    var accountCoordinator: AccountCoordinator?
    var refreshCoordinator: RefreshCoordinator?
    var simulatedScenario: SimulatedScenario?
    var store: PaceStore?
    private var streamPersistenceFailures: Set<AccountID> = []

    isolated deinit {
        notificationSettingsTask?.cancel()
        stopProviderUpdates()
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferencesPersistence: any PacePreferencesPersistence =
            InMemoryPacePreferencesPersistence(),
        statePersistence: any PaceStatePersistence = InMemoryPaceStatePersistence(),
        launchAtLoginService: any LaunchAtLoginService = SystemLaunchAtLoginService(),
        notificationDeliveryService: any PaceNotificationDeliveryService =
            SystemPaceNotificationDeliveryService(),
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
        let previewScale = environment["PACE_REFERENCE_SCALE"]
            .flatMap(RailScale.init(rawValue:))
        if let previewScale {
            initialPreferences.railScale = previewScale
        }
        let previewActivation = environment["PACE_REFERENCE_ACTIVATION"]
            .flatMap(RailActivationMode.init(rawValue:))
        if let previewActivation {
            initialPreferences.activationMode = previewActivation
        }
        preferences = initialPreferences
        launchAtLoginSetting = LaunchAtLoginSetting(service: launchAtLoginService)
        launchAtLoginStatus = launchAtLoginSetting.status
        notificationDeliveryController = PaceNotificationDeliveryController(
            service: notificationDeliveryService,
        )
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
        let available = if isReferencePreview {
            Set(state.accounts.map(\.providerID))
        } else {
            Set(PacePreferences.defaultProviderOrder).union(
                state.accounts.compactMap { account in
                    account.credentialBinding.isSimulated ? nil : account.providerID
                },
            )
        }
        let ordered = preferences.providerOrder.filter(available.contains)
        return ordered + available.subtracting(ordered).sorted()
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
            refreshLaunchAtLoginStatus()
            do {
                let preferencesStore = try await PacePreferencesStore.open(
                    persistence: preferencesPersistence,
                )
                self.preferencesStore = preferencesStore
                preferences = await preferencesStore.currentPreferences()
            } catch {
                preferencesError = "Settings could not be loaded. Defaults are active."
            }
            await refreshNotificationAuthorizationStatus()
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

    func selectProvider(_ providerID: ProviderID) {
        activeProviderID = providerID
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

    /// How often Pace refreshes every account on its own.
    ///
    /// Adapters poll their own providers conservatively; this is the app-level
    /// sweep that keeps the surfaces current when nothing else has run. Fifteen
    /// minutes matches the providers' own baseline so it adds no extra load.
    static let automaticRefreshInterval: TimeInterval = 900

    /// Runs an automatic refresh on a repeating schedule.
    ///
    /// Without this, usage only updated at launch or when the user pressed
    /// refresh, so a panel left open drifted further out of date the longer it
    /// stayed open.
    func startAutomaticRefresh() {
        guard automaticRefreshTask == nil, !isReferencePreview else {
            return
        }
        scheduleNextRefresh()
        automaticRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .seconds(Self.automaticRefreshInterval),
                )
                guard !Task.isCancelled else {
                    return
                }
                await self?.refreshAll()
            }
        }
    }

    func stopAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        nextRefreshAt = nil
    }

    private func scheduleNextRefresh() {
        guard !isReferencePreview else {
            return
        }
        nextRefreshAt = Date().addingTimeInterval(Self.automaticRefreshInterval)
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
            scheduleNextRefresh()
        }
        let previousState = state
        do {
            try await refreshCoordinator.refreshAll()
            let currentState = await store.currentState()
            state = currentState
            streamPersistenceFailures.removeAll()
            refreshError = nil
            await deliverNotifications(previous: previousState, current: currentState)
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
                    let previousState = state
                    let currentState = await store.currentState()
                    state = currentState
                    streamPersistenceFailures.remove(outcome.accountID)
                    refreshError = streamPersistenceFailures.isEmpty
                        ? nil
                        : "Usage changed, but the update could not be saved."
                    await deliverNotifications(previous: previousState, current: currentState)
                case let .persistenceFailed(accountID):
                    streamPersistenceFailures.insert(accountID)
                    refreshError = "Usage changed, but the update could not be saved."
                }
            }
        }
    }

    func updatePreferences(_ update: (inout PacePreferences) -> Void) {
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
    var launchesAtLogin: Bool {
        launchAtLoginSetting.isRegistered
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginSetting.refresh()
        launchAtLoginStatus = launchAtLoginSetting.status
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        guard !isReferencePreview, !isChangingLaunchAtLogin else {
            return
        }
        isChangingLaunchAtLogin = true
        defer { isChangingLaunchAtLogin = false }

        launchAtLoginSetting.setEnabled(isEnabled)
        launchAtLoginStatus = launchAtLoginSetting.status
        launchAtLoginError = launchAtLoginSetting.lastOperationFailed
            ? "Pace could not update Login Items. Check System Settings and try again."
            : nil
    }

    func openLoginItemsSettings() {
        launchAtLoginSetting.openSystemSettings()
    }

    func toggleRail() {
        setRailVisible(!isRailVisible)
    }

    func showRail() {
        railPreviewState = .rail
    }

    func showRailDetails(for providerID: ProviderID) {
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

    func setRailScale(_ scale: RailScale) {
        updatePreferences { $0.railScale = scale }
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

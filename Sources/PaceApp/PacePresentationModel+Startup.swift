import Foundation
import PaceCore

/// What Pace does between launching and having current usage on screen.
///
/// Kept apart from the model because the ordering here carries the decision
/// that stored snapshots are shown before the providers are read.
extension PacePresentationModel {
    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        defer {
            markLoaded()
        }

        if !isReferencePreview {
            await loadPreferences()
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

            // Show what was stored on the last run before reading the
            // providers. That read needs credentials from the keychain, which
            // can block on a system prompt, and until it returned the surfaces
            // had no accounts and reported that as "No account configured".
            // Stored snapshots are stale rather than absent, and their
            // observation time already says so.
            self.store = store
            simulatedScenario = scenario
            state = await store.currentState()
            markLoaded()

            beginFirstRefresh()
            defer { endFirstRefresh() }
            try await configureProviderRuntime(
                store: store,
                scenario: scenario,
                refreshAll: true,
            )

            // After the providers have been read, so a real account that was
            // only just discovered still retires its demonstration stand-in.
            // Nothing refreshes a simulated account, so leaving one in place
            // beside a live one keeps fixture-dated readings on screen forever.
            if !isReferencePreview {
                let retired = try await store.retireSimulatedAccounts()
                if !retired.isEmpty {
                    state = await store.currentState()
                }
            }
        } catch {
            reportLoadingFailure(String(describing: error))
        }
    }

    private func loadPreferences() async {
        refreshLaunchAtLoginStatus()
        do {
            let preferencesStore = try await PacePreferencesStore.open(
                persistence: preferencesPersistence,
            )
            self.preferencesStore = preferencesStore
            await adoptPreferences(preferencesStore.currentPreferences())
        } catch {
            reportPreferencesFailure("Settings could not be loaded. Defaults are active.")
        }
        await refreshNotificationAuthorizationStatus()
    }
}

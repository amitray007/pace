import Foundation
@testable import PaceCore
import Testing

@Suite("Visual reference scenario")
struct VisualReferenceScenarioTests {
    @Test
    func `matches the reference percentages and keeps accounts isolated`() async throws {
        let state = try await runScenario()

        #expect(state.accounts.count == 4)
        #expect(state.accounts.filter { $0.providerID == .claude }.count == 2)
        #expect(Set(state.accounts.map(\.providerID)) == Set([.claude, .codex, .cursor]))

        let claudePersonal = try account(named: "Personal", providerID: .claude, in: state)
        let claudeWork = try account(named: "Work", providerID: .claude, in: state)
        let codex = try account(named: "Personal", providerID: .codex, in: state)
        let cursor = try account(named: "Work", providerID: .cursor, in: state)

        #expect(try usage("Current session", accountID: claudePersonal.id, in: state) == 0.73)
        #expect(try usage("All models", accountID: claudePersonal.id, in: state) == 0.07)
        #expect(try usage("Current session", accountID: claudeWork.id, in: state) == 0.41)
        #expect(try usage("All models", accountID: claudeWork.id, in: state) == 0.36)
        #expect(try usage("Monthly limit", accountID: codex.id, in: state) == 0.21)
        #expect(try usage("Included usage", accountID: cursor.id, in: state) == 0.52)
    }

    @Test
    func `is deterministic`() async throws {
        let firstState = try await runScenario()
        let secondState = try await runScenario()

        #expect(firstState == secondState)
    }

    private func runScenario() async throws -> PaceState {
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let scenario = try SimulatedScenarios.visualReference()
        try await scenario.seed(store)
        let coordinator = try RefreshCoordinator(store: store, adapters: scenario.adapters)
        try await coordinator.refreshAll()
        return await store.currentState()
    }

    private func account(
        named displayName: String,
        providerID: ProviderID,
        in state: PaceState,
    ) throws -> ProviderAccount {
        try #require(state.accounts.first {
            $0.displayName == displayName && $0.providerID == providerID
        })
    }

    private func usage(
        _ label: String,
        accountID: AccountID,
        in state: PaceState,
    ) throws -> Double {
        try #require(state.snapshots.first {
            $0.id.accountID == accountID && $0.label == label
        }).usedFraction
    }
}

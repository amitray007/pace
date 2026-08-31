import Foundation
import Observation
import PaceCore

enum RailPreviewState: String, CaseIterable, Identifiable {
    case claude
    case codex
    case cursor
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
        case .mini, .rail:
            nil
        }
    }
}

@MainActor
@Observable
final class PacePresentationModel {
    private(set) var state = PaceState()
    private(set) var loadingError: String?
    var activeProviderID: ProviderID = .claude
    var isRailVisible: Bool
    var railPreviewState: RailPreviewState

    private var hasStarted = false
    private var store: PaceStore?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let previewState = environment["PACE_REFERENCE_PREVIEW"]
            .flatMap(RailPreviewState.init(rawValue:))
        isRailVisible = previewState != nil
        railPreviewState = previewState ?? .rail
    }

    var visibleProviderIDs: [ProviderID] {
        let available = Set(state.accounts.map(\.providerID))
        return [.claude, .codex, .cursor].filter(available.contains)
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

    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        do {
            let store = try await PaceStore.open(
                persistence: InMemoryPaceStatePersistence(),
            )
            let scenario = try SimulatedScenarios.visualReference()
            try await scenario.seed(store)
            let coordinator = try RefreshCoordinator(store: store, adapters: scenario.adapters)
            try await coordinator.refreshAll()
            self.store = store
            state = await store.currentState()
        } catch {
            loadingError = String(describing: error)
        }
    }

    func accounts(for providerID: ProviderID) -> [ProviderAccount] {
        state.accounts
            .filter { $0.providerID == providerID && $0.isEnabled }
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

    func toggleRail() {
        isRailVisible.toggle()
    }

    func toggleRailDetails() {
        if railPreviewState.detailProviderID == nil {
            railPreviewState = RailPreviewState(providerID: activeProviderID) ?? .rail
        } else {
            railPreviewState = .rail
        }
    }
}

private extension RailPreviewState {
    init?(providerID: ProviderID) {
        switch providerID {
        case .claude:
            self = .claude
        case .codex:
            self = .codex
        case .cursor:
            self = .cursor
        default:
            return nil
        }
    }
}

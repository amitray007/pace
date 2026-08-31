import Foundation

public enum SimulatedRefreshStep: Sendable {
    case failure(ProviderFailure)
    case result(ProviderRefreshResult)
}

public actor SimulatedProviderAdapter: ProviderAdapter {
    public nonisolated let providerID: ProviderID
    public nonisolated let capabilities: ProviderCapabilities

    private let discoveredAccounts: [DiscoveredAccount]
    private var refreshCounts: [AccountID: Int] = [:]
    private var refreshSteps: [AccountID: [SimulatedRefreshStep]]

    public init(
        providerID: ProviderID,
        discoveredAccounts: [DiscoveredAccount],
        refreshSteps: [AccountID: [SimulatedRefreshStep]],
        capabilities: ProviderCapabilities = ProviderCapabilities(
            supportsAccountDiscovery: true,
            supportsMultipleAccounts: true,
            supportsStreamingUpdates: false,
        ),
    ) {
        self.providerID = providerID
        self.discoveredAccounts = discoveredAccounts
        self.refreshSteps = refreshSteps
        self.capabilities = capabilities
    }

    public func discoverAccounts() throws(ProviderFailure) -> [DiscoveredAccount] {
        discoveredAccounts
    }

    public func refresh(
        _ account: ProviderAccount,
    ) throws(ProviderFailure) -> ProviderRefreshResult {
        guard account.providerID == providerID else {
            throw .unavailable(code: "provider-mismatch")
        }
        guard var steps = refreshSteps[account.id], let step = steps.first else {
            throw .unavailable(code: "fixture-missing")
        }

        refreshCounts[account.id, default: 0] += 1
        if steps.count > 1 {
            steps.removeFirst()
            refreshSteps[account.id] = steps
        }

        switch step {
        case let .failure(failure):
            throw failure
        case let .result(result):
            return result
        }
    }

    public func refreshCount(for accountID: AccountID) -> Int {
        refreshCounts[accountID, default: 0]
    }
}

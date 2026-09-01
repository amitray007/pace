import Foundation
@testable import PaceCore

struct CoreTestTimeout: Error {}

func refreshResult(
    for discoveredAccount: DiscoveredAccount,
    accountID: AccountID,
    usedFraction: Double,
) throws -> ProviderRefreshResult {
    try TestSupport.result(
        for: discoveredAccount,
        accountID: accountID,
        snapshots: [
            TestSupport.snapshot(
                accountID: accountID,
                usedFraction: usedFraction,
            ),
        ],
    )
}

func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @Sendable () async -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            throw CoreTestTimeout()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

actor ProviderDeliveryRecorder {
    private var deliveries: [ProviderUpdateDelivery] = []

    var count: Int {
        deliveries.count
    }

    func append(_ delivery: ProviderUpdateDelivery) {
        deliveries.append(delivery)
    }

    func delivery(at index: Int) -> ProviderUpdateDelivery {
        deliveries[index]
    }
}

actor FailingPaceStatePersistence: PaceStatePersistence {
    private struct SaveFailure: Error {}

    private var shouldFailNextSave = false
    private var state: PaceState?

    func load() -> PaceState? {
        state
    }

    func save(_ state: PaceState) throws {
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw SaveFailure()
        }
        self.state = state
    }

    func failNextSave() {
        shouldFailNextSave = true
    }
}

actor LifecycleTestAdapter: ProviderAdapterLifecycle {
    nonisolated let providerID = ProviderID.codex
    nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: false,
    )

    private(set) var shutdownCount = 0

    func discoverAccounts() -> [DiscoveredAccount] {
        []
    }

    func refresh(_: ProviderAccount) throws(ProviderFailure) -> ProviderRefreshResult {
        throw .failed(code: "refresh-not-used")
    }

    func shutdown() {
        shutdownCount += 1
    }
}

actor LifecycleStreamingTestAdapter: ProviderUpdateStreamingAdapter {
    nonisolated let providerID = ProviderID.claude
    nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: true,
    )

    private let discoveredAccount: DiscoveredAccount
    private var continuations: [
        AccountID: AsyncStream<ProviderUpdate>.Continuation
    ] = [:]
    private var subscriptionCounts: [AccountID: Int] = [:]
    private var terminationCounts: [AccountID: Int] = [:]

    init(discoveredAccount: DiscoveredAccount) {
        self.discoveredAccount = discoveredAccount
    }

    func discoverAccounts() -> [DiscoveredAccount] {
        [discoveredAccount]
    }

    func refresh(_: ProviderAccount) throws(ProviderFailure) -> ProviderRefreshResult {
        throw .failed(code: "manual-refresh-not-used")
    }

    func updates(for account: ProviderAccount) -> AsyncStream<ProviderUpdate> {
        let pair = AsyncStream<ProviderUpdate>.makeStream(
            bufferingPolicy: .bufferingNewest(8),
        )
        subscriptionCounts[account.id, default: 0] += 1
        continuations[account.id] = pair.continuation
        return pair.stream
    }

    func stopUpdates(for account: ProviderAccount) {
        continuations.removeValue(forKey: account.id)?.finish()
        terminationCounts[account.id, default: 0] += 1
    }

    func subscriptionCount(for accountID: AccountID) -> Int {
        subscriptionCounts[accountID, default: 0]
    }

    func terminationCount(for accountID: AccountID) -> Int {
        terminationCounts[accountID, default: 0]
    }
}

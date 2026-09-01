@testable import PaceCore

func registerTestAccounts(
    _ personal: DiscoveredAccount,
    _ work: DiscoveredAccount,
    in store: PaceStore,
) async throws {
    try await store.register(
        personal,
        id: TestSupport.personalID,
        addedAt: TestSupport.referenceDate,
    )
    try await store.register(
        work,
        id: TestSupport.workID,
        addedAt: TestSupport.referenceDate,
    )
}

func successfulOutcome(
    for discoveredAccount: DiscoveredAccount,
    accountID: AccountID,
    usedFraction: Double,
) throws -> AccountRefreshOutcome {
    try .success(
        accountID: accountID,
        result: TestSupport.result(
            for: discoveredAccount,
            accountID: accountID,
            snapshots: [
                TestSupport.snapshot(
                    accountID: accountID,
                    usedFraction: usedFraction,
                ),
            ],
        ),
    )
}

actor SuspendingPaceStatePersistence: PaceStatePersistence {
    private(set) var saveCount = 0
    private(set) var storedState: PaceState?
    private var isSuspended = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveCountWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []

    func load() -> PaceState? {
        storedState
    }

    func save(_ state: PaceState) async {
        saveCount += 1
        resumeSaveCountWaiters()
        if isSuspended {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        storedState = state
    }

    func suspendSaves() {
        isSuspended = true
    }

    func releaseNextSave() {
        guard !releaseWaiters.isEmpty else {
            return
        }
        releaseWaiters.removeFirst().resume()
    }

    func waitForSaveCount(_ expectedCount: Int) async {
        guard saveCount < expectedCount else {
            return
        }
        await withCheckedContinuation { continuation in
            saveCountWaiters.append((expectedCount, continuation))
        }
    }

    private func resumeSaveCountWaiters() {
        let ready = saveCountWaiters.filter { $0.count <= saveCount }
        saveCountWaiters.removeAll { $0.count <= saveCount }
        ready.forEach { $0.continuation.resume() }
    }
}

import Foundation

// Snapshot lifecycle: replacing a read, and clearing readings that will
// never be refreshed again.

public extension PaceStore {
    /// Removes seeded demonstration accounts for providers that now have a real
    /// connection.
    ///
    /// The simulated accounts exist so the surfaces have something to show
    /// before any provider is connected. Once a real account for that provider
    /// arrives they are only a source of permanently stale readings: nothing
    /// refreshes them, so their snapshots keep whatever the fixture date said.
    ///
    /// Retirement is per provider. A provider with no real account keeps its
    /// demonstration data, because removing it would leave that tab empty
    /// rather than illustrative.
    func retireSimulatedAccounts() async throws -> [ProviderAccount] {
        var retired: [ProviderAccount] = []
        try await mutate { state in
            let liveProviderIDs = Set(
                state.accounts
                    .filter { !$0.credentialBinding.isSimulated }
                    .map(\.providerID),
            )
            retired = state.accounts.filter {
                $0.credentialBinding.isSimulated && liveProviderIDs.contains($0.providerID)
            }
            guard !retired.isEmpty else {
                return false
            }

            let retiredIDs = Set(retired.map(\.id))
            state.accounts.removeAll { retiredIDs.contains($0.id) }
            state.snapshots.removeAll { retiredIDs.contains($0.id.accountID) }
            state.selections.removeAll { retiredIDs.contains($0.accountID) }

            // A retired account may have held its provider's selection, so
            // each affected provider falls back to whichever account remains.
            for providerID in Set(retired.map(\.providerID)) {
                guard !state.selections.contains(where: { $0.providerID == providerID }),
                      let replacement = state.accounts.first(where: {
                          $0.providerID == providerID && $0.isEnabled
                      })
                else {
                    continue
                }
                state.selections.append(
                    ProviderSelection(providerID: providerID, accountID: replacement.id),
                )
            }
            return true
        }
        return retired
    }
}

public extension PaceStore {
    /// Replaces every snapshot held for an account.
    ///
    /// Replacement rather than merging: a provider reports the whole set of
    /// windows it knows about, so a bucket missing from the new set has gone
    /// away and must not linger from the previous read.
    func replaceSnapshots(
        for accountID: AccountID,
        with snapshots: [LimitSnapshot],
    ) async throws {
        try await mutate { state in
            guard let account = state.accounts.first(where: { $0.id == accountID }) else {
                throw AccountMutationError.unknownAccount(accountID)
            }
            guard snapshots.allSatisfy({ snapshot in
                snapshot.id.accountID == accountID
                    && snapshot.id.providerID == account.providerID
            }) else {
                throw AccountMutationError.invalidSnapshots(accountID)
            }

            state.snapshots.removeAll { $0.id.accountID == accountID }
            state.snapshots.append(contentsOf: snapshots)
            return true
        }
    }
}

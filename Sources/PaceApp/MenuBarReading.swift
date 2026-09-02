import PaceCore

/// One resolved menu-bar slot, ready to draw.
///
/// `usedFraction` is nil when the chosen quota has no current reading. That is
/// kept distinct from zero: an untouched limit and an unavailable one look the
/// same as a number but mean opposite things, so the status item shows a dash
/// rather than "0%".
struct MenuBarReading: Equatable {
    let providerID: ProviderID
    let label: String?
    let usedFraction: Double?

    var isAvailable: Bool {
        usedFraction != nil
    }
}

extension PacePresentationModel {
    /// The readings for the configured menu-bar slots.
    ///
    /// A slot whose provider has no account is dropped, because showing a
    /// permanently blank reading for something that is not set up is noise. A
    /// slot whose provider is present but whose quota is missing is kept and
    /// marked unavailable, because that is a state worth seeing.
    var menuBarReadings: [MenuBarReading] {
        preferences.menuBar.slots.compactMap(reading(for:))
    }

    private func reading(for slot: MenuBarUsageSlot) -> MenuBarReading? {
        guard let account = selectedAccount(for: slot.providerID) else {
            return nil
        }
        let snapshots = snapshots(for: account.id)

        guard let bucketID = slot.bucketID else {
            return MenuBarReading(
                providerID: slot.providerID,
                label: nil,
                usedFraction: headlineUsage(for: slot.providerID),
            )
        }

        // The chosen bucket is not swapped for another when it goes missing.
        // Keeping the slot and reporting it unavailable says the provider
        // stopped returning that window, which the fallback would hide.
        let match = snapshots.first { $0.id.bucketID == bucketID }
        return MenuBarReading(
            providerID: slot.providerID,
            label: match?.label,
            usedFraction: match?.usedFraction,
        )
    }

    /// The quotas a slot can be pointed at, for the settings picker.
    func availableBuckets(for providerID: ProviderID) -> [(id: BucketID, label: String)] {
        guard let account = selectedAccount(for: providerID) else {
            return []
        }
        return snapshots(for: account.id).map { ($0.id.bucketID, $0.label) }
    }
}

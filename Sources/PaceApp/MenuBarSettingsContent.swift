import PaceCore
import SwiftUI

/// Chooses what the menu-bar status item shows.
///
/// Two slots at most. Each names a provider and one of that provider's quotas,
/// because providers do not report the same windows and "session" means a
/// different span to each of them.
struct MenuBarSettingsContent: View {
    @Bindable var model: PacePresentationModel

    var body: some View {
        ForEach(0 ..< MenuBarPresentation.slotLimit, id: \.self) { index in
            slotPicker(at: index)
        }

        Picker(
            "Colour",
            selection: Binding(
                get: { model.preferences.menuBar.tint },
                set: model.setMenuBarTint,
            ),
        ) {
            ForEach(MenuBarTint.allCases, id: \.self) { tint in
                Text(tint.label).tag(tint)
            }
        }
        .disabled(model.preferences.menuBar.slots.isEmpty)

        Toggle(
            "Show percent sign",
            isOn: Binding(
                get: { model.preferences.menuBar.showsPercentSign },
                set: model.setMenuBarShowsPercentSign,
            ),
        )
        .disabled(model.preferences.menuBar.slots.isEmpty)
    }

    @ViewBuilder
    private func slotPicker(at index: Int) -> some View {
        let slots = model.preferences.menuBar.slots
        let slot: MenuBarUsageSlot? = index < slots.count ? slots[index] : nil

        Picker(
            index == 0 ? "Menu bar shows" : "And",
            selection: Binding(
                get: { slot.map(SlotSelection.quota) ?? .none },
                set: { selection in
                    model.setMenuBarSlot(selection.slot, at: index)
                },
            ),
        ) {
            Text("Nothing").tag(SlotSelection.none)
            ForEach(model.visibleProviderIDs, id: \.self) { providerID in
                let buckets = model.availableBuckets(for: providerID)
                let name = ProviderStyle.resolve(providerID).name
                if buckets.isEmpty {
                    // No quotas have been read yet, so the provider can still
                    // be chosen and will use whichever window it reports.
                    Text(name).tag(
                        SlotSelection.quota(MenuBarUsageSlot(providerID: providerID)),
                    )
                } else {
                    ForEach(buckets, id: \.id) { bucket in
                        Text("\(name) · \(bucket.label)").tag(
                            SlotSelection.quota(
                                MenuBarUsageSlot(
                                    providerID: providerID,
                                    bucketID: bucket.id,
                                ),
                            ),
                        )
                    }
                }
            }
        }
        // The second slot is only offered once the first is set, so the two
        // cannot be filled out of order and leave a gap.
        .disabled(index > slots.count)
    }
}

/// A slot picker's selection, which may be empty.
private enum SlotSelection: Hashable {
    case none
    case quota(MenuBarUsageSlot)

    var slot: MenuBarUsageSlot? {
        switch self {
        case .none:
            nil
        case let .quota(slot):
            slot
        }
    }
}

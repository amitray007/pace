import PaceCore

/// What the menu-bar status item is pointed at.
extension PacePresentationModel {
    /// Points a menu-bar slot at a provider and quota.
    ///
    /// Slots are addressed by index so the two keep their left-to-right order
    /// as they are edited. Writing past the end appends, which is how the
    /// second slot is added.
    func setMenuBarSlot(_ slot: MenuBarUsageSlot?, at index: Int) {
        updatePreferences { preferences in
            var slots = preferences.menuBar.slots
            switch (slot, index < slots.count) {
            case let (.some(slot), true):
                slots[index] = slot
            case let (.some(slot), false)
                where slots.count < MenuBarPresentation.slotLimit:
                slots.append(slot)
            case (.none, true):
                slots.remove(at: index)
            default:
                return
            }
            preferences.menuBar.slots = slots
        }
    }

    func setMenuBarTint(_ tint: MenuBarTint) {
        updatePreferences { $0.menuBar.tint = tint }
    }

    /// Hides account addresses across every surface.
    func setHidesAccountIdentity(_ hidesAccountIdentity: Bool) {
        updatePreferences { $0.hidesAccountIdentity = hidesAccountIdentity }
    }

    func setMenuBarShowsPercentSign(_ showsPercentSign: Bool) {
        updatePreferences { $0.menuBar.showsPercentSign = showsPercentSign }
    }
}

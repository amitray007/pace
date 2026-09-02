import Foundation

/// One usage reading shown in the menu bar, as a provider and a chosen quota.
///
/// The bucket is optional because providers do not agree on which windows they
/// report, and a user who has not chosen one still wants a sensible reading.
/// When it is nil the surface falls back to that provider's headline quota.
///
/// A bucket that the provider stops returning is not silently swapped for
/// another. The slot keeps the choice and the surface shows that the reading is
/// unavailable, because a number under the wrong label is worse than no number.
public struct MenuBarUsageSlot: Codable, Equatable, Hashable, Sendable {
    public var providerID: ProviderID
    public var bucketID: BucketID?

    public init(providerID: ProviderID, bucketID: BucketID? = nil) {
        self.providerID = providerID
        self.bucketID = bucketID
    }
}

/// How the status item is coloured.
public enum MenuBarTint: String, CaseIterable, Codable, Sendable {
    /// One tone, tinted by macOS to match the menu bar, like the system's own
    /// items. Correct in both light and dark bars without being told which.
    case monochrome
    /// Each provider's brand colour. Identifies the slots at a glance, at the
    /// cost of standing out from the surrounding items.
    case brand

    public var label: String {
        switch self {
        case .monochrome:
            "Match menu bar"
        case .brand:
            "Provider colours"
        }
    }
}

/// What the menu-bar status item shows.
public struct MenuBarPresentation: Codable, Equatable, Sendable {
    /// At most two readings fit beside each other before the status item is
    /// wider than the clock. Beyond that the panel is the better surface.
    public static let slotLimit = 2

    /// The status item shows a gauge glyph alone until a slot is configured.
    public static let defaultSlots: [MenuBarUsageSlot] = []

    public var slots: [MenuBarUsageSlot]
    public var showsPercentSign: Bool
    public var tint: MenuBarTint

    public init(
        slots: [MenuBarUsageSlot] = Self.defaultSlots,
        showsPercentSign: Bool = false,
        tint: MenuBarTint = .monochrome,
    ) {
        self.slots = Array(slots.prefix(Self.slotLimit))
        self.showsPercentSign = showsPercentSign
        self.tint = tint
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            slots: container.decodeIfPresent([MenuBarUsageSlot].self, forKey: .slots)
                ?? Self.defaultSlots,
            showsPercentSign: container.decodeIfPresent(Bool.self, forKey: .showsPercentSign)
                ?? false,
            tint: container.decodeIfPresent(MenuBarTint.self, forKey: .tint) ?? .monochrome,
        )
    }
}

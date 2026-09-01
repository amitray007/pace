import Foundation

public enum PaceSurfaceMode: String, CaseIterable, Codable, Sendable {
    case menuBar
    case edgeRail
    case both

    public var showsMenuBar: Bool {
        self != .edgeRail
    }

    public var showsEdgeRail: Bool {
        self != .menuBar
    }
}

public enum RailEdge: String, CaseIterable, Codable, Sendable {
    case left
    case right
}

/// How large the edge rail is drawn, as a multiplier on the reference size.
///
/// The silhouette is defined by ratios of the rail's width, so scaling changes
/// the rail's size without changing its shape. The range is bounded because the
/// reference proportions stop being legible outside it: the percentage labels
/// crowd their rings when small, and the rail starts to intrude on window
/// content when large.
public enum RailScale: String, CaseIterable, Codable, Sendable {
    case small
    case medium
    case large

    /// The fraction of the rail's fixed canvas that the reference size fills.
    /// A step may not scale past this, or the contour would clip instead of
    /// growing.
    public static let canvasFraction = 0.86

    /// The largest multiplier that still fits inside the canvas.
    public static var maximumMultiplier: Double {
        1 / canvasFraction
    }

    public var multiplier: Double {
        switch self {
        case .small:
            0.86
        case .medium:
            1.0
        case .large:
            // The canvas is fixed, so the largest step is the one that still
            // fits inside it.
            1.16
        }
    }
}

public enum RailVerticalPosition: String, CaseIterable, Codable, Sendable {
    case top
    case center
    case bottom
}

public enum RailActivationMode: String, CaseIterable, Codable, Sendable {
    case modifierHover
    case clickHandle
    case dwellHover
}

public enum RailActivationModifier: String, CaseIterable, Codable, Sendable {
    case shift
    case option
    case control
    case command
}

public struct PacePreferences: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    public static let defaultProviderOrder: [ProviderID] = [
        .claude,
        .codex,
        .cursor,
        .grok,
        .githubCopilot,
    ]

    /// The dwell before a hover opens the rail.
    ///
    /// In the reference recording the rail starts opening while the pointer is
    /// still travelling toward the edge, well before it arrives, so the design
    /// intent is to open on approach rather than to make the user wait. The
    /// lower bound is therefore small enough to feel immediate while still
    /// rejecting a pointer that merely sweeps past the edge.
    public static let dwellDelayRange: ClosedRange<TimeInterval> = 0.05 ... 2

    /// Small enough that the rail appears to answer the pointer immediately.
    public static let defaultDwellDelay: TimeInterval = 0.06

    public var version: Int
    public var surfaceMode: PaceSurfaceMode
    public var railEdge: RailEdge
    public var railScale: RailScale
    public var selectedDisplayID: String?
    public var railVerticalPosition: RailVerticalPosition
    public var activationMode: RailActivationMode
    public var activationModifier: RailActivationModifier
    public var dwellDelay: TimeInterval
    public var dismissalDelay: TimeInterval
    public var hideRailInFullScreen: Bool
    public var notificationPolicy: PaceNotificationPolicy
    public var providerOrder: [ProviderID]

    public init(
        version: Int = Self.currentVersion,
        surfaceMode: PaceSurfaceMode = .menuBar,
        railEdge: RailEdge = .right,
        railScale: RailScale = .medium,
        selectedDisplayID: String? = nil,
        railVerticalPosition: RailVerticalPosition = .center,
        activationMode: RailActivationMode = .dwellHover,
        activationModifier: RailActivationModifier = .shift,
        dwellDelay: TimeInterval = Self.defaultDwellDelay,
        dismissalDelay: TimeInterval = 0.4,
        hideRailInFullScreen: Bool = true,
        notificationPolicy: PaceNotificationPolicy = .disabled,
        providerOrder: [ProviderID] = Self.defaultProviderOrder,
    ) {
        self.version = version
        self.surfaceMode = surfaceMode
        self.railEdge = railEdge
        self.railScale = railScale
        self.selectedDisplayID = selectedDisplayID
        self.railVerticalPosition = railVerticalPosition
        self.activationMode = activationMode
        self.activationModifier = activationModifier
        self.dwellDelay = Self.clamped(dwellDelay, to: Self.dwellDelayRange)
        self.dismissalDelay = Self.clamped(dismissalDelay, to: 0.1 ... 2)
        self.hideRailInFullScreen = hideRailInFullScreen
        self.notificationPolicy = notificationPolicy
        self.providerOrder = Self.normalizedProviderOrder(providerOrder)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try container.value(.version, default: 1)
        let storedActivationMode = try container.decodeIfPresent(
            RailActivationMode.self,
            forKey: .activationMode,
        )
        // Version 1 shipped modifier-hover as the default. A stored value that
        // merely matches that default was never a deliberate choice, so it
        // migrates to the current default rather than persisting.
        let migratesModifierHoverDefault = storedVersion < 2 &&
            storedActivationMode == .modifierHover
        try self.init(
            version: max(storedVersion, Self.currentVersion),
            surfaceMode: container.value(.surfaceMode, default: .menuBar),
            railEdge: container.value(.railEdge, default: .right),
            railScale: container.value(.railScale, default: .medium),
            selectedDisplayID: container.decodeIfPresent(
                String.self,
                forKey: .selectedDisplayID,
            ),
            railVerticalPosition: container.value(.railVerticalPosition, default: .center),
            activationMode: migratesModifierHoverDefault
                ? .dwellHover
                : storedActivationMode ?? .dwellHover,
            activationModifier: container.value(.activationModifier, default: .shift),
            dwellDelay: migratesModifierHoverDefault
                ? Self.defaultDwellDelay
                : container.value(.dwellDelay, default: Self.defaultDwellDelay),
            dismissalDelay: container.value(.dismissalDelay, default: 0.4),
            hideRailInFullScreen: container.value(
                .hideRailInFullScreen,
                default: true,
            ),
            notificationPolicy: container.value(.notificationPolicy, default: .disabled),
            providerOrder: container.value(
                .providerOrder,
                default: Self.defaultProviderOrder,
            ),
        )
    }

    private static func clamped(
        _ value: TimeInterval,
        to range: ClosedRange<TimeInterval>,
    ) -> TimeInterval {
        guard value.isFinite else {
            return range.lowerBound
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func normalizedProviderOrder(_ providerIDs: [ProviderID]) -> [ProviderID] {
        var seen = Set<ProviderID>()
        let uniqueProviderIDs = providerIDs.filter { seen.insert($0).inserted }
        return uniqueProviderIDs + defaultProviderOrder.filter { seen.insert($0).inserted }
    }
}

private extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `default` when the key is absent.
    ///
    /// Preferences files are written by older builds and edited by hand, so
    /// every key has to be optional with a default. Naming that pattern once
    /// keeps the decoder readable as a list of keys and their defaults.
    func value<Value: Decodable>(
        _ key: Key,
        default defaultValue: Value,
    ) throws -> Value {
        try decodeIfPresent(Value.self, forKey: key) ?? defaultValue
    }
}

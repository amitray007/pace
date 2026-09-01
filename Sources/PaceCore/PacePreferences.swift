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
    public static let currentVersion = 1
    public static let defaultProviderOrder: [ProviderID] = [
        .claude,
        .codex,
        .cursor,
        .grok,
        .githubCopilot,
    ]

    public var version: Int
    public var surfaceMode: PaceSurfaceMode
    public var railEdge: RailEdge
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
        selectedDisplayID: String? = nil,
        railVerticalPosition: RailVerticalPosition = .center,
        activationMode: RailActivationMode = .modifierHover,
        activationModifier: RailActivationModifier = .shift,
        dwellDelay: TimeInterval = 0.6,
        dismissalDelay: TimeInterval = 0.4,
        hideRailInFullScreen: Bool = true,
        notificationPolicy: PaceNotificationPolicy = .disabled,
        providerOrder: [ProviderID] = Self.defaultProviderOrder,
    ) {
        self.version = version
        self.surfaceMode = surfaceMode
        self.railEdge = railEdge
        self.selectedDisplayID = selectedDisplayID
        self.railVerticalPosition = railVerticalPosition
        self.activationMode = activationMode
        self.activationModifier = activationModifier
        self.dwellDelay = Self.clamped(dwellDelay, to: 0.2 ... 2)
        self.dismissalDelay = Self.clamped(dismissalDelay, to: 0.1 ... 2)
        self.hideRailInFullScreen = hideRailInFullScreen
        self.notificationPolicy = notificationPolicy
        self.providerOrder = Self.normalizedProviderOrder(providerOrder)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            version: container.decodeIfPresent(Int.self, forKey: .version)
                ?? Self.currentVersion,
            surfaceMode: container.decodeIfPresent(
                PaceSurfaceMode.self,
                forKey: .surfaceMode,
            ) ?? .menuBar,
            railEdge: container.decodeIfPresent(RailEdge.self, forKey: .railEdge) ?? .right,
            selectedDisplayID: container.decodeIfPresent(
                String.self,
                forKey: .selectedDisplayID,
            ),
            railVerticalPosition: container.decodeIfPresent(
                RailVerticalPosition.self,
                forKey: .railVerticalPosition,
            ) ?? .center,
            activationMode: container.decodeIfPresent(
                RailActivationMode.self,
                forKey: .activationMode,
            ) ?? .modifierHover,
            activationModifier: container.decodeIfPresent(
                RailActivationModifier.self,
                forKey: .activationModifier,
            ) ?? .shift,
            dwellDelay: container.decodeIfPresent(TimeInterval.self, forKey: .dwellDelay)
                ?? 0.6,
            dismissalDelay: container.decodeIfPresent(
                TimeInterval.self,
                forKey: .dismissalDelay,
            ) ?? 0.4,
            hideRailInFullScreen: container.decodeIfPresent(
                Bool.self,
                forKey: .hideRailInFullScreen,
            ) ?? true,
            notificationPolicy: container.decodeIfPresent(
                PaceNotificationPolicy.self,
                forKey: .notificationPolicy,
            ) ?? .disabled,
            providerOrder: container.decodeIfPresent(
                [ProviderID].self,
                forKey: .providerOrder,
            ) ?? Self.defaultProviderOrder,
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

import Foundation

public enum RailPointerRegion: Equatable, Sendable {
    case outside
    case hotspot
    case rail(providerIndex: Int?)
    case detail
    case travelCorridor
    case settings

    var keepsRailOpen: Bool {
        switch self {
        case .rail, .detail, .travelCorridor, .settings:
            true
        case .outside, .hotspot:
            false
        }
    }
}

public struct RailPointerSample: Equatable, Sendable {
    public let horizontalPosition: Double
    public let verticalPosition: Double
    public let region: RailPointerRegion

    /// Distance from the pointer to the active screen edge, in points.
    ///
    /// Supplied by the caller because only it knows which edge the rail is on.
    /// The engine uses the change in this distance to tell a pointer arriving
    /// at the edge from one sweeping along it.
    public let edgeDistance: Double

    public init(
        horizontalPosition: Double,
        verticalPosition: Double,
        region: RailPointerRegion,
        edgeDistance: Double = 0,
    ) {
        self.horizontalPosition = horizontalPosition
        self.verticalPosition = verticalPosition
        self.region = region
        self.edgeDistance = edgeDistance
    }
}

public struct RailActivationConfiguration: Equatable, Sendable {
    public var mode: RailActivationMode
    public var dwellDelay: TimeInterval
    public var dismissalDelay: TimeInterval
    public var providerHoverDelay: TimeInterval
    public var scrollSuppressionDuration: TimeInterval
    public var dragReleaseSuppressionDuration: TimeInterval
    public var fastPointerSuppressionDuration: TimeInterval
    public var fastEdgeVelocityThreshold: Double

    /// How much the pointer must still be closing on the edge, per sample, for
    /// fast vertical movement to count as an approach rather than a pass-by.
    public var edgeApproachTolerance: Double

    public init(
        mode: RailActivationMode,
        dwellDelay: TimeInterval,
        dismissalDelay: TimeInterval,
        providerHoverDelay: TimeInterval = 0.08,
        scrollSuppressionDuration: TimeInterval = 0.45,
        dragReleaseSuppressionDuration: TimeInterval = 0.2,
        fastPointerSuppressionDuration: TimeInterval = 0.25,
        fastEdgeVelocityThreshold: Double = 1600,
        edgeApproachTolerance: Double = 0.5,
    ) {
        self.mode = mode
        self.dwellDelay = dwellDelay
        self.dismissalDelay = dismissalDelay
        self.providerHoverDelay = providerHoverDelay
        self.scrollSuppressionDuration = scrollSuppressionDuration
        self.dragReleaseSuppressionDuration = dragReleaseSuppressionDuration
        self.fastPointerSuppressionDuration = fastPointerSuppressionDuration
        self.fastEdgeVelocityThreshold = fastEdgeVelocityThreshold
        self.edgeApproachTolerance = edgeApproachTolerance
    }
}

public enum RailActivationPhase: Equatable, Sendable {
    case collapsed
    case intentPending
    case revealed
    case dismissalPending
}

public enum RailActivationEvent: Equatable, Sendable {
    case pointerMoved(RailPointerSample)
    case modifierChanged(isActive: Bool)
    case mouseButtonsChanged(isDown: Bool)
    case scroll
    case primaryClick(region: RailPointerRegion)
    case tick
    case fullScreenChanged(isExcluded: Bool)
    case suspensionChanged(isSuspended: Bool)
}

public enum RailActivationAction: Equatable, Sendable {
    case reveal
    case dismiss
    case selectProvider(index: Int)
    case openSettings
}

public struct RailActivationEngine: Sendable {
    public private(set) var phase: RailActivationPhase = .collapsed
    public private(set) var pointerRegion: RailPointerRegion = .outside
    public private(set) var configuration: RailActivationConfiguration

    private var modifierActive = false
    private var mouseButtonDown = false
    private var fullScreenExcluded = false
    private var suspended = false
    private var intentStartedAt: TimeInterval?
    private var dismissalStartedAt: TimeInterval?
    private var pendingProvider: (index: Int, startedAt: TimeInterval)?
    private var lastPointerSample: (sample: RailPointerSample, time: TimeInterval)?
    private var suppressedUntil: TimeInterval = 0

    public init(configuration: RailActivationConfiguration) {
        self.configuration = configuration
    }

    public mutating func replaceConfiguration(_ configuration: RailActivationConfiguration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        resetPendingIntent()
    }

    public mutating func synchronizePresentation(isRevealed: Bool) {
        if isRevealed {
            if phase == .collapsed || phase == .intentPending {
                phase = .revealed
                intentStartedAt = nil
            }
        } else if phase != .collapsed {
            _ = dismiss()
        }
    }

    public mutating func handle(
        _ event: RailActivationEvent,
        at time: TimeInterval,
    ) -> [RailActivationAction] {
        switch event {
        case let .pointerMoved(sample):
            return handlePointerMoved(sample, at: time)
        case let .modifierChanged(isActive):
            guard modifierActive != isActive else {
                return []
            }
            modifierActive = isActive
            guard phase == .collapsed || phase == .intentPending else {
                return []
            }
            return evaluateCollapsedActivation(at: time)
        case let .mouseButtonsChanged(isDown):
            return handleMouseButtonsChanged(isDown: isDown, at: time)
        case .scroll:
            suppressedUntil = max(suppressedUntil, time + configuration.scrollSuppressionDuration)
            resetPendingIntent()
            return []
        case let .primaryClick(region):
            return handlePrimaryClick(in: region, at: time)
        case .tick:
            return handleTick(at: time)
        case let .fullScreenChanged(isExcluded):
            fullScreenExcluded = isExcluded
            return handleAvailabilityChange()
        case let .suspensionChanged(isSuspended):
            suspended = isSuspended
            return handleAvailabilityChange()
        }
    }

    private mutating func handlePointerMoved(
        _ sample: RailPointerSample,
        at time: TimeInterval,
    ) -> [RailActivationAction] {
        let isFastEdgeMovement = passesAlongEdge(for: sample, at: time)
        pointerRegion = sample.region
        lastPointerSample = (sample, time)
        if isFastEdgeMovement {
            suppressedUntil = max(
                suppressedUntil,
                time + configuration.fastPointerSuppressionDuration,
            )
            resetPendingIntent()
        }

        switch phase {
        case .collapsed, .intentPending:
            return evaluateCollapsedActivation(at: time)
        case .revealed, .dismissalPending:
            updateRevealedPointerIntent(at: time)
            return []
        }
    }

    private mutating func handleMouseButtonsChanged(
        isDown: Bool,
        at time: TimeInterval,
    ) -> [RailActivationAction] {
        guard mouseButtonDown != isDown else {
            return []
        }
        mouseButtonDown = isDown
        resetPendingIntent()
        if !isDown {
            suppressedUntil = max(
                suppressedUntil,
                time + configuration.dragReleaseSuppressionDuration,
            )
        }
        return []
    }

    private mutating func handlePrimaryClick(
        in region: RailPointerRegion,
        at time: TimeInterval,
    ) -> [RailActivationAction] {
        if phase == .collapsed || phase == .intentPending {
            guard configuration.mode == .clickHandle,
                  region == .hotspot,
                  canActivate(at: time)
            else {
                return []
            }
            return reveal()
        }

        switch region {
        case let .rail(providerIndex?):
            pendingProvider = nil
            return [.selectProvider(index: providerIndex)]
        case .settings:
            return [.openSettings]
        case .outside, .hotspot:
            return dismiss()
        case .rail, .detail, .travelCorridor:
            return []
        }
    }

    private mutating func handleTick(at time: TimeInterval) -> [RailActivationAction] {
        // A settled pointer sends no more move events, so the tick must rerun
        // the collapsed evaluation. Without it, a pointer that arrived during
        // a suppression window (scroll, drag release, or a fast sweep that
        // ended on the handle) waited in the hotspot forever, and only another
        // wiggle would start the dwell.
        if phase == .collapsed || phase == .intentPending, pointerRegion == .hotspot {
            let actions = evaluateCollapsedActivation(at: time)
            if !actions.isEmpty {
                return actions
            }
        }
        if dwellIntentIsReady(at: time) {
            return reveal()
        }
        if dismissalIntentIsReady(at: time) {
            return dismiss()
        }
        if let pendingProvider, providerIntentIsReady(at: time) {
            self.pendingProvider = nil
            return [.selectProvider(index: pendingProvider.index)]
        }
        return []
    }

    private mutating func evaluateCollapsedActivation(
        at time: TimeInterval,
    ) -> [RailActivationAction] {
        guard pointerRegion == .hotspot, canActivate(at: time) else {
            resetPendingIntent()
            return []
        }
        switch configuration.mode {
        case .modifierHover:
            return modifierActive ? reveal() : []
        case .clickHandle:
            return []
        case .dwellHover:
            if intentStartedAt == nil {
                intentStartedAt = time
                phase = .intentPending
            }
            return []
        }
    }

    private mutating func updateRevealedPointerIntent(at time: TimeInterval) {
        guard pointerRegion.keepsRailOpen else {
            if dismissalStartedAt == nil {
                dismissalStartedAt = time
            }
            phase = .dismissalPending
            pendingProvider = nil
            return
        }
        dismissalStartedAt = nil
        phase = .revealed
        guard case let .rail(providerIndex?) = pointerRegion else {
            pendingProvider = nil
            return
        }
        if pendingProvider?.index != providerIndex {
            pendingProvider = (providerIndex, time)
        }
    }

    private func canActivate(at time: TimeInterval) -> Bool {
        !mouseButtonDown && !fullScreenExcluded && !suspended && time >= suppressedUntil
    }

    private func deadlineReached(
        start: TimeInterval,
        duration: TimeInterval,
        at time: TimeInterval,
    ) -> Bool {
        time + 1e-9 >= start + duration
    }

    /// Whether the pointer is sweeping along the edge rather than arriving at
    /// it.
    ///
    /// The rule this implements is "do not activate while the pointer is moving
    /// rapidly along the edge". Speed alone cannot express that: reaching the
    /// edge quickly is the normal way to reach it, and judging on vertical
    /// speed alone suppressed every brisk approach.
    ///
    /// The distinction is direction. A pointer travelling along the edge keeps
    /// moving vertically while its horizontal distance to the edge stays put. A
    /// pointer arriving is still closing that distance, or has already stopped.
    /// Only the first is a pass-by.
    private func passesAlongEdge(
        for sample: RailPointerSample,
        at time: TimeInterval,
    ) -> Bool {
        guard sample.region == .hotspot,
              let lastPointerSample,
              lastPointerSample.sample.region == .hotspot
        else {
            return false
        }
        let elapsed = time - lastPointerSample.time
        guard elapsed > 0 else {
            return false
        }
        let verticalVelocity = abs(
            sample.verticalPosition - lastPointerSample.sample.verticalPosition,
        ) / elapsed
        guard verticalVelocity >= configuration.fastEdgeVelocityThreshold else {
            return false
        }
        // Still closing on the edge, so this is an approach that happens to be
        // quick rather than a pass-by.
        let closing = lastPointerSample.sample.edgeDistance - sample.edgeDistance
        return closing <= configuration.edgeApproachTolerance
    }

    private func dwellIntentIsReady(at time: TimeInterval) -> Bool {
        guard phase == .intentPending, let intentStartedAt else {
            return false
        }
        return deadlineReached(
            start: intentStartedAt,
            duration: configuration.dwellDelay,
            at: time,
        ) && canActivate(at: time) && pointerRegion == .hotspot
    }

    private func dismissalIntentIsReady(at time: TimeInterval) -> Bool {
        guard phase == .dismissalPending, let dismissalStartedAt else {
            return false
        }
        return deadlineReached(
            start: dismissalStartedAt,
            duration: configuration.dismissalDelay,
            at: time,
        )
    }

    private func providerIntentIsReady(at time: TimeInterval) -> Bool {
        guard let pendingProvider else {
            return false
        }
        return deadlineReached(
            start: pendingProvider.startedAt,
            duration: configuration.providerHoverDelay,
            at: time,
        )
    }

    private mutating func handleAvailabilityChange() -> [RailActivationAction] {
        resetPendingIntent()
        if fullScreenExcluded || suspended, phase != .collapsed {
            return dismiss()
        }
        return []
    }

    private mutating func reveal() -> [RailActivationAction] {
        phase = .revealed
        intentStartedAt = nil
        dismissalStartedAt = nil
        pendingProvider = nil
        return [.reveal]
    }

    private mutating func dismiss() -> [RailActivationAction] {
        phase = .collapsed
        intentStartedAt = nil
        dismissalStartedAt = nil
        pendingProvider = nil
        return [.dismiss]
    }

    private mutating func resetPendingIntent() {
        intentStartedAt = nil
        if phase == .intentPending {
            phase = .collapsed
        }
    }
}

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

    public init(
        horizontalPosition: Double,
        verticalPosition: Double,
        region: RailPointerRegion,
    ) {
        self.horizontalPosition = horizontalPosition
        self.verticalPosition = verticalPosition
        self.region = region
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

    public init(
        mode: RailActivationMode,
        dwellDelay: TimeInterval,
        dismissalDelay: TimeInterval,
        providerHoverDelay: TimeInterval = 0.08,
        scrollSuppressionDuration: TimeInterval = 0.45,
        dragReleaseSuppressionDuration: TimeInterval = 0.2,
        fastPointerSuppressionDuration: TimeInterval = 0.25,
        fastEdgeVelocityThreshold: Double = 900,
    ) {
        self.mode = mode
        self.dwellDelay = dwellDelay
        self.dismissalDelay = dismissalDelay
        self.providerHoverDelay = providerHoverDelay
        self.scrollSuppressionDuration = scrollSuppressionDuration
        self.dragReleaseSuppressionDuration = dragReleaseSuppressionDuration
        self.fastPointerSuppressionDuration = fastPointerSuppressionDuration
        self.fastEdgeVelocityThreshold = fastEdgeVelocityThreshold
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
        let isFastEdgeMovement = fastEdgeMovement(for: sample, at: time)
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

    private func fastEdgeMovement(
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
        return verticalVelocity >= configuration.fastEdgeVelocityThreshold
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

import AppKit
import PaceCore

@MainActor
final class RailInteractionController {
    let model: PacePresentationModel
    weak var visualPanel: NSPanel?
    private var engine: RailActivationEngine
    private var globalMonitor: Any?
    private var timer: Timer?
    private var targetPanels: [RailInteractionPanel] = []
    private var isScreenExcluded = false

    init(model: PacePresentationModel, visualPanel: NSPanel) {
        self.model = model
        self.visualPanel = visualPanel
        engine = RailActivationEngine(configuration: Self.configuration(for: model.preferences))
    }

    isolated deinit {
        removeEventMonitors()
        timer?.invalidate()
        targetPanels.forEach { $0.orderOut(nil) }
    }

    func synchronize() {
        engine.replaceConfiguration(Self.configuration(for: model.preferences))
        engine.synchronizePresentation(isRevealed: model.railPreviewState != .mini)
        if model.isRailVisible, !isScreenExcluded {
            installEventMonitors()
        } else {
            removeEventMonitors()
        }
        synchronizeTargetPanels()
        synchronizeTimer()
    }

    func screenAvailabilityChanged(isFullScreenExcluded: Bool) {
        isScreenExcluded = isFullScreenExcluded
        perform(
            engine.handle(
                .fullScreenChanged(isExcluded: isFullScreenExcluded),
                at: ProcessInfo.processInfo.systemUptime,
            ),
        )
        synchronize()
    }

    private func installEventMonitors() {
        guard globalMonitor == nil else {
            return
        }
        let eventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseUp,
            .rightMouseUp,
            .otherMouseUp,
            .scrollWheel,
        ]
        globalMonitor = NSEvent
            .addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
                Self.onMainActor { self?.handle(event) }
            }
    }

    /// Runs `work` on the main actor with the least delay available.
    ///
    /// Event monitors and main run loop timers already call back on the main
    /// thread. Wrapping each callback in a `Task` queued it behind whatever
    /// else the main actor had pending, which added a run loop turn between
    /// the pointer arriving and the rail answering. When the callback is
    /// already on the main thread it runs inline; otherwise it is queued.
    private nonisolated static func onMainActor(
        _ work: sending @escaping @MainActor () -> Void,
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in
                work()
            }
        }
    }

    private func removeEventMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        let time = ProcessInfo.processInfo.systemUptime
        let location = NSEvent.mouseLocation
        let region = pointerRegion(at: location)
        let modifierIsActive = event.modifierFlags
            .contains(model.preferences.activationModifier.flag)
        perform(engine.handle(.modifierChanged(isActive: modifierIsActive), at: time))

        switch event.type {
        case .mouseMoved:
            handlePointerMoved(to: location, region: region, at: time)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            perform(engine.handle(.mouseButtonsChanged(isDown: true), at: time))
            handlePointerMoved(to: location, region: region, at: time)
        case .leftMouseDown:
            if event.window is RailInteractionPanel {
                perform(engine.handle(.primaryClick(region: region), at: time))
            } else {
                perform(engine.handle(.mouseButtonsChanged(isDown: true), at: time))
                perform(engine.handle(.primaryClick(region: region), at: time))
            }
        case .rightMouseDown, .otherMouseDown:
            perform(engine.handle(.mouseButtonsChanged(isDown: true), at: time))
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            perform(engine.handle(.mouseButtonsChanged(isDown: false), at: time))
        case .scrollWheel:
            perform(engine.handle(.scroll, at: time))
        default:
            break
        }
        synchronizeTimer()
    }

    private func handlePointerMoved(
        to location: NSPoint,
        region: RailPointerRegion,
        at time: TimeInterval,
    ) {
        let sample = RailPointerSample(
            horizontalPosition: location.x,
            verticalPosition: location.y,
            region: region,
            edgeDistance: edgeDistance(to: location),
        )
        perform(engine.handle(.pointerMoved(sample), at: time))
    }

    /// How far the pointer is from the edge the rail lives on.
    private func edgeDistance(to location: NSPoint) -> Double {
        guard let screen = visualPanel?.screen ?? NSScreen.main else {
            return 0
        }
        return model.preferences.railEdge == .right
            ? max(screen.frame.maxX - location.x, 0)
            : max(location.x - screen.frame.minX, 0)
    }

    private func perform(_ actions: [RailActivationAction]) {
        guard !actions.isEmpty else {
            return
        }
        for action in actions {
            switch action {
            case .reveal:
                model.showRail()
            case .dismiss:
                model.collapseRail()
            case let .selectProvider(index):
                let providerIDs = Array(model.visibleProviderIDs
                    .prefix(EdgeRailGeometry.maximumProviderRows))
                guard providerIDs.indices.contains(index) else {
                    continue
                }
                model.showRailDetails(for: providerIDs[index])
            case .openSettings:
                model.collapseRail()
                PaceSettingsPresenter.show()
            }
        }
        synchronizeTargetPanels()
        synchronizeTimer()
    }

    private func synchronizeTimer() {
        let needsTimer = model.isRailVisible && !isScreenExcluded &&
            (engine.phase != .collapsed || engine.pointerRegion == .hotspot)
        guard needsTimer else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else {
            return
        }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Self.onMainActor { self?.handleTimerTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// How often deadlines and polled input state are checked while the
    /// pointer is on the handle or the rail is open.
    ///
    /// The dwell, provider hover, and dismissal deadlines only fire on a tick,
    /// and so does a modifier pressed over a resting pointer. At the previous
    /// 50 ms each of those landed up to 50 ms late, which is a third of the
    /// reveal itself. One display frame keeps the error under what a 120 Hz
    /// panel can show. The tick reads two event-state values and runs the
    /// engine, so the extra wakeups are not measurable, and the timer only
    /// exists during an interaction.
    private static let tickInterval: TimeInterval = 1.0 / 120.0

    private func handleTimerTick() {
        let time = ProcessInfo.processInfo.systemUptime
        let modifierIsActive = NSEvent.modifierFlags.contains(
            model.preferences.activationModifier.flag,
        )
        perform(engine.handle(.modifierChanged(isActive: modifierIsActive), at: time))
        perform(
            engine.handle(
                .mouseButtonsChanged(isDown: NSEvent.pressedMouseButtons != 0),
                at: time,
            ),
        )
        perform(engine.handle(.tick, at: time))
        synchronizeTimer()
    }

    private func synchronizeTargetPanels() {
        guard model.isRailVisible, !isScreenExcluded else {
            removeTargetPanels()
            return
        }
        let targets = interactionTargets.filter { !$0.frame.isEmpty }
        // Interaction panels are real windows. Recreating them while nothing
        // moved makes the window server churn on every model refresh and
        // briefly stacks old and new panels, so identical targets keep their
        // panels. When only the geometry moved, as it does on every provider
        // switch, the same panels are moved instead of being replaced, which
        // spares the window server three window creations per switch.
        // Opening the detail adds one panel behind the two the rail already
        // has, so panels are matched by position and only the difference is
        // created or removed.
        for (index, target) in targets.enumerated() {
            if targetPanels.indices.contains(index) {
                let panel = targetPanels[index]
                if panel.targetAccessibilityLabel == target.accessibilityLabel {
                    if panel.frame != target.frame {
                        panel.setFrame(target.frame, display: false)
                    }
                    continue
                }
                panel.orderOut(nil)
                targetPanels[index] = makeTargetPanel(for: target)
            } else {
                targetPanels.append(makeTargetPanel(for: target))
            }
        }
        while targetPanels.count > targets.count {
            targetPanels.removeLast().orderOut(nil)
        }
    }

    private func makeTargetPanel(
        for target: (frame: NSRect, accessibilityLabel: String?),
    ) -> RailInteractionPanel {
        let targetPanel = RailInteractionPanel(
            frame: target.frame,
            level: visualPanel?.level,
            accessibilityLabel: target.accessibilityLabel,
        ) { [weak self] event in
            self?.handle(event)
        } onAccessibilityPress: { [weak self] location in
            self?.handleAccessibilityPress(at: location)
        }
        targetPanel.orderFrontRegardless()
        return targetPanel
    }

    private func removeTargetPanels() {
        targetPanels.forEach { $0.orderOut(nil) }
        targetPanels.removeAll(keepingCapacity: true)
    }

    private func handleAccessibilityPress(at location: NSPoint) {
        perform(
            engine.handle(
                .primaryClick(region: pointerRegion(at: location)),
                at: ProcessInfo.processInfo.systemUptime,
            ),
        )
    }
}

private extension RailActivationModifier {
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift:
            .shift
        case .option:
            .option
        case .control:
            .control
        case .command:
            .command
        }
    }
}

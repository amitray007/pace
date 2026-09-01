import AppKit
import PaceCore

@MainActor
final class RailInteractionController {
    private let model: PacePresentationModel
    private weak var visualPanel: NSPanel?
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
                Task { @MainActor in
                    self?.handle(event)
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
        )
        perform(engine.handle(.pointerMoved(sample), at: time))
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
                let providerIDs = Array(model.visibleProviderIDs.prefix(3))
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
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimerTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

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
        targetPanels.forEach { $0.orderOut(nil) }
        targetPanels.removeAll(keepingCapacity: true)
        guard model.isRailVisible, !isScreenExcluded else {
            return
        }
        let targets = interactionTargets
        for target in targets where !target.frame.isEmpty {
            let targetPanel = RailInteractionPanel(
                frame: target.frame,
                level: visualPanel?.level,
                accessibilityLabel: target.accessibilityLabel,
            ) { [weak self] event in
                self?.handle(event)
            } onAccessibilityPress: { [weak self] in
                self?.handleAccessibilityPress(at: target.frame.center)
            }
            targetPanel.orderFrontRegardless()
            targetPanels.append(targetPanel)
        }
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

private extension RailInteractionController {
    private var interactionTargets: [(frame: NSRect, accessibilityLabel: String?)] {
        if model.railPreviewState == .mini {
            return model.preferences.activationMode == .clickHandle
                ? [(hotspotFrame, "Open Pace rail")]
                : []
        }
        return [(railFrame, nil), (settingsFrame, nil)] +
            (detailFrame.map { [($0, nil)] } ?? [])
    }

    private func pointerRegion(at location: NSPoint) -> RailPointerRegion {
        if model.railPreviewState == .mini {
            return hotspotFrame.contains(location) ? .hotspot : .outside
        }
        if settingsFrame.contains(location) {
            return .settings
        }
        for (index, frame) in providerFrames.enumerated() where frame.contains(location) {
            return .rail(providerIndex: index)
        }
        if railFrame.contains(location) {
            return .rail(providerIndex: nil)
        }
        if detailFrame?.contains(location) == true {
            return .detail
        }
        if travelCorridorFrame?.contains(location) == true {
            return .travelCorridor
        }
        return .outside
    }

    private var hotspotFrame: NSRect {
        guard let visualPanel else {
            return .zero
        }
        let originX = model.preferences.railEdge == .right
            ? visualPanel.frame.maxX - 18
            : visualPanel.frame.minX
        return scaledInteractionFrame(NSRect(
            x: originX,
            y: visualPanel.frame.minY + 173,
            width: 18,
            height: 70,
        ))
    }

    private var railFrame: NSRect {
        guard let visualPanel else {
            return .zero
        }
        let originX = model.preferences.railEdge == .right
            ? visualPanel.frame.minX + EdgeRailGeometry.railOriginX
            : visualPanel.frame.minX
        return scaledInteractionFrame(NSRect(
            x: originX,
            y: visualPanel.frame.minY + 62,
            width: EdgeRailGeometry.railWidth,
            height: 324,
        ))
    }

    private var providerFrames: [NSRect] {
        guard let visualPanel else {
            return []
        }
        let originX = model.preferences.railEdge == .right
            ? visualPanel.frame.minX + EdgeRailGeometry.railOriginX
            : visualPanel.frame.minX
        return EdgeRailGeometry.providerTopY.map { topPosition in
            scaledInteractionFrame(NSRect(
                x: originX,
                y: visualPanel.frame.minY + EdgeRailGeometry.canvasSize.height - topPosition - 64,
                width: EdgeRailGeometry.railWidth,
                height: 64,
            ))
        }
    }

    private var settingsFrame: NSRect {
        guard let visualPanel else {
            return .zero
        }
        let localOriginX: CGFloat = model.preferences.railEdge == .right ? 266 : 12
        return scaledInteractionFrame(NSRect(
            x: visualPanel.frame.minX + localOriginX,
            y: visualPanel.frame.minY,
            width: 46,
            height: 46,
        ))
    }

    private var detailFrame: NSRect? {
        guard let visualPanel, let detailCenterY else {
            return nil
        }
        let panelTop = min(max(detailCenterY - 69.5, 0), 205)
        let originX = model.preferences.railEdge == .right
            ? visualPanel.frame.minX
            : visualPanel.frame.maxX - EdgeRailGeometry.detailWidth
        return scaledInteractionFrame(NSRect(
            x: originX,
            y: visualPanel.frame.minY + EdgeRailGeometry.canvasSize.height - panelTop - 139,
            width: EdgeRailGeometry.detailWidth,
            height: 139,
        ))
    }

    private var travelCorridorFrame: NSRect? {
        guard let detailFrame, let detailCenterY,
              let providerIndex = EdgeRailGeometry.providerCentersY.firstIndex(of: detailCenterY),
              providerFrames.indices.contains(providerIndex)
        else {
            return nil
        }
        let centerY = providerFrames[providerIndex].midY
        let minimumX = model.preferences.railEdge == .right ? detailFrame.maxX : railFrame.maxX
        let maximumX = model.preferences.railEdge == .right ? railFrame.minX : detailFrame.minX
        return NSRect(
            x: minimumX,
            y: centerY - 24,
            width: max(maximumX - minimumX, 0),
            height: 48,
        )
    }

    private func scaledInteractionFrame(_ frame: NSRect) -> NSRect {
        guard let visualPanel else {
            return .zero
        }
        let scale = EdgeRailGeometry.displayScale
        let anchorX = model.preferences.railEdge == .right
            ? visualPanel.frame.maxX
            : visualPanel.frame.minX
        let anchorY = visualPanel.frame.midY
        return NSRect(
            x: anchorX + (frame.minX - anchorX) * scale,
            y: anchorY + (frame.minY - anchorY) * scale,
            width: frame.width * scale,
            height: frame.height * scale,
        )
    }

    private var detailCenterY: CGFloat? {
        guard let providerID = model.railPreviewState.detailProviderID,
              let index = Array(model.visibleProviderIDs.prefix(3)).firstIndex(of: providerID),
              EdgeRailGeometry.providerCentersY.indices.contains(index)
        else {
            return nil
        }
        return EdgeRailGeometry.providerCentersY[index]
    }

    private static func configuration(for preferences: PacePreferences)
    -> RailActivationConfiguration {
        RailActivationConfiguration(
            mode: preferences.activationMode,
            dwellDelay: preferences.dwellDelay,
            dismissalDelay: preferences.dismissalDelay,
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

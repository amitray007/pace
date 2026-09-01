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
            edgeDistance: edgeDistance(to: location),
        )
        perform(engine.handle(.pointerMoved(sample), at: time))
    }

    /// How far the pointer is from the edge the rail lives on.
    /// How many provider rows the rail is showing, which the hit regions are
    /// laid out against.
    private var railProviderCount: Int {
        min(model.visibleProviderIDs.count, EdgeRailGeometry.maximumProviderRows)
    }

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
        guard model.isRailVisible, !isScreenExcluded else {
            removeTargetPanels()
            return
        }
        let targets = interactionTargets.filter { !$0.frame.isEmpty }
        // Interaction panels are real windows. Recreating them while nothing
        // moved makes the window server churn on every model refresh and
        // briefly stacks old and new panels, so identical targets keep their
        // panels.
        let isUnchanged = targets.count == targetPanels.count &&
            zip(targets, targetPanels).allSatisfy { target, panel in
                target.frame == panel.frame
            }
        if isUnchanged {
            return
        }
        removeTargetPanels()
        for target in targets {
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
            return collapsedPointerFrame.contains(location) ? .hotspot : .outside
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

    /// Converts a rect authored in the shell's top-down canvas coordinates
    /// into the on-screen rect the pointer actually meets: flipped like the
    /// layer view flips its paths, mirrored for the left edge, and scaled
    /// around the screen edge. Hit regions must take the same trip the drawing
    /// takes; the collapsed handle's hotspot once skipped the flip and sat
    /// 150 pt below the visible handle, which made hovering it feel
    /// impossible.
    private func interactionFrame(authored rect: CGRect) -> NSRect {
        guard let visualPanel else {
            return .zero
        }
        let canvas = EdgeRailGeometry.canvasSize
        let originX = model.preferences.railEdge == .right
            ? rect.minX
            : canvas.width - rect.maxX
        return scaledInteractionFrame(NSRect(
            x: visualPanel.frame.minX + originX,
            y: visualPanel.frame.minY + canvas.height - rect.maxY,
            width: rect.width,
            height: rect.height,
        ))
    }

    /// The collapsed handle's pointer target.
    ///
    /// Derived from the same rect the shell draws the handle from, so shrinking
    /// the handle cannot leave the clickable area somewhere else. The target is
    /// deliberately larger than the visible handle, which stays small.
    private var hotspotFrame: NSRect {
        interactionFrame(authored: RailShellMetrics.handleTargetRect)
    }

    /// The hover modes' pointer target: the edge band the rail opens into.
    ///
    /// Hover activation has no input window, so the larger band cannot block
    /// clicks, scrolling, or drags. Click mode keeps the small handle target,
    /// because that one backs a real input panel.
    private var hoverHotspotFrame: NSRect {
        interactionFrame(authored: RailShellMetrics.hoverTargetRect)
    }

    private var collapsedPointerFrame: NSRect {
        model.preferences.activationMode == .clickHandle ? hotspotFrame : hoverHotspotFrame
    }

    private var railFrame: NSRect {
        interactionFrame(authored: NSRect(
            x: EdgeRailGeometry.railOriginX,
            y: RailShellMetrics.topEdgeY,
            width: EdgeRailGeometry.railWidth,
            height: RailShellMetrics.bottomEdgeY - RailShellMetrics.topEdgeY,
        ))
    }

    private var providerFrames: [NSRect] {
        EdgeRailGeometry.providerTopY(count: railProviderCount).map { topPosition in
            interactionFrame(authored: NSRect(
                x: EdgeRailGeometry.railOriginX,
                y: topPosition,
                width: EdgeRailGeometry.railWidth,
                height: 64,
            ))
        }
    }

    private var settingsFrame: NSRect {
        let center = RailShellMetrics.settingsCircleCenter
        return interactionFrame(authored: NSRect(
            x: center.x - 23,
            y: center.y - 23,
            width: 46,
            height: 46,
        ))
    }

    /// The drawn detail panel's frame, sized the same way EdgeRailView sizes
    /// it so the hit region hugs the drawn panel.
    private var detailFrame: NSRect? {
        guard let detailCenterY else {
            return nil
        }
        let quotaCount = model.railPreviewState.detailProviderID
            .flatMap { providerID in model.selectedAccount(for: providerID) }
            .map { account in model.snapshots(for: account.id).count } ?? 0
        let height = EdgeRailGeometry.detailHeight(quotaCount: quotaCount)
        return interactionFrame(authored: NSRect(
            x: 0,
            y: EdgeRailGeometry.detailPanelY(centerY: detailCenterY, height: height),
            width: EdgeRailGeometry.detailWidth,
            height: height,
        ))
    }

    private var travelCorridorFrame: NSRect? {
        guard let detailFrame, let detailCenterY,
              let providerIndex = EdgeRailGeometry.providerCentersY(count: railProviderCount)
                  .firstIndex(of: detailCenterY),
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
        let scale = EdgeRailGeometry.displayScale(for: model.preferences)
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
              let index = Array(model.visibleProviderIDs
                  .prefix(EdgeRailGeometry.maximumProviderRows)).firstIndex(of: providerID),
              EdgeRailGeometry.providerCentersY(count: railProviderCount).indices.contains(index)
        else {
            return nil
        }
        return EdgeRailGeometry.providerCentersY(count: railProviderCount)[index]
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

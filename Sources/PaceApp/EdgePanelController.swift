import AppKit
import Observation
import SwiftUI

@MainActor
final class EdgePanelController {
    private let model: PacePresentationModel
    private let panel: ClickThroughEdgePanel
    private var interactionController: RailInteractionController?
    private var screenParametersObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cachedFullScreenExclusion: FullScreenExclusion?

    init(
        model: PacePresentationModel,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) {
        self.model = model
        panel = ClickThroughEdgePanel(
            contentRect: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )

        configurePanel()
        let enablesInteraction = environment["PACE_REFERENCE_PREVIEW"] == nil ||
            environment["PACE_REFERENCE_INTERACTION"] == "1"
        if enablesInteraction {
            interactionController = RailInteractionController(model: model, visualPanel: panel)
        }
        observeModel()
        observeScreenParameters()
        observeWorkspace()
        synchronizeVisibility()

        // Writes the rail to a transparent PNG and exits. Capturing the rail
        // off the screen photographs whatever sits behind its transparent
        // canvas, which is everything the rail is drawn around.
        if let path = environment["PACE_CAPTURE_RAIL"] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.captureRail(to: path)
                NSApp.terminate(nil)
            }
        }
    }

    /// Renders the rail to a PNG with its transparency intact.
    private func captureRail(to path: String) {
        guard let view = panel.contentView else {
            return
        }
        let bounds = view.bounds
        guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return
        }
        view.cacheDisplay(in: bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            return
        }
        try? png.write(to: URL(filePath: path))
    }

    isolated deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func configurePanel() {
        panel.backgroundColor = .clear
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: EdgeRailView(model: model))
        positionPanel()
    }

    private func positionPanel() {
        guard let screen = PaceDisplayCatalog.selectedScreen(
            identifier: model.preferences.selectedDisplayID,
        ) else {
            return
        }
        let size = EdgeRailGeometry.canvasSize
        let xPosition = switch model.preferences.railEdge {
        case .left:
            screen.frame.minX
        case .right:
            screen.frame.maxX - size.width
        }
        let availableTravel = max(screen.visibleFrame.height - size.height, 0)
        let positionFraction: CGFloat = switch model.preferences.railVerticalPosition {
        case .top:
            1
        case .center:
            0.5
        case .bottom:
            0
        }
        let origin = NSPoint(
            x: xPosition,
            y: screen.visibleFrame.minY + availableTravel * positionFraction,
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.state
            _ = model.isRailVisible
            _ = model.preferences.railEdge
            _ = model.preferences.selectedDisplayID
            _ = model.preferences.railVerticalPosition
            _ = model.preferences.activationMode
            _ = model.preferences.activationModifier
            _ = model.preferences.dwellDelay
            _ = model.preferences.dismissalDelay
            _ = model.railPreviewState
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.synchronizeVisibility()
                self?.observeModel()
            }
        }
    }

    private func observeScreenParameters() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                self?.synchronizeVisibility(recheckingFullScreen: true)
            }
        }
    }

    private func observeWorkspace() {
        guard interactionController != nil else {
            return
        }
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let notificationNames: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        workspaceObservers = notificationNames.map { notificationName in
            notificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.synchronizeVisibility(recheckingFullScreen: true)
                }
            }
        }
    }

    /// Brings the panel and its interaction state in line with the model.
    ///
    /// The full-screen check asks the window server for every on-screen
    /// window, which takes milliseconds. It only changes when the frontmost
    /// application, Space, or display set changes, so those notifications
    /// recheck it and rail state changes reuse the last answer. Rechecking on
    /// every reveal and provider switch put that call on the same run loop
    /// pass that started the animation.
    private func synchronizeVisibility(recheckingFullScreen: Bool = false) {
        let isFullScreenExcluded = isFullScreenExcluded(recheck: recheckingFullScreen)
        interactionController?.screenAvailabilityChanged(
            isFullScreenExcluded: isFullScreenExcluded,
        )
        if model.isRailVisible, !isFullScreenExcluded {
            positionPanel()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
        interactionController?.synchronize()
    }

    private struct FullScreenExclusion {
        var hidesRailInFullScreen: Bool
        var selectedDisplayID: String?
        var isExcluded: Bool

        func matches(hidesRailInFullScreen: Bool, selectedDisplayID: String?) -> Bool {
            self.hidesRailInFullScreen == hidesRailInFullScreen &&
                self.selectedDisplayID == selectedDisplayID
        }
    }

    private func isFullScreenExcluded(recheck: Bool) -> Bool {
        let hidesRailInFullScreen = model.preferences.hideRailInFullScreen
        let selectedDisplayID = model.preferences.selectedDisplayID
        let cached = cachedFullScreenExclusion
        let cacheHolds = cached?.matches(
            hidesRailInFullScreen: hidesRailInFullScreen,
            selectedDisplayID: selectedDisplayID,
        ) ?? false
        if !recheck, cacheHolds, let cached {
            return cached.isExcluded
        }
        let isExcluded = computeFullScreenExclusion(
            hidesRailInFullScreen: hidesRailInFullScreen,
            selectedDisplayID: selectedDisplayID,
        )
        cachedFullScreenExclusion = FullScreenExclusion(
            hidesRailInFullScreen: hidesRailInFullScreen,
            selectedDisplayID: selectedDisplayID,
            isExcluded: isExcluded,
        )
        return isExcluded
    }

    private func computeFullScreenExclusion(
        hidesRailInFullScreen: Bool,
        selectedDisplayID: String?,
    ) -> Bool {
        guard interactionController != nil,
              hidesRailInFullScreen,
              let screen = PaceDisplayCatalog.selectedScreen(identifier: selectedDisplayID)
        else {
            return false
        }
        return PaceFullScreenDetector.frontmostApplicationCovers(screen)
    }
}

private final class ClickThroughEdgePanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

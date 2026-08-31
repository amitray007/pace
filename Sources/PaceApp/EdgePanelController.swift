import AppKit
import Observation
import SwiftUI

@MainActor
final class EdgePanelController {
    private let model: PacePresentationModel
    private let panel: ClickThroughEdgePanel
    private var screenParametersObserver: NSObjectProtocol?

    init(model: PacePresentationModel) {
        self.model = model
        panel = ClickThroughEdgePanel(
            contentRect: NSRect(origin: .zero, size: EdgeRailGeometry.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )

        configurePanel()
        observeModel()
        observeScreenParameters()
        synchronizeVisibility()
    }

    isolated deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
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
            _ = model.isRailVisible
            _ = model.preferences.railEdge
            _ = model.preferences.selectedDisplayID
            _ = model.preferences.railVerticalPosition
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
                self?.synchronizeVisibility()
            }
        }
    }

    private func synchronizeVisibility() {
        if model.isRailVisible {
            positionPanel()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
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

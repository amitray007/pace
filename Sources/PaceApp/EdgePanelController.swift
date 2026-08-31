import AppKit
import Observation
import SwiftUI

@MainActor
final class EdgePanelController {
    private let model: PacePresentationModel
    private let panel: ClickThroughEdgePanel

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
        synchronizeVisibility()
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
        guard let screen = NSScreen.main else {
            return
        }
        let size = EdgeRailGeometry.canvasSize
        let origin = NSPoint(
            x: screen.frame.maxX - size.width,
            y: screen.visibleFrame.midY - size.height / 2,
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.isRailVisible
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.synchronizeVisibility()
                self?.observeModel()
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

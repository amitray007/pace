import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(
        model: PacePresentationModel,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) {
        super.init()

        let hostingController = NSHostingController(rootView: MenuPanelView(model: model))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.behavior = .semitransient
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.67percent",
                accessibilityDescription: "Pace",
            )
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Pace usage limits"
            button.setAccessibilityLabel("Pace usage limits")
        }

        if environment["PACE_REFERENCE_MENU"] == "1" {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.showPopover()
            }
        }
    }

    @objc
    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

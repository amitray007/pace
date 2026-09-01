import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let model: PacePresentationModel
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var keyMonitor: Any?

    init(
        model: PacePresentationModel,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) {
        self.model = model
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

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event) ?? event
        }
    }

    isolated deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
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
        let popoverWindow = popover.contentViewController?.view.window
        popoverWindow?.makeKey()
        popoverWindow?.makeFirstResponder(nil)
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown else {
            return event
        }
        if event.keyCode == 53 {
            popover.performClose(nil)
            return nil
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.option),
              !modifiers.contains(.command),
              !modifiers.contains(.control)
        else {
            return event
        }
        let offset: Int? = switch event.keyCode {
        case 123:
            -1
        case 124:
            1
        default:
            nil
        }
        guard let offset else {
            return event
        }
        Task {
            await model.selectAdjacentAccount(offset: offset)
        }
        return nil
    }
}

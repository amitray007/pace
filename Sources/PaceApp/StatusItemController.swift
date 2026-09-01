import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let model: PacePresentationModel
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var keyMonitor: Any?
    private var activationObserver: (any NSObjectProtocol)?

    init(
        model: PacePresentationModel,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) {
        self.model = model
        super.init()

        let hostingController = NSHostingController(rootView: MenuPanelView(model: model))
        hostingController.sizingOptions = [.preferredContentSize]
        // Transient, so clicking anywhere outside the panel closes it. The
        // semitransient behaviour only dismissed on interaction inside Pace, so
        // clicking another application left the panel open behind it.
        popover.behavior = .transient
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

        // A transient popover closes on an outside click, but switching
        // applications by other means, such as the keyboard or Mission Control,
        // is not a click. Closing on deactivation covers those too, so the
        // panel never stays open over an application the user has moved on to.
        // Reference capture holds the panel open deliberately without Pace
        // being frontmost, so it opts out of closing on deactivation.
        if environment["PACE_REFERENCE_MENU"] != "1" {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.popover.performClose(nil)
                }
            }
        }
    }

    isolated deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
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

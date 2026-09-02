import AppKit

final class RailInteractionPanel: NSPanel {
    /// The label this panel was created with. Panels are reused across
    /// geometry changes, so the controller checks this before deciding
    /// whether an existing panel can simply be moved.
    let targetAccessibilityLabel: String?

    init(
        frame: NSRect,
        level: NSWindow.Level?,
        accessibilityLabel: String?,
        onEvent: @escaping (NSEvent) -> Void,
        onAccessibilityPress: @escaping (NSPoint) -> Void,
    ) {
        targetAccessibilityLabel = accessibilityLabel
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isMovable = false
        isOpaque = false
        self.level = NSWindow
            .Level(rawValue: (level?.rawValue ?? NSWindow.Level.floating.rawValue) + 1)
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        contentView = RailInteractionView(
            frame: NSRect(origin: .zero, size: frame.size),
            accessibilityLabel: accessibilityLabel,
            onEvent: onEvent,
            onAccessibilityPress: onAccessibilityPress,
        )
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class RailInteractionView: NSView {
    private let onEvent: (NSEvent) -> Void
    private let onAccessibilityPress: (NSPoint) -> Void

    init(
        frame: NSRect,
        accessibilityLabel: String?,
        onEvent: @escaping (NSEvent) -> Void,
        onAccessibilityPress: @escaping (NSPoint) -> Void,
    ) {
        self.onEvent = onEvent
        self.onAccessibilityPress = onAccessibilityPress
        super.init(frame: frame)
        setAccessibilityElement(accessibilityLabel != nil)
        if let accessibilityLabel {
            setAccessibilityRole(.button)
            setAccessibilityLabel(accessibilityLabel)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        onEvent(event)
    }

    override func mouseDown(with event: NSEvent) {
        onEvent(event)
    }

    override func mouseUp(with event: NSEvent) {
        onEvent(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onEvent(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onEvent(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        onEvent(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        onEvent(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onEvent(event)
    }

    override func otherMouseUp(with event: NSEvent) {
        onEvent(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        onEvent(event)
    }

    override func scrollWheel(with event: NSEvent) {
        onEvent(event)
    }

    override func accessibilityPerformPress() -> Bool {
        // Read the frame at press time. The panel may have been moved since
        // it was created, so a captured centre would point at the old spot.
        guard let window else {
            return false
        }
        onAccessibilityPress(window.frame.center)
        return true
    }
}

extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}

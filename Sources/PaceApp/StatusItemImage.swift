import AppKit
import PaceCore

/// Draws the status-item content: a provider mark followed by its usage.
///
/// Rendered as one image rather than composed from a title and an image,
/// because `NSStatusItem` gives a single image and title and this needs several
/// of each. Drawing it also keeps the mark and the digits on a shared baseline,
/// which alternating image and text positions could not guarantee.
enum StatusItemImage {
    /// Menu-bar items are laid out in a 22pt bar; this leaves the standard
    /// padding above and below.
    private static let height: CGFloat = 18
    private static let markSize: CGFloat = 14
    private static let markToNumberGap: CGFloat = 3
    private static let slotGap: CGFloat = 7
    private static let fontSize: CGFloat = 12

    private static var font: NSFont {
        .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
    }

    /// The fallback when no slot is configured.
    static func placeholder() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
            accessibilityDescription: "Pace usage limits",
        )
        image?.isTemplate = true
        return image
    }

    static func image(
        for readings: [MenuBarReading],
        showsPercentSign: Bool,
        tint: MenuBarTint = .monochrome,
    ) -> NSImage? {
        guard !readings.isEmpty else {
            return placeholder()
        }

        let segments = readings.map { reading in
            (reading: reading, text: text(for: reading, showsPercentSign: showsPercentSign))
        }
        let width = segments.reduce(CGFloat.zero) { total, segment in
            total + markSize + markToNumberGap + textWidth(segment.text) + slotGap
        } - slotGap

        let image = NSImage(size: NSSize(width: max(width, markSize), height: height))
        image.lockFocus()

        var originX: CGFloat = 0
        for segment in segments {
            draw(mark: segment.reading.providerID, at: originX, tint: tint)
            originX += markSize + markToNumberGap
            draw(
                text: segment.text,
                at: originX,
                isAvailable: segment.reading.isAvailable,
                tint: tint,
            )
            originX += textWidth(segment.text) + slotGap
        }
        image.unlockFocus()

        // A template image is what the system's own items use: macOS tints it
        // to suit the menu bar, so it is correct in a light and a dark bar
        // without the app resolving colours itself. Baking in a resolved colour
        // could only ever match one of the two.
        //
        // Brand tinting has to opt out of that, because template rendering
        // flattens every hue to one tone.
        image.isTemplate = tint == .monochrome
        return image
    }

    private static func text(for reading: MenuBarReading, showsPercentSign: Bool) -> String {
        guard let usedFraction = reading.usedFraction else {
            // The provider stopped reporting this quota. A dash says so; "0%"
            // would claim an untouched limit.
            return "--"
        }
        let percentage = Int((min(max(usedFraction, 0), 1) * 100).rounded())
        return showsPercentSign ? "\(percentage)%" : "\(percentage)"
    }

    private static func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func draw(mark providerID: ProviderID, at originX: CGFloat, tint: MenuBarTint) {
        let rect = NSRect(
            x: originX,
            y: (height - markSize) / 2,
            width: markSize,
            height: markSize,
        )
        guard let mark = ProviderMarkResources.image(for: providerID) else {
            return
        }
        let color = tint == .brand
            ? ProviderStyle.resolve(providerID).accentColor
            : NSColor.black
        let tinted = NSImage(size: rect.size, flipped: false) { bounds in
            color.set()
            bounds.fill(using: .sourceOver)
            mark.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        tinted.draw(in: rect)
    }

    private static func draw(
        text: String,
        at originX: CGFloat,
        isAvailable: Bool,
        tint: MenuBarTint,
    ) {
        // Opaque black in a template image; macOS replaces it with the tone the
        // menu bar needs. An unavailable reading is drawn faded, which template
        // rendering preserves as reduced opacity.
        let base: NSColor = tint == .brand ? .labelColor : .black
        let color = isAvailable ? base : base.withAlphaComponent(0.45)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: originX, y: (height - size.height) / 2),
            withAttributes: attributes,
        )
    }
}

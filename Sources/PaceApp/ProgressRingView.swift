import AppKit
import SwiftUI

struct ProgressRingLayerRepresentable: NSViewRepresentable {
    let fraction: Double
    let color: NSColor
    let increasedContrast: Bool

    func makeNSView(context _: Context) -> ProgressRingLayerView {
        ProgressRingLayerView()
    }

    func updateNSView(_ view: ProgressRingLayerView, context _: Context) {
        view.update(
            fraction: fraction,
            color: color,
            increasedContrast: increasedContrast,
        )
    }
}

final class ProgressRingLayerView: NSView {
    private let progressLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for item in [trackLayer, progressLayer] {
            item.fillColor = nil
            item.lineCap = .round
            item.actions = ["strokeEnd": NSNull(), "path": NSNull(), "lineWidth": NSNull()]
            layer?.addSublayer(item)
        }
        // The reference draws the arc directly on top of a track of the same
        // weight, so the unused remainder stays visible as a grey annulus.
        trackLayer.lineCap = .butt
        trackLayer.strokeColor = UsageLevelPalette.track.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        // Reference ring: 85 px outer diameter with a 10 px stroke, so the
        // stroke is 0.118 of the diameter and the path radius is inset by half
        // the stroke.
        let strokeWidth = max(bounds.width * Self.strokeRatio, 1)
        trackLayer.lineWidth = strokeWidth
        progressLayer.lineWidth = strokeWidth
        let inset = strokeWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = CGPath(ellipseIn: rect, transform: nil)
        trackLayer.frame = bounds
        trackLayer.path = path
        progressLayer.frame = bounds
        progressLayer.path = path
        progressLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
    }

    func update(fraction: Double, color: NSColor, increasedContrast: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.strokeColor = UsageLevelPalette
            .trackColor(increasedContrast: increasedContrast).cgColor
        progressLayer.strokeColor = color.cgColor
        progressLayer.strokeEnd = min(max(fraction, 0), 1)
        CATransaction.commit()
    }

    /// Reference stroke weight relative to the ring's outer diameter.
    private static let strokeRatio: CGFloat = 10.0 / 85.0
}

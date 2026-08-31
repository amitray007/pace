import AppKit
import SwiftUI

struct ProgressRingLayerRepresentable: NSViewRepresentable {
    let fraction: Double
    let color: NSColor

    func makeNSView(context _: Context) -> ProgressRingLayerView {
        ProgressRingLayerView()
    }

    func updateNSView(_ view: ProgressRingLayerView, context _: Context) {
        view.update(fraction: fraction, color: color)
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
            item.lineWidth = 5
            item.actions = ["strokeEnd": NSNull(), "path": NSNull()]
            layer?.addSublayer(item)
        }
        trackLayer.strokeColor = NSColor(white: 0.17, alpha: 1).cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: 3, dy: 3)
        let path = CGPath(ellipseIn: rect, transform: nil)
        trackLayer.frame = bounds
        trackLayer.path = path
        progressLayer.frame = bounds
        progressLayer.path = path
        progressLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
    }

    func update(fraction: Double, color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeColor = color.cgColor
        progressLayer.strokeEnd = min(max(fraction, 0), 1)
        CATransaction.commit()
    }
}

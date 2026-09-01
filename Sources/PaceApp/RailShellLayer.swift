import AppKit
import PaceCore
import SwiftUI

struct RailShellLayerRepresentable: NSViewRepresentable {
    let previewState: RailPreviewState
    let edge: RailEdge
    let detailCenterY: CGFloat?
    let reducesMotion: Bool

    func makeNSView(context _: Context) -> RailShellLayerView {
        RailShellLayerView()
    }

    func updateNSView(_ view: RailShellLayerView, context _: Context) {
        view.update(
            previewState: previewState,
            edge: edge,
            detailCenterY: detailCenterY,
            reducesMotion: reducesMotion,
        )
    }
}

final class RailShellLayerView: NSView {
    private let detailLayer = CAShapeLayer()
    private let railLayer = CAShapeLayer()
    private let settingsLayer = CAShapeLayer()
    private var previewState: RailPreviewState = .rail
    private var edge: RailEdge = .right
    private var detailCenterY: CGFloat?
    private var lastDetailCenterY: CGFloat = 92
    private var hasReceivedState = false
    private var reducesMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(detailLayer)
        layer?.addSublayer(railLayer)
        layer?.addSublayer(settingsLayer)
        for item in [detailLayer, railLayer, settingsLayer] {
            item.fillColor = NSColor.black.cgColor
            item.actions = ["path": NSNull(), "opacity": NSNull()]
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        updatePaths(animated: false, duration: RailMotion.detailDuration)
    }

    func update(
        previewState: RailPreviewState,
        edge: RailEdge,
        detailCenterY: CGFloat?,
        reducesMotion: Bool,
    ) {
        let previousPreviewState = self.previewState
        let changed = self.previewState != previewState || self.edge != edge ||
            self.detailCenterY != detailCenterY
        let shouldAnimate = hasReceivedState && changed && !bounds.isEmpty
        self.previewState = previewState
        self.edge = edge
        self.detailCenterY = detailCenterY
        if let detailCenterY {
            lastDetailCenterY = detailCenterY
        }
        self.reducesMotion = reducesMotion
        hasReceivedState = true
        if changed {
            let duration = transitionDuration(
                from: previousPreviewState,
                to: previewState,
            )
            updatePaths(animated: shouldAnimate, duration: duration)
        }
    }

    private func updatePaths(animated: Bool, duration: CFTimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        railLayer.frame = bounds
        settingsLayer.frame = bounds
        detailLayer.frame = bounds

        if previewState == .mini {
            set(
                railLayer,
                path: transformed(RailShellPaths.mini()),
                opacity: 1,
                animated: animated,
                duration: duration,
            )
            set(
                settingsLayer,
                path: transformed(RailShellPaths.settings()),
                opacity: 0,
                animated: animated,
                duration: duration,
            )
            set(
                detailLayer,
                path: transformed(RailShellPaths.collapsedDetail(centerY: lastDetailCenterY)),
                opacity: 1,
                animated: animated,
                duration: duration,
            )
        } else {
            set(
                railLayer,
                path: transformed(RailShellPaths.rail()),
                opacity: 1,
                animated: animated,
                duration: duration,
            )
            set(
                settingsLayer,
                path: transformed(RailShellPaths.settings()),
                opacity: 1,
                animated: animated,
                duration: duration,
            )
            updateDetailPath(animated: animated, duration: duration)
        }
        CATransaction.commit()
    }

    private func updateDetailPath(animated: Bool, duration: CFTimeInterval) {
        guard previewState.detailProviderID != nil else {
            set(
                detailLayer,
                path: transformed(RailShellPaths.collapsedDetail(centerY: lastDetailCenterY)),
                opacity: 1,
                animated: animated,
                duration: duration,
            )
            return
        }
        let centerY = detailCenterY ?? 92
        set(
            detailLayer,
            path: transformed(RailShellPaths.detail(centerY: centerY)),
            opacity: 1,
            animated: animated,
            duration: duration,
        )
    }

    private func transitionDuration(
        from previousState: RailPreviewState,
        to nextState: RailPreviewState,
    ) -> CFTimeInterval {
        if reducesMotion {
            return RailMotion.reducedMotionFadeDuration
        }
        return previousState == .mini || nextState == .mini
            ? RailMotion.revealDuration
            : RailMotion.detailDuration
    }

    private func set(
        _ shapeLayer: CAShapeLayer,
        path: CGPath?,
        opacity: Float,
        animated: Bool,
        duration: CFTimeInterval,
    ) {
        let presentationLayer = shapeLayer.presentation()
        let currentPath = presentationLayer?.path ?? shapeLayer.path
        let currentOpacity = presentationLayer?.opacity ?? shapeLayer.opacity

        shapeLayer.path = path
        shapeLayer.opacity = opacity
        guard animated else {
            shapeLayer.removeAnimation(forKey: "pace.path")
            shapeLayer.removeAnimation(forKey: "pace.opacity")
            return
        }

        if !reducesMotion, let currentPath, let path, !CFEqual(currentPath, path) {
            let pathAnimation = CABasicAnimation(keyPath: "path")
            pathAnimation.fromValue = currentPath
            pathAnimation.toValue = path
            pathAnimation.duration = duration
            pathAnimation.timingFunction = RailMotion.timingFunction
            shapeLayer.add(pathAnimation, forKey: "pace.path")
        }

        if currentOpacity != opacity {
            let opacityAnimation = CABasicAnimation(keyPath: "opacity")
            opacityAnimation.fromValue = currentOpacity
            opacityAnimation.toValue = opacity
            opacityAnimation.duration = reducesMotion
                ? RailMotion.reducedMotionFadeDuration
                : min(duration, RailMotion.contentFadeDuration)
            opacityAnimation.timingFunction = RailMotion.timingFunction
            shapeLayer.add(opacityAnimation, forKey: "pace.opacity")
        }
    }

    private func transformed(_ path: CGPath) -> CGPath {
        var verticalFlip = CGAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: -1,
            tx: 0,
            ty: bounds.height,
        )
        let verticallyFlippedPath = path.copy(using: &verticalFlip) ?? path
        guard edge == .left else {
            return verticallyFlippedPath
        }
        var horizontalFlip = CGAffineTransform(
            a: -1,
            b: 0,
            c: 0,
            d: 1,
            tx: bounds.width,
            ty: 0,
        )
        return verticallyFlippedPath.copy(using: &horizontalFlip) ?? verticallyFlippedPath
    }
}

private enum RailShellPaths {
    static func mini() -> CGPath {
        let path = CGMutablePath()
        let rightX = EdgeRailGeometry.canvasSize.width
        let leftX = rightX - 18
        let topY: CGFloat = 173
        let bottomY: CGFloat = 243
        let radius: CGFloat = 9
        path.move(to: CGPoint(x: rightX, y: topY))
        path.addCompatibleLine(to: CGPoint(x: leftX + radius, y: topY))
        path.addCurve(
            to: CGPoint(x: leftX, y: topY + radius),
            control1: CGPoint(x: leftX + radius * 0.45, y: topY),
            control2: CGPoint(x: leftX, y: topY + radius * 0.45),
        )
        path.addCompatibleLine(to: CGPoint(x: leftX, y: bottomY - radius))
        path.addCurve(
            to: CGPoint(x: leftX + radius, y: bottomY),
            control1: CGPoint(x: leftX, y: bottomY - radius * 0.45),
            control2: CGPoint(x: leftX + radius * 0.45, y: bottomY),
        )
        path.addCompatibleLine(to: CGPoint(x: rightX, y: bottomY))
        path.addCompatibleLine(to: CGPoint(x: rightX, y: topY))
        path.closeSubpath()
        return path
    }

    static func rail() -> CGPath {
        let path = CGMutablePath()
        let leftX = EdgeRailGeometry.railOriginX
        let rightX = EdgeRailGeometry.canvasSize.width
        let topY = EdgeRailGeometry.railTopY
        path.move(to: CGPoint(x: rightX, y: topY))
        path.addCompatibleLine(to: CGPoint(x: leftX + 38, y: topY))
        path.addCurve(
            to: CGPoint(x: leftX, y: topY + 48),
            control1: CGPoint(x: leftX + 38, y: topY + 20),
            control2: CGPoint(x: leftX, y: topY + 20),
        )
        path.addCompatibleLine(to: CGPoint(x: leftX, y: 322))
        path.addCurve(
            to: CGPoint(x: leftX + 36, y: 350),
            control1: CGPoint(x: leftX, y: 338),
            control2: CGPoint(x: leftX + 20, y: 348),
        )
        path.addCurve(
            to: CGPoint(x: rightX, y: 354),
            control1: CGPoint(x: leftX + 58, y: 350),
            control2: CGPoint(x: rightX - 7, y: 354),
        )
        path.addCompatibleLine(to: CGPoint(x: rightX, y: topY))
        path.closeSubpath()
        return path
    }

    static func settings() -> CGPath {
        let path = CGMutablePath()
        let rightX = EdgeRailGeometry.canvasSize.width
        path.addRoundedRect(
            in: CGRect(x: rightX - 20, y: 384, width: 20, height: 18),
            cornerWidth: 9,
            cornerHeight: 9,
        )
        path.addEllipse(
            in: CGRect(x: EdgeRailGeometry.railOriginX + 12, y: 370, width: 46, height: 46),
        )
        return path
    }

    static func detail(centerY: CGFloat) -> CGPath {
        let panelY = min(max(centerY - 69.5, 0), 205)
        let rect = CGRect(x: 0, y: panelY, width: EdgeRailGeometry.detailWidth, height: 139)
        let radius: CGFloat = 16
        let controlDistance = radius * 0.552_284_75
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addCompatibleLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control1: CGPoint(x: rect.maxX - radius + controlDistance, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + radius - controlDistance),
        )
        path.addCompatibleLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - radius + controlDistance),
            control2: CGPoint(x: rect.maxX - radius + controlDistance, y: rect.maxY),
        )
        path.addCompatibleLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control1: CGPoint(x: rect.minX + radius - controlDistance, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - radius + controlDistance),
        )
        path.addCompatibleLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + radius - controlDistance),
            control2: CGPoint(x: rect.minX + radius - controlDistance, y: rect.minY),
        )
        path.closeSubpath()

        let connectorStart = CGPoint(x: rect.maxX - 1, y: centerY - 17)
        path.move(to: connectorStart)
        path.addCompatibleLine(
            to: CGPoint(x: EdgeRailGeometry.railOriginX + 2, y: centerY),
        )
        path.addCompatibleLine(to: CGPoint(x: rect.maxX - 1, y: centerY + 17))
        path.addCompatibleLine(to: connectorStart)
        path.closeSubpath()
        return path
    }

    static func collapsedDetail(centerY: CGFloat) -> CGPath {
        let point = CGPoint(x: EdgeRailGeometry.railOriginX + 2, y: centerY)
        let path = CGMutablePath()
        path.move(to: point)
        for _ in 0 ..< 8 {
            path.addCompatibleLine(to: point)
        }
        path.closeSubpath()
        path.move(to: point)
        for _ in 0 ..< 3 {
            path.addCompatibleLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private extension CGMutablePath {
    func addCompatibleLine(to point: CGPoint) {
        let start = currentPoint
        addCurve(
            to: point,
            control1: CGPoint(
                x: start.x + (point.x - start.x) / 3,
                y: start.y + (point.y - start.y) / 3,
            ),
            control2: CGPoint(
                x: start.x + (point.x - start.x) * 2 / 3,
                y: start.y + (point.y - start.y) * 2 / 3,
            ),
        )
    }
}

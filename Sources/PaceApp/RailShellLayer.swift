import AppKit
import PaceCore
import SwiftUI

/// Everything the rail shell draws from. Grouping it gives one comparison for
/// "did anything change" instead of a growing list of stored properties.
struct RailShellState: Equatable {
    var previewState: RailPreviewState
    var edge: RailEdge
    var detailCenterY: CGFloat?
    var detailHeight: CGFloat
    var showsSettingsCircle: Bool
    var reducesMotion: Bool
}

struct RailShellLayerRepresentable: NSViewRepresentable {
    let state: RailShellState

    func makeNSView(context _: Context) -> RailShellLayerView {
        RailShellLayerView()
    }

    func updateNSView(_ view: RailShellLayerView, context _: Context) {
        view.update(state)
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
    private var detailHeight = EdgeRailGeometry.detailHeight(quotaCount: 2)
    private var showsSettingsCircle = false
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

    func update(_ state: RailShellState) {
        let previousPreviewState = previewState
        let changed = state != currentState
        let shouldAnimate = hasReceivedState && changed && !bounds.isEmpty
        previewState = state.previewState
        edge = state.edge
        detailCenterY = state.detailCenterY
        detailHeight = state.detailHeight
        showsSettingsCircle = state.showsSettingsCircle
        if let centerY = state.detailCenterY {
            lastDetailCenterY = centerY
        }
        reducesMotion = state.reducesMotion
        hasReceivedState = true
        guard changed else {
            return
        }
        updatePaths(
            animated: shouldAnimate,
            duration: transitionDuration(
                from: previousPreviewState,
                to: state.previewState,
            ),
        )
    }

    private var currentState: RailShellState {
        RailShellState(
            previewState: previewState,
            edge: edge,
            detailCenterY: detailCenterY,
            detailHeight: detailHeight,
            showsSettingsCircle: showsSettingsCircle,
            reducesMotion: reducesMotion,
        )
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
                path: transformed(
                    RailShellPaths.settings(showsCircle: showsSettingsCircle),
                ),
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
                path: transformed(
                    RailShellPaths.settings(showsCircle: showsSettingsCircle),
                ),
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
            path: transformed(
                RailShellPaths.detail(centerY: centerY, panelHeight: detailHeight),
            ),
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

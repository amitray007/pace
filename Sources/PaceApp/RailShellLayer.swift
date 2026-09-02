import AppKit
import PaceCore
import SwiftUI

/// Everything the rail shell draws from. Grouping it gives one comparison for
/// "did anything change" instead of a growing list of stored properties.
struct RailShellState: Equatable {
    /// How many provider rows the rail is drawing. The shell's paths are built
    /// from static geometry, so this is applied to RailShellMetrics before they
    /// are evaluated.
    var providerRowCount: Int
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
    private let handleHighlightLayer = CAShapeLayer()
    private var previewState: RailPreviewState = .rail
    private var edge: RailEdge = .right
    private var detailCenterY: CGFloat?
    private var lastDetailCenterY: CGFloat = 92
    private var detailHeight = EdgeRailGeometry.detailHeight(quotaCount: 2)
    private var showsSettingsCircle = false
    private var hasShownDetail = false
    private var hasReceivedState = false
    private var reducesMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(detailLayer)
        layer?.addSublayer(railLayer)
        layer?.addSublayer(settingsLayer)
        layer?.addSublayer(handleHighlightLayer)
        for item in [detailLayer, railLayer, settingsLayer] {
            item.fillColor = NSColor.black.cgColor
            item.actions = ["path": NSNull(), "opacity": NSNull()]
        }
        configureHandleHighlight()
    }

    /// A hairline along the collapsed handle's inner edge.
    ///
    /// The handle is pure black, so on a dark desktop it has nothing to
    /// contrast against and effectively disappears. A light stroke does not
    /// depend on the wallpaper behind it, which makes the handle findable
    /// without making it larger or lighter overall.
    private func configureHandleHighlight() {
        handleHighlightLayer.fillColor = nil
        handleHighlightLayer.strokeColor = RailShellMetrics.handleHighlightColor.cgColor
        handleHighlightLayer.lineWidth = RailShellMetrics.handleHighlightWidth
        handleHighlightLayer.lineCap = .round
        handleHighlightLayer.actions = ["path": NSNull(), "opacity": NSNull()]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        updatePaths(animated: false, transition: .detail)
    }

    func update(_ state: RailShellState) {
        RailShellMetrics.providerRowCount = state.providerRowCount
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
            transition: transition(
                from: previousPreviewState,
                to: state.previewState,
            ),
        )
    }

    private var currentState: RailShellState {
        RailShellState(
            providerRowCount: RailShellMetrics.providerRowCount,
            previewState: previewState,
            edge: edge,
            detailCenterY: detailCenterY,
            detailHeight: detailHeight,
            showsSettingsCircle: showsSettingsCircle,
            reducesMotion: reducesMotion,
        )
    }

    private func updatePaths(
        animated: Bool,
        transition: RailMotion.Transition,
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        railLayer.frame = bounds
        settingsLayer.frame = bounds
        detailLayer.frame = bounds
        handleHighlightLayer.frame = bounds

        if previewState == .mini {
            updateCollapsedPaths(animated: animated, transition: transition)
        } else {
            updateExpandedPaths(animated: animated, transition: transition)
        }
        CATransaction.commit()
    }

    private func updateCollapsedPaths(
        animated: Bool,
        transition: RailMotion.Transition,
    ) {
        set(
            railLayer,
            path: transformed(RailShellPaths.mini()),
            opacity: 1,
            animated: animated,
            transition: transition,
        )
        set(
            settingsLayer,
            path: transformed(
                RailShellPaths.settings(showsCircle: showsSettingsCircle),
            ),
            opacity: 0,
            animated: animated,
            transition: transition,
        )
        set(
            detailLayer,
            path: transformed(RailShellPaths.collapsedDetail(centerY: lastDetailCenterY)),
            opacity: 1,
            animated: animated,
            transition: transition,
        )
        // The highlight marks the collapsed handle, which is otherwise pure
        // black against whatever wallpaper is behind it.
        set(
            handleHighlightLayer,
            path: transformed(RailShellPaths.handleHighlight()),
            opacity: 1,
            animated: animated,
            transition: transition,
        )
    }

    private func updateExpandedPaths(
        animated: Bool,
        transition: RailMotion.Transition,
    ) {
        // Once the rail is open its own silhouette is the affordance, so the
        // handle's highlight goes away with it.
        set(
            handleHighlightLayer,
            path: transformed(RailShellPaths.handleHighlight()),
            opacity: 0,
            animated: animated,
            transition: transition,
        )
        set(
            railLayer,
            path: transformed(RailShellPaths.rail()),
            opacity: 1,
            animated: animated,
            transition: transition,
        )
        set(
            settingsLayer,
            path: transformed(
                RailShellPaths.settings(showsCircle: showsSettingsCircle),
            ),
            opacity: 1,
            animated: animated,
            transition: transition,
        )
        updateDetailPath(animated: animated, transition: transition)
    }

    /// The detail card's shape.
    ///
    /// It appears rather than growing, matching its contents, and only animates
    /// when travelling between provider rows.
    private func updateDetailPath(
        animated: Bool,
        transition: RailMotion.Transition,
    ) {
        let isAppearing = previewState.detailProviderID == nil ||
            !hasShownDetail
        let animatesShape = animated &&
            (RailMotion.animatesDetailAppearance || !isAppearing)
        hasShownDetail = previewState.detailProviderID != nil
        guard previewState.detailProviderID != nil else {
            set(
                detailLayer,
                path: transformed(RailShellPaths.collapsedDetail(centerY: lastDetailCenterY)),
                opacity: 1,
                animated: animatesShape,
                transition: transition,
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
            animated: animatesShape,
            transition: transition,
        )
    }

    /// The reference reveals faster than it dismisses, so the two directions do
    /// not share a duration or a curve.
    private func transition(
        from previousState: RailPreviewState,
        to nextState: RailPreviewState,
    ) -> RailMotion.Transition {
        if reducesMotion {
            return .reduced
        }
        if nextState == .mini {
            return .dismiss
        }
        return previousState == .mini ? .reveal : .detail
    }

    private func set(
        _ shapeLayer: CAShapeLayer,
        path: CGPath?,
        opacity: Float,
        animated: Bool,
        transition: RailMotion.Transition,
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
            pathAnimation.duration = transition.duration
            pathAnimation.timingFunction = transition.timing
            pathAnimation.preferredFrameRateRange = RailMotion.preferredFrameRateRange
            shapeLayer.add(pathAnimation, forKey: "pace.path")
        }

        if currentOpacity != opacity {
            let opacityAnimation = CABasicAnimation(keyPath: "opacity")
            opacityAnimation.fromValue = currentOpacity
            opacityAnimation.toValue = opacity
            let fade = reducesMotion
                ? RailMotion.Transition.reduced
                : transition.capped(at: transition.contentDuration)
            opacityAnimation.duration = fade.duration
            opacityAnimation.timingFunction = fade.timing
            opacityAnimation.preferredFrameRateRange = RailMotion.preferredFrameRateRange
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

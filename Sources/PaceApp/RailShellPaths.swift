import CoreGraphics
import Foundation

/// The rail's shell paths. Each is authored top-down and flipped once by the
/// layer view, so a smaller y is higher on screen.
enum RailShellPaths {
    /// The collapsed handle: a small pill flush with the screen edge, with only
    /// its inner side rounded.
    static func mini() -> CGPath {
        let rect = RailShellMetrics.handleRect
        let radius = min(
            RailShellMetrics.handleRadius,
            rect.height / 2,
        )
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCompatibleLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            control1: CGPoint(x: rect.minX + radius * 0.45, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: rect.minY + radius * 0.45),
        )
        path.addCompatibleLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.maxY - radius * 0.45),
            control2: CGPoint(x: rect.minX + radius * 0.45, y: rect.maxY),
        )
        path.addCompatibleLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCompatibleLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }

    /// The hairline along the collapsed handle's inner edge.
    ///
    /// Only the rounded inner side is stroked. The flat side sits against the
    /// screen edge, where half the stroke would be off screen and the visible
    /// half would read heavier than the rest of the line.
    static func handleHighlight() -> CGPath {
        let rect = RailShellMetrics.handleRect
        let radius = min(RailShellMetrics.handleRadius, rect.height / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCompatibleLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            control1: CGPoint(x: rect.minX + radius * 0.45, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: rect.minY + radius * 0.45),
        )
        path.addCompatibleLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.maxY - radius * 0.45),
            control2: CGPoint(x: rect.minX + radius * 0.45, y: rect.maxY),
        )
        path.addCompatibleLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }

    static func rail() -> CGPath {
        let path = CGMutablePath()
        let leftX = EdgeRailGeometry.canvasSize.width - RailShellMetrics.railWidth
        let rightX = EdgeRailGeometry.canvasSize.width
        let width = RailShellMetrics.railWidth
        let contourHeight = RailShellMetrics.contourHeight

        // Start at the screen edge above the body and sweep in along the top
        // contour.
        path.move(to: CGPoint(x: rightX, y: RailShellMetrics.topEdgeY))
        RailContour.append(
            to: path,
            placement: RailContour.Placement(
                width: width,
                height: contourHeight,
                edgePoint: CGPoint(x: rightX, y: RailShellMetrics.topEdgeY),
                inward: -1,
                downward: 1,
            ),
        )

        // Straight body.
        path.addCompatibleLine(to: CGPoint(x: leftX, y: RailShellMetrics.bodyBottomY))

        // Mirror the contour back out to the screen edge.
        RailContour.appendReversed(
            to: path,
            placement: RailContour.Placement(
                width: width,
                height: contourHeight,
                edgePoint: CGPoint(x: rightX, y: RailShellMetrics.bottomEdgeY),
                inward: -1,
                downward: -1,
            ),
        )

        path.addCompatibleLine(to: CGPoint(x: rightX, y: RailShellMetrics.topEdgeY))
        path.closeSubpath()
        return path
    }

    /// The resting settings control.
    ///
    /// The running reference application draws a round-capped quarter-circle
    /// arc below the rail rather than a filled circle. The arc runs from
    /// straight up to straight left, echoing the rail contour's curvature, and
    /// its separation from the rail is part of the silhouette. The filled
    /// circle in the reference video is this control's hover state.
    static func settings(showsCircle: Bool) -> CGPath {
        if showsCircle {
            let path = CGMutablePath()
            path.addEllipse(in: RailShellMetrics.settingsCircleRect)
            return path
        }
        let center = RailShellMetrics.settingsArcCenter
        let arc = CGMutablePath()
        // Paths here are authored top-down and flipped once for display, so a
        // smaller y is higher on screen. The traced arc runs from straight up
        // round to straight left, which is the quarter from -pi/2 to -pi.
        arc.addArc(
            center: center,
            radius: RailShellMetrics.settingsArcRadius,
            startAngle: -.pi / 2,
            endAngle: -.pi,
            clockwise: true,
        )
        return CGPath(
            __byStroking: arc,
            transform: nil,
            lineWidth: RailShellMetrics.settingsArcStroke,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10,
        ) ?? arc
    }

    static func detail(centerY: CGFloat, panelHeight: CGFloat) -> CGPath {
        let panelY = EdgeRailGeometry.detailPanelY(centerY: centerY, height: panelHeight)
        let rect = CGRect(
            x: 0,
            y: panelY,
            width: EdgeRailGeometry.detailWidth,
            height: panelHeight,
        )
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

        appendConnector(to: path, panelRightX: rect.maxX, centerY: centerY)
        return path
    }

    /// The wedge joining the detail panel to the active provider ring.
    ///
    /// Measured from settings-claude-detail.png: 61 px tall and 54 px deep on a
    /// 139 px rail, so 30.7 pt by 27.2 pt. Its depth grows linearly, so the
    /// silhouette is a triangle, but the apex holds its depth across two rows
    /// rather than coming to a point. Rounding the tip and the two base corners
    /// keeps that reading without turning it into a blunt tab.
    private static func appendConnector(
        to path: CGMutablePath,
        panelRightX: CGFloat,
        centerY: CGFloat,
    ) {
        let halfHeight = RailShellMetrics.connectorHeight / 2
        let baseX = panelRightX - 1
        let tipX = baseX + RailShellMetrics.connectorDepth
        let tipRadius = RailShellMetrics.connectorTipRadius
        let baseRadius = RailShellMetrics.connectorBaseRadius
        let slope = RailShellMetrics.connectorDepth / halfHeight
        let baseOffset = baseRadius * slope

        path.move(to: CGPoint(x: baseX, y: centerY - halfHeight + baseRadius))
        path.addQuadCurve(
            to: CGPoint(x: baseX + baseOffset, y: centerY - halfHeight + baseRadius),
            control: CGPoint(x: baseX, y: centerY - halfHeight),
        )
        path.addCompatibleLine(
            to: CGPoint(x: tipX - tipRadius * slope, y: centerY - tipRadius),
        )
        path.addQuadCurve(
            to: CGPoint(x: tipX - tipRadius * slope, y: centerY + tipRadius),
            control: CGPoint(x: tipX, y: centerY),
        )
        path.addCompatibleLine(
            to: CGPoint(x: baseX + baseOffset, y: centerY + halfHeight - baseRadius),
        )
        path.addQuadCurve(
            to: CGPoint(x: baseX, y: centerY + halfHeight - baseRadius),
            control: CGPoint(x: baseX, y: centerY + halfHeight),
        )
        path.closeSubpath()
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

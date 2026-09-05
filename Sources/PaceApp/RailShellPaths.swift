import CoreGraphics
import Foundation

/// Paths are authored top-down. The surface applies edge and view transforms once.
enum RailShellPaths {
    static func rail(providerRowCount: Int) -> CGPath {
        reveal(progress: 1, providerRowCount: providerRowCount)
    }

    static func mini(providerRowCount: Int) -> CGPath {
        reveal(progress: 0, providerRowCount: providerRowCount)
    }

    static func reveal(progress: Double, providerRowCount: Int) -> CGPath {
        let mini = RailShellMetrics.handleRect(providerRowCount: providerRowCount)
        let top = RailShellMetrics.topEdgeY
        let bottom = RailShellMetrics.bottomEdgeY(providerRowCount: providerRowCount)
        let edge = EdgeRailGeometry.canvasSize.width
        let width = max(1, mini.width + (RailShellMetrics.railWidth - mini.width) * progress)
        let height = max(1, mini.height + (bottom - top - mini.height) * progress)
        let topY = mini.minY + (top - mini.minY) * progress
        let rect = CGRect(x: edge - width, y: topY, width: width, height: height)
        let corner = min(78.8 * 44 / 117, width / 2)
        let flare = max(0, min(RailShellMetrics.contourHeight, height / 2, width - corner))
        let radius = min(corner, (height - 2 * flare) / 2)
        let bodyTop = topY + flare
        let bodyBottom = rect.maxY - flare
        let path = CGMutablePath()
        path.move(to: CGPoint(x: edge, y: topY))
        path.addArc(
            center: CGPoint(x: edge - flare, y: topY),
            radius: flare,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: false,
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: bodyTop))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: bodyTop + radius),
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: -.pi,
            clockwise: true,
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyBottom - radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: bodyBottom - radius),
            radius: radius,
            startAngle: .pi,
            endAngle: .pi / 2,
            clockwise: true,
        )
        path.addLine(to: CGPoint(x: edge - flare, y: bodyBottom))
        path.addArc(
            center: CGPoint(x: edge - flare, y: rect.maxY),
            radius: flare,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: false,
        )
        path.closeSubpath()
        return path
    }

    static func handleHighlight(providerRowCount: Int) -> CGPath {
        mini(providerRowCount: providerRowCount)
    }

    static func settings(showsCircle: Bool, providerRowCount: Int) -> CGPath {
        if showsCircle {
            return CGPath(
                ellipseIn: RailShellMetrics.settingsCircleRect(providerRowCount: providerRowCount),
                transform: nil,
            )
        }
        let arc = CGMutablePath()
        arc.addArc(
            center: RailShellMetrics.settingsArcCenter(providerRowCount: providerRowCount),
            radius: RailShellMetrics.settingsArcRadius,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: false,
        )
        return arc.copy(
            strokingWithWidth: RailShellMetrics.settingsArcStroke,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10,
        )
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
}

private extension CGMutablePath {
    func addCompatibleLine(to point: CGPoint) {
        addLine(to: point)
    }
}

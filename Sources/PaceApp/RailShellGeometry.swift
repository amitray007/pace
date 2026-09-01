import AppKit
import CoreGraphics
import Foundation

/// Rail silhouette values, expressed as ratios of the rail's width so the
/// shape stays identical at any scale.
///
/// Every ratio comes from a subpixel trace of the running reference
/// application, where the rail body measures 139 px wide. Deriving the layout
/// from one width means a scale preference changes size without changing the
/// silhouette.
enum RailShellMetrics {
    /// The rail's width in canvas points at the default scale.
    static let railWidth = EdgeRailGeometry.railWidth

    /// Ring diameter, 87 px on a 139 px rail.
    static let ringDiameterRatio: CGFloat = 0.6259

    /// Distance between adjacent ring centres, 205 px on a 139 px rail.
    static let ringPitchRatio: CGFloat = 1.4748

    /// Distance from the top of the straight body to the first ring's centre,
    /// 52 px on a 139 px rail.
    static let firstRingInsetRatio: CGFloat = 0.3705

    /// The resting settings control is a quarter-circle arc below the rail, not
    /// a filled circle. Its centreline radius is 62.7 px and its stroke is
    /// 15 px on a 137 px rail.
    static let settingsArcRadiusRatio: CGFloat = 0.4573
    static let settingsArcStrokeRatio: CGFloat = 0.1095

    /// The arc's centre, inboard of the screen edge and below the rail body.
    static let settingsArcCenterInsetRatio: CGFloat = 0.5791
    static let settingsArcCenterDropRatio: CGFloat = 0.5182

    /// The hover state's filled circle, 90 px on a 139 px rail.
    static let settingsDiameterRatio: CGFloat = 0.6475

    static var ringDiameter: CGFloat {
        railWidth * ringDiameterRatio
    }

    static var ringPitch: CGFloat {
        railWidth * ringPitchRatio
    }

    static var contourHeight: CGFloat {
        RailContour.height(forWidth: railWidth)
    }

    static var settingsDiameter: CGFloat {
        railWidth * settingsDiameterRatio
    }

    static var settingsArcRadius: CGFloat {
        railWidth * settingsArcRadiusRatio
    }

    /// The hover glyph, sized against the filled circle it sits in.
    static var settingsGlyphSize: CGFloat {
        settingsDiameter * 0.44
    }

    static var settingsArcStroke: CGFloat {
        railWidth * settingsArcStrokeRatio
    }

    /// Centre of the quarter-circle the resting settings arc is drawn on.
    static var settingsArcCenter: CGPoint {
        CGPoint(
            x: EdgeRailGeometry.canvasSize.width
                - railWidth * settingsArcCenterInsetRatio,
            y: bodyBottomY + railWidth * settingsArcCenterDropRatio,
        )
    }

    /// The first ring's centre, which anchors the whole vertical layout.
    static var firstRingCenterY: CGFloat {
        EdgeRailGeometry.providerCentersY[0]
    }

    /// Where the straight body starts, above the first ring.
    static var bodyTopY: CGFloat {
        firstRingCenterY - railWidth * firstRingInsetRatio
    }

    /// Where the straight body ends, below the last ring by the same inset.
    static var bodyBottomY: CGFloat {
        (EdgeRailGeometry.providerCentersY.last ?? firstRingCenterY)
            + railWidth * firstRingInsetRatio
    }

    /// Where the top contour meets the screen edge.
    static var topEdgeY: CGFloat {
        bodyTopY - contourHeight
    }

    /// Where the bottom contour meets the screen edge.
    static var bottomEdgeY: CGFloat {
        bodyBottomY + contourHeight
    }

    /// The detached settings circle, centred on the rail and sitting below the
    /// bottom contour's negative space.
    static var settingsCircleRect: CGRect {
        let diameter = settingsDiameter
        let center = settingsArcCenter
        return CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter,
        )
    }

    static var settingsCircleCenter: CGPoint {
        CGPoint(x: settingsCircleRect.midX, y: settingsCircleRect.midY)
    }

    /// The collapsed handle.
    ///
    /// This is the only thing on screen while the rail is closed, so it stays
    /// small enough to read as a hint rather than a bar sitting on the edge.
    /// It is centred on the rail's own vertical centre so opening the rail
    /// grows out of where the handle was.
    static let handleWidth: CGFloat = 6
    static let handleHeight: CGFloat = 34

    /// The handle's rounded end. Half its width, so the inner edge is a
    /// semicircle rather than a rectangle with clipped corners.
    static var handleRadius: CGFloat {
        handleWidth / 2
    }

    /// The handle's frame, which the shell path and the pointer's hit region
    /// both derive from so the visible and clickable areas cannot drift apart.
    static var handleRect: CGRect {
        let centerY = (bodyTopY + bodyBottomY) / 2
        return CGRect(
            x: EdgeRailGeometry.canvasSize.width - handleWidth,
            y: centerY - handleHeight / 2,
            width: handleWidth,
            height: handleHeight,
        )
    }

    /// The handle's edge hairline. White at low opacity reads as a highlight on
    /// any wallpaper, where a fixed grey would vanish against a light one.
    static let handleHighlightColor = NSColor(white: 1, alpha: 0.32)
    static let handleHighlightWidth: CGFloat = 1

    /// A pointer target smaller than this is hard to hit deliberately, so the
    /// hit region is grown around the handle without making it look larger.
    static let minimumHandleTargetWidth: CGFloat = 18
    static let minimumHandleTargetHeight: CGFloat = 70

    /// The handle's hit region: the visible handle, expanded to a comfortable
    /// target.
    static var handleTargetRect: CGRect {
        let rect = handleRect
        let width = max(rect.width, minimumHandleTargetWidth)
        let height = max(rect.height, minimumHandleTargetHeight)
        return CGRect(
            x: EdgeRailGeometry.canvasSize.width - width,
            y: rect.midY - height / 2,
            width: width,
            height: height,
        )
    }
}

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

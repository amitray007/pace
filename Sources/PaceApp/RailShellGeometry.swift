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

    /// The connector joining the detail panel to the active provider ring.
    /// Measured at 61 px tall and 54 px deep on a 139 px rail.
    static var connectorHeight: CGFloat {
        railWidth * (61.0 / 139.0)
    }

    static var connectorDepth: CGFloat {
        railWidth * (54.0 / 139.0)
    }

    /// The reference apex holds its depth across two rows rather than coming to
    /// a point, so the tip is rounded rather than sharp.
    static var connectorTipRadius: CGFloat {
        connectorHeight * 0.16
    }

    /// Softens where the connector meets the panel, so the join reads as one
    /// shape instead of a wedge stuck onto a card.
    static var connectorBaseRadius: CGFloat {
        connectorHeight * 0.12
    }

    /// The resting settings control is a small arc tucked against the screen
    /// edge below the rail, not a sweep across the rail's width.
    ///
    /// Measured in the running reference application, where the arc occupies
    /// x 11 to 27 and y 5 to 30 below the body end on a 137 px rail: 0.08 to
    /// 0.20 of the rail's width inward and 0.04 to 0.22 below it, so the
    /// control stays well inside the rail's own footprint. The earlier values
    /// were roughly four times that and swept past the rail's inner edge,
    /// which made the arc read as a stray tendril rather than a control.
    static let settingsArcRadiusRatio: CGFloat = 0.115
    static let settingsArcStrokeRatio: CGFloat = 0.055

    /// The arc's centre, inboard of the screen edge and below the rail body.
    static let settingsArcCenterInsetRatio: CGFloat = 0.10
    static let settingsArcCenterDropRatio: CGFloat = 0.16

    /// The hover state's filled circle.
    ///
    /// The resting arc is small and sits against the screen edge, so the hover
    /// target has to be large enough to hit and to hold a legible gear.
    static let settingsDiameterRatio: CGFloat = 0.42

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
    static let handleWidth: CGFloat = 8
    static let handleHeight: CGFloat = 52

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

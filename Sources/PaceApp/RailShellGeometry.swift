import AppKit
import CoreGraphics
import Foundation

enum RailShellMetrics {
    static let railWidth = EdgeRailGeometry.railWidth

    static let ringDiameterRatio: CGFloat = 0.6259

    static let ringPitchRatio: CGFloat = 1.4748

    static let firstRingInsetRatio: CGFloat = (22 + 69.5 * 44 / 117) / 70

    static var connectorHeight: CGFloat {
        railWidth * (61.0 / 139.0)
    }

    static var connectorDepth: CGFloat {
        railWidth * (54.0 / 139.0)
    }

    static var connectorTipRadius: CGFloat {
        connectorHeight * 0.16
    }

    static var connectorBaseRadius: CGFloat {
        connectorHeight * 0.12
    }

    static let settingsArcRadiusRatio: CGFloat = (103 - 27) * 44 / 117 / 70
    static let settingsArcStrokeRatio: CGFloat = 18 * 44 / 117 / 70

    static let settingsArcCenterInsetRatio: CGFloat = 103 * 44 / 117 / 70
    static let settingsArcCenterDropRatio: CGFloat = 103 * 44 / 117 / 70

    static let settingsDiameterRatio: CGFloat = 124 * 44 / 117 / 70

    static var ringDiameter: CGFloat {
        railWidth * ringDiameterRatio
    }

    static var ringPitch: CGFloat {
        railWidth * ringPitchRatio
    }

    static var contourHeight: CGFloat {
        103 * 44 / 117
    }

    static var settingsDiameter: CGFloat {
        railWidth * settingsDiameterRatio
    }

    static var settingsArcRadius: CGFloat {
        railWidth * settingsArcRadiusRatio
    }

    static var settingsGlyphSize: CGFloat {
        settingsDiameter * 0.44
    }

    static var settingsArcStroke: CGFloat {
        railWidth * settingsArcStrokeRatio
    }

    static func settingsArcCenter(providerRowCount: Int) -> CGPoint {
        CGPoint(
            x: EdgeRailGeometry.canvasSize.width
                - railWidth * settingsArcCenterInsetRatio,
            y: bodyBottomY(providerRowCount: providerRowCount) + railWidth *
                settingsArcCenterDropRatio,
        )
    }

    static var firstRingCenterY: CGFloat {
        EdgeRailGeometry.firstProviderCenterY
    }

    static var bodyTopY: CGFloat {
        firstRingCenterY - railWidth * firstRingInsetRatio
    }

    static func bodyBottomY(providerRowCount: Int) -> CGFloat {
        let centers = EdgeRailGeometry.providerCentersY(count: providerRowCount)
        return (centers.last ?? firstRingCenterY) + 22 + 27 * 44 / 117 + 17 + 50.1 * 44 / 117
    }

    static var topEdgeY: CGFloat {
        bodyTopY - contourHeight
    }

    static func bottomEdgeY(providerRowCount: Int) -> CGFloat {
        bodyBottomY(providerRowCount: providerRowCount) + contourHeight
    }

    static func settingsCircleRect(providerRowCount: Int) -> CGRect {
        let diameter = settingsDiameter
        let center = settingsArcCenter(providerRowCount: providerRowCount)
        return CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter,
        )
    }

    static func settingsCircleCenter(providerRowCount: Int) -> CGPoint {
        let rect = settingsCircleRect(providerRowCount: providerRowCount)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    static let handleWidth: CGFloat = 11
    static let handleHeight: CGFloat = 76

    static var handleRadius: CGFloat {
        handleWidth / 2
    }

    static func handleRect(providerRowCount: Int) -> CGRect {
        let centerY = (bodyTopY + bodyBottomY(providerRowCount: providerRowCount)) / 2
        return CGRect(
            x: EdgeRailGeometry.canvasSize.width - handleWidth,
            y: centerY - handleHeight / 2,
            width: handleWidth,
            height: handleHeight,
        )
    }

    static let handleHighlightColor = NSColor(white: 1, alpha: 0.32)
    static let handleHighlightWidth: CGFloat = 1

    static let minimumHandleTargetWidth: CGFloat = 24
    static let minimumHandleTargetHeight: CGFloat = 132

    static func handleTargetRect(providerRowCount: Int) -> CGRect {
        let rect = handleRect(providerRowCount: providerRowCount)
        let width = max(rect.width, minimumHandleTargetWidth)
        let height = max(rect.height, minimumHandleTargetHeight)
        return CGRect(
            x: EdgeRailGeometry.canvasSize.width - width,
            y: rect.midY - height / 2,
            width: width,
            height: height,
        )
    }

    static func hoverTargetRect(providerRowCount: Int) -> CGRect {
        let handle = handleTargetRect(providerRowCount: providerRowCount)
        let top = min(topEdgeY, handle.minY)
        let bottom = max(bottomEdgeY(providerRowCount: providerRowCount), handle.maxY)
        return CGRect(
            x: handle.minX,
            y: top,
            width: handle.width,
            height: bottom - top,
        )
    }
}

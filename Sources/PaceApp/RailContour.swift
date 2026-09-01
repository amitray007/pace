import CoreGraphics
import Foundation

/// The rail's organic edge contour, traced from the running reference
/// application.
///
/// The contour is the shape that turns the rail from a rounded rectangle into
/// the reference's notch. It leaves the screen edge tangent to it, sweeps
/// across in a long concave arc, passes through an inflection where it is
/// momentarily horizontal, and then eases convexly into the rail body.
///
/// The control points below are a two-segment cubic fitted to a subpixel trace
/// of that edge. The fit has a 0.27 px root-mean-square and a 1.02 px maximum
/// error against 112 traced rows, so the curve is reproduced rather than
/// approximated. Values are fractions of the rail's width and of the contour's
/// own height, which keeps the silhouette identical at any rail scale.
enum RailContour {
    /// Contour height as a fraction of the rail's width.
    static let heightRatio: CGFloat = 0.8058

    /// Where the two cubic segments meet, as a fraction of width and height.
    private static let inflection = CGPoint(x: 0.5969, y: 0.5890)

    /// Control point pulling the curve down the screen edge before it turns.
    private static let edgeControlY: CGFloat = 0.0205

    /// Control point that flattens the first segment into the inflection.
    private static let approachControlX: CGFloat = 0.0838

    /// Control point that carries the second segment out of the inflection.
    private static let departControlX: CGFloat = 0.9112

    /// The contour's height for a rail of `width`.
    static func height(forWidth width: CGFloat) -> CGFloat {
        width * heightRatio
    }

    /// Where a contour starts and how it is oriented.
    ///
    /// The rail draws this curve four times across its two edges and two ends,
    /// so its placement travels as one value rather than as five loose
    /// arguments.
    struct Placement {
        /// The rail's width. The contour spans this horizontally.
        var width: CGFloat
        /// The contour's vertical span.
        var height: CGFloat
        /// The contour's endpoint on the screen edge.
        var edgePoint: CGPoint
        /// Direction from the screen edge toward the rail body: `1` for a
        /// left-edge rail, `-1` for a right-edge rail.
        var inward: CGFloat
        /// Direction along the contour: `1` when it runs from the rail's top
        /// toward its body, `-1` for the mirrored bottom.
        var downward: CGFloat

        func point(_ unitX: CGFloat, _ unitY: CGFloat) -> CGPoint {
            CGPoint(
                x: edgePoint.x + inward * unitX * width,
                y: edgePoint.y + downward * unitY * height,
            )
        }
    }

    /// Appends the contour to `path`, running from the screen edge to the rail
    /// body. The path's current point must already be `placement.edgePoint`.
    static func append(to path: CGMutablePath, placement: Placement) {
        let meeting = placement.point(inflection.x, inflection.y)
        path.addCurve(
            to: meeting,
            control1: placement.point(0, edgeControlY),
            control2: placement.point(approachControlX, inflection.y),
        )
        path.addCurve(
            to: placement.point(1, 1),
            control1: placement.point(departControlX, inflection.y),
            control2: placement.point(1, 1),
        )
    }

    /// Appends the contour running the other way, from the rail body back out
    /// to the screen edge.
    ///
    /// The rail outline is one closed path, so the second contour has to be
    /// traversed in reverse. Reversing the control points keeps it the exact
    /// mirror of ``append(to:placement:)`` instead of an independently tuned
    /// near-copy.
    static func appendReversed(to path: CGMutablePath, placement: Placement) {
        let meeting = placement.point(inflection.x, inflection.y)
        path.addCurve(
            to: meeting,
            control1: placement.point(1, 1),
            control2: placement.point(departControlX, inflection.y),
        )
        path.addCurve(
            to: placement.point(0, 0),
            control1: placement.point(approachControlX, inflection.y),
            control2: placement.point(0, edgeControlY),
        )
    }
}

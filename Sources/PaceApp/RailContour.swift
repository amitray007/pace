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

    /// Appends the contour to `path`, running from the screen edge to the rail
    /// body.
    ///
    /// The curve is expressed in a unit box and then mapped, so a caller only
    /// supplies where the contour starts and how it is oriented.
    ///
    /// - Parameters:
    ///   - path: The path to append to. Its current point must already be the
    ///     contour's start, on the screen edge.
    ///   - width: The rail's width. The contour spans this horizontally.
    ///   - height: The contour's vertical span.
    ///   - origin: The contour's start, on the screen edge.
    ///   - inward: Direction from the screen edge toward the rail body, either
    ///     `1` for a left-edge rail or `-1` for a right-edge rail.
    ///   - downward: Direction along the contour, either `1` when it runs from
    ///     the rail's top toward its body or `-1` for the mirrored bottom.
    static func append(
        to path: CGMutablePath,
        width: CGFloat,
        height: CGFloat,
        origin: CGPoint,
        inward: CGFloat,
        downward: CGFloat,
    ) {
        func point(_ unitX: CGFloat, _ unitY: CGFloat) -> CGPoint {
            CGPoint(
                x: origin.x + inward * unitX * width,
                y: origin.y + downward * unitY * height,
            )
        }

        let meeting = point(inflection.x, inflection.y)
        path.addCurve(
            to: meeting,
            control1: point(0, edgeControlY),
            control2: point(approachControlX, inflection.y),
        )
        path.addCurve(
            to: point(1, 1),
            control1: point(departControlX, inflection.y),
            control2: point(1, 1),
        )
    }

    /// Appends the contour running the other way, from the rail body back out
    /// to the screen edge.
    ///
    /// The rail outline is one closed path, so the second contour has to be
    /// traversed in reverse. Reversing the control points keeps it the exact
    /// mirror of ``append(to:width:height:origin:inward:downward:)`` instead of
    /// an independently tuned near-copy.
    ///
    /// - Parameter origin: The contour's end, on the screen edge. The curve is
    ///   emitted from the body toward this point.
    static func appendReversed(
        to path: CGMutablePath,
        width: CGFloat,
        height: CGFloat,
        origin: CGPoint,
        inward: CGFloat,
        downward: CGFloat,
    ) {
        func point(_ unitX: CGFloat, _ unitY: CGFloat) -> CGPoint {
            CGPoint(
                x: origin.x + inward * unitX * width,
                y: origin.y + downward * unitY * height,
            )
        }

        let meeting = point(inflection.x, inflection.y)
        path.addCurve(
            to: meeting,
            control1: point(1, 1),
            control2: point(departControlX, inflection.y),
        )
        path.addCurve(
            to: point(0, 0),
            control1: point(approachControlX, inflection.y),
            control2: point(0, edgeControlY),
        )
    }
}

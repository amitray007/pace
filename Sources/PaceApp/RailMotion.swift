import QuartzCore
import SwiftUI

/// Rail motion values measured from the reference recording.
///
/// The rail's width was sampled per frame across
/// `.local/references/source/side-notch-settings.mp4`, giving the reveal and
/// dismissal durations directly and a progress curve to fit a timing function
/// against. The fitted curves sit within a 0.010 and 0.004 root-mean-square of
/// the sampled progress, so these are measurements rather than estimates.
///
/// The previous timing function, `(0.2, 0.8, 0.2, 1)`, was the worst fit of
/// every curve tried against that data at 0.194. It front-loads the motion far
/// harder than the reference, which is why the reveal read as a snap rather
/// than a settle.
enum RailMotion {
    /// How much quicker Pace runs than the reference recording.
    ///
    /// The reference is a showcase; Pace is glanced at many times a day, so the
    /// same motion plays faster. Only durations scale. The fitted easing curves
    /// are unchanged, which keeps the reference's character.
    static let speedFactor: CFTimeInterval = 0.75

    /// The mini handle grows to the full rail. Measured at 0.250 s.
    ///
    /// Opening is scaled harder than the rest. Hovering the handle is the one
    /// moment the user is waiting on the rail rather than reading it, so the
    /// reveal answers the pointer almost immediately.
    static let revealDuration = 0.25 * speedFactor * 0.6

    /// The rail collapses back to the mini handle. Measured at 0.300 s.
    /// Dismissal is slower than reveal in the reference, so leaving does not
    /// feel abrupt, and that relationship survives the scaling.
    static let dismissDuration = 0.3 * speedFactor

    /// The attached panel moving between provider rows.
    ///
    /// Measured across three switches in the reference recording: 0.333 s,
    /// 0.383 s, and 0.384 s. The panel travels further than the rail does when
    /// it opens, and taking longer over it is what makes the move read as one
    /// object gliding between rows rather than as a jump.
    static let detailDuration = 0.37 * speedFactor

    static let contentDismissDuration = 0.08 * speedFactor
    static let reducedMotionFadeDuration = 0.1 * speedFactor

    /// Fraction of a shell transition that passes before its content starts to
    /// appear, so the shape is established before anything is drawn inside it.
    ///
    /// The content's fade occupies the remainder, so it always finishes exactly
    /// when the shell stops moving. Expressing it this way means the two cannot
    /// drift apart.
    static let contentRevealDelayFraction: CFTimeInterval = 0.3

    /// Fraction of a shell transition that the content's own fade occupies.
    static var contentFadeFraction: CFTimeInterval {
        1 - contentRevealDelayFraction
    }

    /// The attached detail panel appears rather than animating open.
    ///
    /// The panel is read and dismissed in about a second, so an entrance is
    /// time spent waiting to read it. Appearing also removes any chance of the
    /// shell and its contents arriving separately, which is what made the bars
    /// show up before the panel behind them. The panel still moves between
    /// provider rows, because that movement is what ties it to the ring it
    /// belongs to.
    static let animatesDetailAppearance = false

    /// Fitted from the reference reveal, 0.010 root-mean-square.
    static let timingFunction = CAMediaTimingFunction(
        controlPoints: 0.24,
        0.32,
        0.39,
        0.95,
    )

    /// Fitted from the reference dismissal, 0.004 root-mean-square.
    static let dismissTimingFunction = CAMediaTimingFunction(
        controlPoints: 0.28,
        0.12,
        0.31,
        0.95,
    )

    /// Fitted from a reference provider switch, 0.006 root-mean-square.
    ///
    /// The near-zero start ramp means the panel leaves immediately and spends
    /// most of the duration decelerating into place. The reveal curve fitted
    /// this movement four times worse, so the two are not shared.
    static let detailTimingFunction = CAMediaTimingFunction(
        controlPoints: 0.07,
        0.02,
        0.32,
        1,
    )

    /// The reveal curve for SwiftUI content, so the hosted labels and the
    /// Core Animation shell ease identically.
    static func contentTiming(duration: TimeInterval) -> Animation {
        .timingCurve(0.24, 0.32, 0.39, 0.95, duration: duration)
    }

    /// One transition's duration and curve. They are always chosen together, so
    /// they travel together.
    struct Transition {
        var duration: CFTimeInterval
        var timing: CAMediaTimingFunction

        /// When this transition's content should start appearing.
        var contentDelay: CFTimeInterval {
            duration * contentRevealDelayFraction
        }

        /// How long that content takes to appear. It finishes with the shell.
        var contentDuration: CFTimeInterval {
            duration * contentFadeFraction
        }

        static let reveal = Self(
            duration: revealDuration,
            timing: timingFunction,
        )
        static let dismiss = Self(
            duration: dismissDuration,
            timing: dismissTimingFunction,
        )
        static let detail = Self(
            duration: detailDuration,
            timing: detailTimingFunction,
        )
        static let reduced = Self(
            duration: reducedMotionFadeDuration,
            timing: timingFunction,
        )

        /// The same curve over a shorter span, for a fade that should finish
        /// before the shape it accompanies.
        func capped(at limit: CFTimeInterval) -> Self {
            Self(duration: min(duration, limit), timing: timing)
        }
    }
}

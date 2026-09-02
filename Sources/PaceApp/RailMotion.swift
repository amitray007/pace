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
    ///
    /// It was scaled to 0.6 while the rows faded in over whatever was behind
    /// them, because a shorter reveal hid that mismatch. Now that the rows are
    /// clipped to the silhouette, the growth is the thing being watched, and
    /// at 112 ms it was over before it read as movement. 146 ms is still well
    /// under the reference's 250 ms.
    static let revealDuration = 0.25 * speedFactor * 0.78

    /// The rail collapses back to the mini handle. Measured at 0.300 s.
    /// Dismissal is slower than reveal in the reference, so leaving does not
    /// feel abrupt, and that relationship survives the scaling.
    static let dismissDuration = 0.3 * speedFactor

    /// The attached panel moving between provider rows.
    ///
    /// Measured across three switches in the reference recording: 0.333 s,
    /// 0.383 s, and 0.384 s. The panel travels further than the rail does when
    /// it opens, and taking some time over it is what makes the move read as
    /// one object gliding between rows rather than as a jump.
    ///
    /// Scaled harder than the rest, though. Every provider's panel is built and
    /// laid out before the rail opens, so a switch is waiting on the animation
    /// and nothing else. Comparing several providers means making this move
    /// repeatedly, and at the reference duration it was two and a half times
    /// the reveal.
    static let detailDuration = 0.37 * speedFactor * 0.62

    static let contentDismissDuration = 0.08 * speedFactor
    static let reducedMotionFadeDuration = 0.1 * speedFactor

    /// Fraction of a shell transition that passes before its content starts to
    /// appear, so the shape is established before anything is drawn inside it.
    ///
    /// The content's fade occupies the remainder, so it always finishes exactly
    /// when the shell stops moving. Expressing it this way means the two cannot
    /// drift apart.
    ///
    /// This was 0.3 while the rows were drawn at their final positions with
    /// nothing clipping them, so the fade had to wait for the silhouette to
    /// reach them. The rows are now masked by the shell, so nothing can appear
    /// outside it, and the delay only needs to give the shape a visible lead
    /// so the reveal reads as the shell opening rather than the whole rail
    /// cross-fading in.
    static let contentRevealDelayFraction: CFTimeInterval = 0.12

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

    /// The frame rate the rail's animations ask for.
    ///
    /// On a ProMotion display Core Animation chooses a rate per animation, and
    /// a short path morph does not always earn the top one on its own. Every
    /// rail animation lasts well under half a second, so asking for the full
    /// rate costs nothing measurable and keeps the morph from stepping at 60
    /// on a 120 Hz panel. A 60 Hz display ignores the request.
    static let preferredFrameRateRange = CAFrameRateRange(
        minimum: 60,
        maximum: 120,
        preferred: 120,
    )

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

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
    /// The mini handle grows to the full rail in 0.250 s.
    static let revealDuration: CFTimeInterval = 0.25

    /// The rail collapses back to the mini handle in 0.300 s. Dismissal is
    /// slower than reveal in the reference, so leaving does not feel abrupt.
    static let dismissDuration: CFTimeInterval = 0.3

    /// The attached panel moving between provider rows. Shorter than a reveal
    /// because the shell is already open and only the panel travels.
    static let detailDuration: CFTimeInterval = 0.22

    static let contentFadeDuration: CFTimeInterval = 0.14
    static let contentDismissDuration: CFTimeInterval = 0.08
    static let contentRevealDelay: TimeInterval = 0.08
    static let reducedMotionFadeDuration: CFTimeInterval = 0.1

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
            timing: timingFunction,
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

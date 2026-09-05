import QuartzCore
import SwiftUI

/// Reference response and damping, evaluated with Apple's spring solver.
/// One surface clock drives every geometry and content track.
enum RailMotion {
    struct ScalarSpring: Sendable {
        let spring: Spring

        init(response: Double, dampingRatio: Double) {
            spring = Spring(response: response, dampingRatio: dampingRatio)
        }

        func value(target: Double, initialVelocity: Double, time: TimeInterval) -> Double {
            spring.value(target: target, initialVelocity: initialVelocity, time: time)
        }

        func velocity(target: Double, initialVelocity: Double, time: TimeInterval) -> Double {
            spring.velocity(target: target, initialVelocity: initialVelocity, time: time)
        }

        func settlingDuration(target: Double, initialVelocity: Double) -> TimeInterval {
            spring.settlingDuration(
                target: target,
                initialVelocity: initialVelocity,
                epsilon: 0.001,
            )
        }
    }

    static let unfoldSpring = ScalarSpring(response: 0.42, dampingRatio: 0.78)
    static let contentSpring = ScalarSpring(response: 0.36, dampingRatio: 0.82)
    static let glideSpring = ScalarSpring(response: 0.5, dampingRatio: 0.86)
    static let settingsSpring = ScalarSpring(response: 0.36, dampingRatio: 0.7)
    static let reducedMotionFadeDuration = 0.1
    static let preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)

    enum Curve {
        case spring(ScalarSpring)
        case fade(TimeInterval)
        case merge
    }

    /// An absolute-time track. Repeated targets are no-ops; reversals inherit
    /// both the sampled position and velocity, including between display ticks.
    struct Track {
        private(set) var target: Double
        private var origin: Double
        private var velocity = 0.0
        private var start = 0.0
        private var duration = 0.0
        private var curve: Curve = .fade(0)

        init(_ value: Double) {
            target = value
            origin = value
        }

        func sample(at time: TimeInterval) -> (value: Double, velocity: Double) {
            let elapsed = time - start
            guard elapsed > 0 else { return (origin, velocity) }
            guard elapsed < duration else { return (target, 0) }
            let distance = target - origin
            switch curve {
            case let .spring(spring):
                return (
                    origin + spring.value(
                        target: distance,
                        initialVelocity: velocity,
                        time: elapsed,
                    ),
                    spring.velocity(target: distance, initialVelocity: velocity, time: elapsed),
                )
            case .fade, .merge:
                let progress = elapsed / duration
                let easing: UnitCurve = if case .merge = curve {
                    .easeIn
                } else {
                    .easeInOut
                }
                return (
                    origin + distance * easing.value(at: progress),
                    distance * easing.velocity(at: progress) / duration,
                )
            }
        }

        mutating func retarget(
            _ value: Double,
            at time: TimeInterval,
            curve: Curve,
            delay: TimeInterval = 0,
            directly: Bool = false,
            restart: Bool = false,
        ) {
            guard value != target || directly || restart else { return }
            let current = sample(at: time)
            origin = directly ? value : current.value
            velocity = directly ? 0 : current.velocity
            target = value
            self.curve = curve
            // Never park an already moving object while a stagger catches up.
            start = time + (abs(velocity) < 0.001 ? delay : 0)
            duration = if directly {
                0
            } else {
                switch curve {
                case let .spring(spring):
                    spring.settlingDuration(target: target - origin, initialVelocity: velocity)
                case let .fade(seconds): seconds
                case .merge: 0.2
                }
            }
        }

        func isActive(at time: TimeInterval) -> Bool {
            time < start + duration
        }
    }
}

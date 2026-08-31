import QuartzCore

enum RailMotion {
    static let revealDuration: CFTimeInterval = 0.28
    static let detailDuration: CFTimeInterval = 0.22
    static let contentFadeDuration: CFTimeInterval = 0.14
    static let contentDismissDuration: CFTimeInterval = 0.08
    static let contentRevealDelay: TimeInterval = 0.08
    static let reducedMotionFadeDuration: CFTimeInterval = 0.1
    static let timingFunction = CAMediaTimingFunction(
        controlPoints: 0.2,
        0.8,
        0.2,
        1,
    )
}

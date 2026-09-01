import AppKit
import SwiftUI

/// The reference encodes remaining headroom with the accent color rather than
/// provider identity. Every rail ring and quota bar in the source frames uses
/// one of two accents: a spring green while usage is comfortable, and a neon
/// yellow once it is elevated. Pace adds a red step so an exhausted quota is not
/// reported with the same accent as a merely elevated one.
///
/// Measured from `.local/references/frames/settings-button.png` and
/// `settings-claude-detail.png`. The 41 percent bar is green and the 60 percent
/// bar is yellow, which places the elevated threshold between them.
enum UsageLevel: Equatable {
    /// Usage below `elevatedThreshold`.
    case comfortable
    /// Usage at or above `elevatedThreshold` and below `criticalThreshold`.
    case elevated
    /// Usage at or above `criticalThreshold`.
    case critical
    /// No usage fraction is available for this quota.
    case unavailable

    static let elevatedThreshold = 0.5
    static let criticalThreshold = 0.9

    static func resolve(_ fraction: Double?) -> Self {
        guard let fraction else {
            return .unavailable
        }
        if fraction >= criticalThreshold {
            return .critical
        }
        if fraction >= elevatedThreshold {
            return .elevated
        }
        return .comfortable
    }
}

/// Accent colors for each usage level, plus the neutral tracks they sit on.
enum UsageLevelPalette {
    /// `rgb(18, 255, 138)`, sampled from the reference rail arcs and the
    /// 41 percent quota bar.
    static let comfortable = NSColor(
        srgbRed: 18 / 255,
        green: 255 / 255,
        blue: 138 / 255,
        alpha: 1,
    )

    /// `rgb(223, 246, 0)`, sampled from the reference 60 percent quota bar and
    /// the elevated rail arc.
    static let elevated = NSColor(
        srgbRed: 223 / 255,
        green: 246 / 255,
        blue: 0,
        alpha: 1,
    )

    /// Pace's own step. The reference media never shows an exhausted quota, so
    /// this value is chosen to stay legible on the pure-black shell rather than
    /// sampled.
    static let critical = NSColor(
        srgbRed: 255 / 255,
        green: 69 / 255,
        blue: 58 / 255,
        alpha: 1,
    )

    /// `rgb(55, 55, 55)`, sampled from the reference ring track.
    static let track = NSColor(white: 55 / 255, alpha: 1)

    /// The track lightened so it stays distinguishable under increased contrast.
    static let increasedContrastTrack = NSColor(white: 0.42, alpha: 1)

    static func accent(for level: UsageLevel) -> NSColor {
        switch level {
        case .comfortable:
            comfortable
        case .elevated:
            elevated
        case .critical:
            critical
        case .unavailable:
            NSColor(white: 0.55, alpha: 1)
        }
    }

    static func accent(forFraction fraction: Double?) -> NSColor {
        accent(for: UsageLevel.resolve(fraction))
    }

    static func trackColor(increasedContrast: Bool) -> NSColor {
        increasedContrast ? increasedContrastTrack : track
    }
}

extension Color {
    static func paceUsageAccent(forFraction fraction: Double?) -> Self {
        Color(nsColor: UsageLevelPalette.accent(forFraction: fraction))
    }

    static func paceUsageTrack(increasedContrast: Bool) -> Self {
        Color(nsColor: UsageLevelPalette.trackColor(increasedContrast: increasedContrast))
    }
}

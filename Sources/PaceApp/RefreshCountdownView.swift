import SwiftUI

/// A live countdown to the next automatic refresh.
///
/// Replaces stating when data was last observed. An observation time answers
/// "how old is this", which the freshness state already covers; a countdown
/// answers "when will this change", which is what someone deciding whether to
/// wait or press refresh actually needs.
///
/// It says nothing when no refresh is scheduled, rather than counting toward
/// one that will not arrive.
struct RefreshCountdownView: View {
    /// How the remaining time is worded.
    enum Style {
        /// A bare "12:04" behind a refresh glyph. For places where something
        /// nearby already establishes what is being counted.
        case glyph
        /// A full "Refreshes in 12:04". For places where the countdown stands
        /// on its own and a bare number would not say what it referred to.
        case sentence
    }

    let nextRefreshAt: Date?
    let isRefreshing: Bool
    var style: Style = .glyph

    /// Drives the countdown.
    ///
    /// The timer is held in `@State` rather than created inline. A publisher
    /// built in the view's initializer is replaced on every rebuild, so
    /// switching provider tabs discarded the connected one and the countdown
    /// stopped moving until the panel was reopened.
    @State private var now = Date()
    @State private var tick = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            if style == .glyph {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
            }
            if isRefreshing {
                Text(refreshingText)
            } else if let remaining {
                Text(remaining)
                    .monospacedDigit()
            }
        }
        .onReceive(tick) { now = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The countdown text, or nil when nothing is scheduled.
    private var remaining: String? {
        switch schedule {
        case .none:
            nil
        case .due:
            // Saying "0:00" for however long the request takes would read as
            // stuck.
            style == .glyph ? "Due" : "Refreshing shortly"
        case let .waiting(clock):
            style == .glyph ? clock : "Refreshes in \(clock)"
        }
    }

    /// The state of the next refresh.
    ///
    /// A due refresh is distinct from an unscheduled one: the first is about to
    /// produce new data, the second never will.
    private enum Schedule {
        case none
        case due
        case waiting(String)
    }

    private var schedule: Schedule {
        guard let nextRefreshAt else {
            return .none
        }
        let seconds = Int(nextRefreshAt.timeIntervalSince(now).rounded())
        guard seconds > 0 else {
            return .due
        }
        return .waiting(String(format: "%d:%02d", seconds / 60, seconds % 60))
    }

    private var refreshingText: String {
        style == .glyph ? "Refreshing" : "Refreshing now"
    }

    private var accessibilityLabel: String {
        if isRefreshing {
            return "Refreshing usage"
        }
        switch schedule {
        case .none:
            return "No refresh scheduled"
        case .due:
            return "Refresh due"
        case let .waiting(clock):
            return "Next refresh in \(clock)"
        }
    }
}

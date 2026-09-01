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
    let nextRefreshAt: Date?
    let isRefreshing: Bool

    /// Drives the countdown. One timer per visible panel, stopped with the view.
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        Group {
            if isRefreshing {
                Text("Refreshing")
            } else if let remaining {
                Text(remaining)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .onReceive(tick) { now = $0 }
        .accessibilityLabel(accessibilityLabel)
    }

    /// The countdown text, or nil when nothing is scheduled.
    private var remaining: String? {
        guard let nextRefreshAt else {
            return nil
        }
        let seconds = Int(nextRefreshAt.timeIntervalSince(now).rounded())
        guard seconds > 0 else {
            // The refresh is due; saying "0:00" for however long the request
            // takes would read as stuck.
            return "Due"
        }
        let minutes = seconds / 60
        return String(format: "%d:%02d", minutes, seconds % 60)
    }

    private var accessibilityLabel: String {
        if isRefreshing {
            return "Refreshing usage"
        }
        guard let remaining else {
            return "No refresh scheduled"
        }
        return remaining == "Due"
            ? "Refresh due"
            : "Next refresh in \(remaining)"
    }
}

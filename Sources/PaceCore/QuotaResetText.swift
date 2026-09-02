import Foundation

/// Reset-time wording shared by the edge rail and the menu panel.
///
/// Stated as how long is left rather than as a clock time. "Resets in 2d 18h"
/// answers how much room remains before the quota returns, which is the
/// question a usage tool is opened to settle. A clock time makes the reader do
/// that subtraction themselves, and the further out the reset, the more work it
/// is: "Resets Sep 12 5:30 AM" is not a useful answer to "can I keep going".
///
/// The reference states absolute times, so this is a deliberate departure.
public enum QuotaResetText {
    /// Reset wording for a quota that may not report a reset moment.
    public static func description(
        resetsAt: Date?,
        relativeTo referenceDate: Date,
        calendar: Calendar = .current,
    ) -> String {
        guard let resetsAt else {
            return "Reset unavailable"
        }
        return "Resets \(moment(resetsAt, relativeTo: referenceDate, calendar: calendar))"
    }

    /// The remaining time, without the "Resets" prefix.
    ///
    /// Two units at most, and never a unit smaller than the one below the
    /// largest: days and hours, or hours and minutes. A reset four days away
    /// does not need its minutes, and showing them would imply a precision the
    /// provider's own window does not have.
    public static func moment(
        _ resetsAt: Date,
        relativeTo referenceDate: Date,
        calendar _: Calendar = .current,
    ) -> String {
        let remaining = resetsAt.timeIntervalSince(referenceDate)
        guard remaining > 0 else {
            // The window has closed but the provider has not reported the new
            // one yet. Saying "in 0m" would read as broken.
            return "shortly"
        }

        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "in \(days)d \(hours)h" : "in \(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "in \(hours)h \(minutes)m" : "in \(hours)h"
        }
        return "in \(max(minutes, 1))m"
    }
}

import Foundation

/// Reset-time wording shared by the edge rail and the menu panel.
///
/// The reference frames and the running reference application both state the
/// absolute reset moment rather than a countdown: "Resets Mon 1:09 AM" and
/// "Resets Wed 11:59 PM". An absolute time stays correct on a surface the user
/// glances at rather than watches, and it does not need to re-render every
/// minute to stay honest.
enum QuotaResetText {
    /// Reset wording for a quota that may not report a reset moment.
    static func description(
        resetsAt: Date?,
        relativeTo referenceDate: Date,
        calendar: Calendar = .current,
    ) -> String {
        guard let resetsAt else {
            return "Reset unavailable"
        }
        return "Resets \(moment(resetsAt, relativeTo: referenceDate, calendar: calendar))"
    }

    /// The reset moment itself, without the "Resets" prefix.
    ///
    /// Today and tomorrow read as a bare time or "Tomorrow", because a weekday
    /// name for a moment hours away is harder to place than either. Anything
    /// further out uses the weekday, and anything beyond a week adds the date
    /// so two resets a week apart never render identically.
    static func moment(
        _ resetsAt: Date,
        relativeTo referenceDate: Date,
        calendar: Calendar = .current,
    ) -> String {
        let time = resetsAt.formatted(date: .omitted, time: .shortened)

        if calendar.isDate(resetsAt, inSameDayAs: referenceDate) {
            return time
        }
        if calendar.isDateInTomorrow(resetsAt) {
            return "Tomorrow \(time)"
        }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: referenceDate),
            to: calendar.startOfDay(for: resetsAt),
        ).day ?? 0

        if days > 0, days < 7 {
            return "\(resetsAt.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }

        let date = resetsAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(date) \(time)"
    }
}

import Foundation
@testable import PaceCore
import Testing

@Suite("Quota reset wording")
struct QuotaResetTextTests {
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    @Test
    func `states hours and minutes for a reset later today`() {
        let resetsAt = now.addingTimeInterval(3 * 3600 + 11 * 60)

        #expect(QuotaResetText.moment(resetsAt, relativeTo: now) == "in 3h 11m")
    }

    @Test
    func `states days and hours for a distant reset`() {
        let resetsAt = now.addingTimeInterval(2 * 86400 + 18 * 3600)

        #expect(QuotaResetText.moment(resetsAt, relativeTo: now) == "in 2d 18h")
    }

    @Test
    func `a passed reset reads as imminent rather than negative`() {
        // The window has closed but the provider has not published the new one.
        let resetsAt = now.addingTimeInterval(-120)

        #expect(QuotaResetText.moment(resetsAt, relativeTo: now) == "shortly")
    }

    @Test
    func `an absent reset is reported as unavailable`() {
        // Not every provider publishes a reset for every bucket, and inventing
        // one would be worse than saying so.
        #expect(
            QuotaResetText.description(resetsAt: nil, relativeTo: now)
                == "Reset unavailable",
        )
    }

    @Test
    func `measuring from a stale reference inflates the remaining time`() {
        // Both surfaces used to measure against the simulated scenario's fixed
        // date instead of the present, so every countdown was overstated by
        // however long ago that date was. A reset three hours out was shown as
        // more than two days away.
        let resetsAt = now.addingTimeInterval(3 * 3600 + 11 * 60)
        let staleReference = now.addingTimeInterval(-(2 * 86400 + 9 * 3600))

        #expect(QuotaResetText.moment(resetsAt, relativeTo: now) == "in 3h 11m")
        #expect(QuotaResetText.moment(resetsAt, relativeTo: staleReference) == "in 2d 12h")
    }
}

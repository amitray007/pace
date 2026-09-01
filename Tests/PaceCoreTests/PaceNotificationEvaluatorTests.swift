import Foundation
@testable import PaceCore
import Testing

@Suite("Notification evaluation")
struct PaceNotificationEvaluatorTests {
    @Test
    func `default policy never produces a notification`() throws {
        let state = try state(usedFractions: [TestSupport.personalID: 0.95])

        let candidates = try PaceNotificationEvaluator.evaluate(
            previous: state,
            current: state,
            policy: PaceNotificationPolicy(),
            now: TestSupport.referenceDate,
        )

        #expect(candidates.isEmpty)
    }

    @Test
    func `usage threshold crosses independently for each account`() throws {
        let previous = try state(
            usedFractions: [
                TestSupport.personalID: 0.79,
                TestSupport.workID: 0.92,
            ],
        )
        let current = try state(
            usedFractions: [
                TestSupport.personalID: 0.81,
                TestSupport.workID: 0.96,
            ],
        )
        let policy = try PaceNotificationPolicy(usageThreshold: 0.8)

        let candidates = PaceNotificationEvaluator.evaluate(
            previous: previous,
            current: current,
            policy: policy,
            now: TestSupport.referenceDate,
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.accountID == TestSupport.personalID)
        guard case let .usageThreshold(_, usedFraction, threshold) = candidates.first?.event else {
            Issue.record("Expected a usage-threshold candidate")
            return
        }
        #expect(usedFraction == 0.81)
        #expect(threshold == 0.8)
    }

    @Test
    func `initial or stale snapshots do not invent a threshold crossing`() throws {
        let currentSnapshot = try snapshot(
            accountID: TestSupport.personalID,
            usedFraction: 0.9,
            observedAt: TestSupport.referenceDate,
            freshness: .stale,
        )
        let current = state(
            accounts: [account(id: TestSupport.personalID, name: "Personal")],
            snapshots: [currentSnapshot],
        )
        let policy = try PaceNotificationPolicy(usageThreshold: 0.8)

        let candidates = PaceNotificationEvaluator.evaluate(
            previous: PaceState(),
            current: current,
            policy: policy,
            now: TestSupport.referenceDate,
        )

        #expect(candidates.isEmpty)
    }

    @Test
    func `disabled accounts do not produce candidates`() throws {
        let previous = try state(usedFractions: [TestSupport.personalID: 0.79])
        var disabledAccount = try #require(previous.accounts.first)
        disabledAccount.isEnabled = false
        let current = try state(
            accounts: [disabledAccount],
            snapshots: [
                snapshot(accountID: disabledAccount.id, usedFraction: 0.95),
            ],
        )
        let policy = try PaceNotificationPolicy(
            usageThreshold: 0.8,
            warnsWhenDataBecomesStale: true,
        )

        let candidates = PaceNotificationEvaluator.evaluate(
            previous: previous,
            current: current,
            policy: policy,
            now: TestSupport.referenceDate,
        )

        #expect(candidates.isEmpty)
    }

    @Test
    func `stale transition produces one account event for several buckets`() throws {
        let personal = account(id: TestSupport.personalID, name: "Personal")
        let previous = try state(
            accounts: [personal],
            snapshots: [
                snapshot(accountID: personal.id, bucketID: "session", usedFraction: 0.4),
                snapshot(accountID: personal.id, bucketID: "weekly", usedFraction: 0.6),
            ],
        )
        let current = try state(
            accounts: [personal],
            snapshots: [
                snapshot(
                    accountID: personal.id,
                    bucketID: "session",
                    usedFraction: 0.4,
                    freshness: .stale,
                ),
                snapshot(
                    accountID: personal.id,
                    bucketID: "weekly",
                    usedFraction: 0.6,
                    freshness: .stale,
                ),
            ],
        )
        let policy = try PaceNotificationPolicy(warnsWhenDataBecomesStale: true)

        let candidates = PaceNotificationEvaluator.evaluate(
            previous: previous,
            current: current,
            policy: policy,
            now: TestSupport.referenceDate,
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.event == .staleData)
    }

    @Test
    func `reset reminder fires only when the same reset enters the lead window`() throws {
        let now = TestSupport.referenceDate
        let resetDate = now.addingTimeInterval(30 * 60)
        let previous = try state(
            accounts: [account(id: TestSupport.personalID, name: "Personal")],
            snapshots: [
                snapshot(
                    accountID: TestSupport.personalID,
                    usedFraction: 0.5,
                    resetsAt: resetDate,
                    observedAt: now.addingTimeInterval(-2 * 60 * 60),
                ),
            ],
        )
        let current = try state(
            accounts: previous.accounts,
            snapshots: [
                snapshot(
                    accountID: TestSupport.personalID,
                    usedFraction: 0.6,
                    resetsAt: resetDate,
                    observedAt: now,
                ),
            ],
        )
        let policy = try PaceNotificationPolicy(resetReminderLeadTime: 60 * 60)

        let candidates = PaceNotificationEvaluator.evaluate(
            previous: previous,
            current: current,
            policy: policy,
            now: now,
        )

        #expect(candidates.count == 1)
        guard case let .resetReminder(_, candidateResetDate) = candidates.first?.event else {
            Issue.record("Expected a reset-reminder candidate")
            return
        }
        #expect(candidateResetDate == resetDate)
    }

    @Test
    func `new provider reset cycle does not invent a reminder transition`() throws {
        let now = TestSupport.referenceDate
        let previous = try state(
            accounts: [account(id: TestSupport.personalID, name: "Personal")],
            snapshots: [
                snapshot(
                    accountID: TestSupport.personalID,
                    usedFraction: 0.5,
                    resetsAt: now.addingTimeInterval(2 * 60 * 60),
                    observedAt: now.addingTimeInterval(-2 * 60 * 60),
                ),
            ],
        )
        let current = try state(
            accounts: previous.accounts,
            snapshots: [
                snapshot(
                    accountID: TestSupport.personalID,
                    usedFraction: 0.1,
                    resetsAt: now.addingTimeInterval(30 * 60),
                    observedAt: now,
                ),
            ],
        )
        let policy = try PaceNotificationPolicy(resetReminderLeadTime: 60 * 60)

        let candidates = PaceNotificationEvaluator.evaluate(
            previous: previous,
            current: current,
            policy: policy,
            now: now,
        )

        #expect(candidates.isEmpty)
    }

    @Test
    func `quiet hours hold a crossing until the next local end time`() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let quietHours = try NotificationQuietHours(
            startMinutesAfterMidnight: 22 * 60,
            endMinutesAfterMidnight: 7 * 60,
            timeZone: timeZone,
        )
        let policy = try PaceNotificationPolicy(
            usageThreshold: 0.8,
            quietHours: quietHours,
        )
        let calendar = try utcCalendar()
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 23, minute: 30)),
        )
        let expectedDelivery = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 7)),
        )
        let previous = try state(usedFractions: [TestSupport.personalID: 0.79])
        let current = try state(usedFractions: [TestSupport.personalID: 0.81])

        let candidates = PaceNotificationEvaluator.evaluate(
            previous: previous,
            current: current,
            policy: policy,
            now: now,
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.notBefore == expectedDelivery)
    }

    @Test
    func `quiet hours do not delay daytime delivery`() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let quietHours = try NotificationQuietHours(
            startMinutesAfterMidnight: 22 * 60,
            endMinutesAfterMidnight: 7 * 60,
            timeZone: timeZone,
        )
        let calendar = try utcCalendar()
        let daytime = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 14)),
        )

        #expect(quietHours.deliveryDate(for: daytime) == nil)
    }

    @Test
    func `rejects invalid notification policy values`() throws {
        #expect(throws: PaceNotificationPolicyError.invalidUsageThreshold(1.1)) {
            try PaceNotificationPolicy(usageThreshold: 1.1)
        }
        #expect(throws: PaceNotificationPolicyError.invalidUsageThreshold(0)) {
            try PaceNotificationPolicy(usageThreshold: 0)
        }
        #expect(throws: PaceNotificationPolicyError.invalidResetReminderLeadTime(0)) {
            try PaceNotificationPolicy(resetReminderLeadTime: 0)
        }
        #expect(throws: NotificationQuietHoursError.identicalStartAndEnd) {
            try NotificationQuietHours(
                startMinutesAfterMidnight: 60,
                endMinutesAfterMidnight: 60,
                timeZone: #require(TimeZone(secondsFromGMT: 0)),
            )
        }
        #expect(throws: NotificationQuietHoursError.invalidMinute(24 * 60)) {
            try NotificationQuietHours(
                startMinutesAfterMidnight: 0,
                endMinutesAfterMidnight: 24 * 60,
                timeZone: #require(TimeZone(secondsFromGMT: 0)),
            )
        }
    }
}

private extension PaceNotificationEvaluatorTests {
    func state(usedFractions: [AccountID: Double]) throws -> PaceState {
        let accounts = usedFractions.keys.sorted().enumerated().map { index, accountID in
            account(id: accountID, name: index == 0 ? "Personal" : "Work", order: index)
        }
        let snapshots = try accounts.map { account in
            try snapshot(
                accountID: account.id,
                usedFraction: usedFractions[account.id] ?? 0,
            )
        }
        return state(accounts: accounts, snapshots: snapshots)
    }

    func state(
        accounts: [ProviderAccount],
        snapshots: [LimitSnapshot],
    ) -> PaceState {
        PaceState(accounts: accounts, snapshots: snapshots)
    }

    func account(
        id: AccountID,
        name: String,
        order: Int = 0,
    ) -> ProviderAccount {
        ProviderAccount(
            id: id,
            providerID: .claude,
            identity: ProviderIdentity(subjectID: name.lowercased()),
            credentialBinding: .simulated,
            addedAt: TestSupport.referenceDate,
            displayName: name,
            planName: "Claude Pro",
            isEnabled: true,
            order: order,
            connectionState: .connected(lastVerifiedAt: TestSupport.referenceDate),
        )
    }

    func snapshot(
        accountID: AccountID,
        bucketID: String = "weekly",
        usedFraction: Double,
        resetsAt: Date? = TestSupport.referenceDate.addingTimeInterval(24 * 60 * 60),
        observedAt: Date = TestSupport.referenceDate,
        freshness: Freshness = .current,
    ) throws -> LimitSnapshot {
        try LimitSnapshot(
            providerID: .claude,
            accountID: accountID,
            bucketID: BucketID(rawValue: bucketID),
            label: bucketID.capitalized,
            usedFraction: usedFraction,
            windowDuration: 7 * 24 * 60 * 60,
            resetsAt: resetsAt,
            observedAt: observedAt,
            freshness: freshness,
        )
    }

    func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }
}

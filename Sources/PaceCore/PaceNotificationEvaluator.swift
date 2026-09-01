import Foundation

public enum PaceNotificationPolicyError: Error, Equatable, Sendable {
    case invalidResetReminderLeadTime(TimeInterval)
    case invalidUsageThreshold(Double)
}

public enum NotificationQuietHoursError: Error, Equatable, Sendable {
    case identicalStartAndEnd
    case invalidMinute(Int)
}

public struct NotificationQuietHours: Equatable, Sendable {
    public let startMinutesAfterMidnight: Int
    public let endMinutesAfterMidnight: Int
    public let timeZone: TimeZone

    public init(
        startMinutesAfterMidnight: Int,
        endMinutesAfterMidnight: Int,
        timeZone: TimeZone,
    ) throws {
        guard (0 ..< 24 * 60).contains(startMinutesAfterMidnight) else {
            throw NotificationQuietHoursError.invalidMinute(startMinutesAfterMidnight)
        }
        guard (0 ..< 24 * 60).contains(endMinutesAfterMidnight) else {
            throw NotificationQuietHoursError.invalidMinute(endMinutesAfterMidnight)
        }
        guard startMinutesAfterMidnight != endMinutesAfterMidnight else {
            throw NotificationQuietHoursError.identicalStartAndEnd
        }

        self.startMinutesAfterMidnight = startMinutesAfterMidnight
        self.endMinutesAfterMidnight = endMinutesAfterMidnight
        self.timeZone = timeZone
    }

    public func deliveryDate(for date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }

        let minutesAfterMidnight = hour * 60 + minute
        let crossesMidnight = startMinutesAfterMidnight > endMinutesAfterMidnight
        let isQuiet = crossesMidnight
            ? minutesAfterMidnight >= startMinutesAfterMidnight
            || minutesAfterMidnight < endMinutesAfterMidnight
            : minutesAfterMidnight >= startMinutesAfterMidnight
            && minutesAfterMidnight < endMinutesAfterMidnight
        guard isQuiet else {
            return nil
        }

        var deliveryDay = calendar.startOfDay(for: date)
        if crossesMidnight, minutesAfterMidnight >= startMinutesAfterMidnight {
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: deliveryDay) {
                deliveryDay = nextDay
            }
        }
        return calendar.date(
            bySettingHour: endMinutesAfterMidnight / 60,
            minute: endMinutesAfterMidnight % 60,
            second: 0,
            of: deliveryDay,
        )
    }
}

public struct PaceNotificationPolicy: Equatable, Sendable {
    public let usageThreshold: Double?
    public let resetReminderLeadTime: TimeInterval?
    public let warnsWhenDataBecomesStale: Bool
    public let quietHours: NotificationQuietHours?

    public init(
        usageThreshold: Double? = nil,
        resetReminderLeadTime: TimeInterval? = nil,
        warnsWhenDataBecomesStale: Bool = false,
        quietHours: NotificationQuietHours? = nil,
    ) throws {
        if let usageThreshold {
            if !usageThreshold.isFinite || usageThreshold <= 0 || usageThreshold > 1 {
                throw PaceNotificationPolicyError.invalidUsageThreshold(usageThreshold)
            }
        }
        if let resetReminderLeadTime {
            if !resetReminderLeadTime.isFinite || resetReminderLeadTime <= 0 {
                throw PaceNotificationPolicyError.invalidResetReminderLeadTime(
                    resetReminderLeadTime,
                )
            }
        }

        self.usageThreshold = usageThreshold
        self.resetReminderLeadTime = resetReminderLeadTime
        self.warnsWhenDataBecomesStale = warnsWhenDataBecomesStale
        self.quietHours = quietHours
    }

    public var isEnabled: Bool {
        usageThreshold != nil || resetReminderLeadTime != nil || warnsWhenDataBecomesStale
    }
}

public enum PaceNotificationEvent: Equatable, Sendable {
    case resetReminder(LimitSnapshot.ID, resetsAt: Date)
    case staleData
    case usageThreshold(LimitSnapshot.ID, usedFraction: Double, threshold: Double)
}

public struct PaceNotificationCandidate: Equatable, Sendable {
    public let providerID: ProviderID
    public let accountID: AccountID
    public let accountDisplayName: String
    public let bucketLabel: String?
    public let event: PaceNotificationEvent
    public let notBefore: Date?

    public init(
        providerID: ProviderID,
        accountID: AccountID,
        accountDisplayName: String,
        bucketLabel: String?,
        event: PaceNotificationEvent,
        notBefore: Date?,
    ) {
        self.providerID = providerID
        self.accountID = accountID
        self.accountDisplayName = accountDisplayName
        self.bucketLabel = bucketLabel
        self.event = event
        self.notBefore = notBefore
    }
}

public enum PaceNotificationEvaluator {
    private struct EvaluationContext {
        let previousAccounts: [AccountID: ProviderAccount]
        let previousSnapshots: [LimitSnapshot.ID: LimitSnapshot]
        let policy: PaceNotificationPolicy
        let now: Date
        let notBefore: Date?
    }

    public static func evaluate(
        previous: PaceState,
        current: PaceState,
        policy: PaceNotificationPolicy,
        now: Date,
    ) -> [PaceNotificationCandidate] {
        guard policy.isEnabled else {
            return []
        }

        let context = EvaluationContext(
            previousAccounts: accountsByID(previous.accounts),
            previousSnapshots: snapshotsByID(previous.snapshots),
            policy: policy,
            now: now,
            notBefore: policy.quietHours?.deliveryDate(for: now),
        )
        let currentSnapshots = snapshotsByID(current.snapshots)
        return orderedEnabledAccounts(current.accounts).flatMap { account in
            let accountSnapshots = orderedSnapshots(
                currentSnapshots.values.filter { $0.id.accountID == account.id },
            )
            return candidates(
                for: account,
                snapshots: accountSnapshots,
                context: context,
            )
        }
    }

    private static func candidates(
        for account: ProviderAccount,
        snapshots: [LimitSnapshot],
        context: EvaluationContext,
    ) -> [PaceNotificationCandidate] {
        var result: [PaceNotificationCandidate] = []
        if shouldWarnAboutStaleData(
            account: account,
            snapshots: snapshots,
            previousAccount: context.previousAccounts[account.id],
            previousSnapshots: context.previousSnapshots.values.filter {
                $0.id.accountID == account.id
            },
            policy: context.policy,
        ) {
            result.append(
                candidate(
                    account: account,
                    bucketLabel: nil,
                    event: .staleData,
                    notBefore: context.notBefore,
                ),
            )
        }
        for snapshot in snapshots where snapshotCanNotify(snapshot) {
            guard let previousSnapshot = context.previousSnapshots[snapshot.id] else {
                continue
            }
            result.append(contentsOf: candidates(
                for: snapshot,
                previous: previousSnapshot,
                account: account,
                context: context,
            ))
        }
        return result
    }

    private static func candidates(
        for snapshot: LimitSnapshot,
        previous: LimitSnapshot,
        account: ProviderAccount,
        context: EvaluationContext,
    ) -> [PaceNotificationCandidate] {
        var candidates: [PaceNotificationCandidate] = []
        if let threshold = context.policy.usageThreshold {
            if previous.usedFraction < threshold, snapshot.usedFraction >= threshold {
                candidates.append(candidate(
                    account: account,
                    bucketLabel: snapshot.label,
                    event: .usageThreshold(
                        snapshot.id,
                        usedFraction: snapshot.usedFraction,
                        threshold: threshold,
                    ),
                    notBefore: context.notBefore,
                ))
            }
        }
        if let leadTime = context.policy.resetReminderLeadTime {
            if let resetsAt = snapshot.resetsAt {
                if resetEnteredLeadWindow(
                    previous: previous,
                    current: snapshot,
                    leadTime: leadTime,
                    now: context.now,
                ) {
                    candidates.append(candidate(
                        account: account,
                        bucketLabel: snapshot.label,
                        event: .resetReminder(snapshot.id, resetsAt: resetsAt),
                        notBefore: context.notBefore,
                    ))
                }
            }
        }
        return candidates
    }

    private static func accountsByID(
        _ accounts: [ProviderAccount],
    ) -> [AccountID: ProviderAccount] {
        accounts.reduce(into: [:]) { result, account in
            result[account.id] = account
        }
    }

    private static func snapshotsByID(
        _ snapshots: [LimitSnapshot],
    ) -> [LimitSnapshot.ID: LimitSnapshot] {
        snapshots.reduce(into: [:]) { result, snapshot in
            guard let existing = result[snapshot.id],
                  existing.observedAt >= snapshot.observedAt
            else {
                result[snapshot.id] = snapshot
                return
            }
        }
    }

    private static func orderedEnabledAccounts(
        _ accounts: [ProviderAccount],
    ) -> [ProviderAccount] {
        accounts.filter(\.isEnabled).sorted { lhs, rhs in
            if lhs.providerID != rhs.providerID {
                return lhs.providerID < rhs.providerID
            }
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        }
    }

    private static func orderedSnapshots(
        _ snapshots: some Sequence<LimitSnapshot>,
    ) -> [LimitSnapshot] {
        snapshots.sorted { lhs, rhs in
            if lhs.id.bucketID.rawValue != rhs.id.bucketID.rawValue {
                return lhs.id.bucketID.rawValue < rhs.id.bucketID.rawValue
            }
            return (lhs.id.quotaSubjectID?.rawValue ?? "")
                < (rhs.id.quotaSubjectID?.rawValue ?? "")
        }
    }

    private static func snapshotCanNotify(_ snapshot: LimitSnapshot) -> Bool {
        snapshot.freshness == .current || snapshot.freshness == .aging
    }

    private static func shouldWarnAboutStaleData(
        account: ProviderAccount,
        snapshots: [LimitSnapshot],
        previousAccount: ProviderAccount?,
        previousSnapshots: some Sequence<LimitSnapshot>,
        policy: PaceNotificationPolicy,
    ) -> Bool {
        guard policy.warnsWhenDataBecomesStale,
              let previousAccount,
              previousAccount.isEnabled
        else {
            return false
        }
        let currentStatus = AccountUsageStatus(account: account, snapshots: snapshots)
        let previousStatus = AccountUsageStatus(
            account: previousAccount,
            snapshots: Array(previousSnapshots),
        )
        return currentStatus.dataFreshness == .stale
            && previousStatus.dataFreshness != .stale
    }

    private static func resetEnteredLeadWindow(
        previous: LimitSnapshot,
        current: LimitSnapshot,
        leadTime: TimeInterval,
        now: Date,
    ) -> Bool {
        guard let resetsAt = current.resetsAt,
              previous.resetsAt == resetsAt
        else {
            return false
        }
        let previousRemaining = resetsAt.timeIntervalSince(previous.observedAt)
        let currentRemaining = resetsAt.timeIntervalSince(now)
        return previousRemaining > leadTime
            && currentRemaining > 0
            && currentRemaining <= leadTime
    }

    private static func candidate(
        account: ProviderAccount,
        bucketLabel: String?,
        event: PaceNotificationEvent,
        notBefore: Date?,
    ) -> PaceNotificationCandidate {
        PaceNotificationCandidate(
            providerID: account.providerID,
            accountID: account.id,
            accountDisplayName: account.displayName,
            bucketLabel: bucketLabel,
            event: event,
            notBefore: notBefore,
        )
    }
}

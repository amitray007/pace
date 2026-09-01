import Foundation
import PaceCore

extension PacePresentationModel {
    static let defaultNotificationResetLeadTime: TimeInterval = 60 * 60
    static let defaultNotificationUsageThreshold = 0.8
    static let defaultQuietHoursEnd = 8 * 60
    static let defaultQuietHoursStart = 22 * 60

    var notificationPolicy: PaceNotificationPolicy {
        preferences.notificationPolicy
    }

    var usageNotificationsEnabled: Bool {
        notificationPolicy.usageThreshold != nil
    }

    var notificationUsageThreshold: Double {
        notificationPolicy.usageThreshold ?? Self.defaultNotificationUsageThreshold
    }

    var resetNotificationsEnabled: Bool {
        notificationPolicy.resetReminderLeadTime != nil
    }

    var notificationResetLeadTime: TimeInterval {
        notificationPolicy.resetReminderLeadTime ?? Self.defaultNotificationResetLeadTime
    }

    var staleDataNotificationsEnabled: Bool {
        notificationPolicy.warnsWhenDataBecomesStale
    }

    var quietHoursEnabled: Bool {
        notificationPolicy.quietHours != nil
    }

    var quietHoursStartDate: Date {
        dateForNotificationTime(
            notificationPolicy.quietHours?.startMinutesAfterMidnight
                ?? Self.defaultQuietHoursStart,
        )
    }

    var quietHoursEndDate: Date {
        dateForNotificationTime(
            notificationPolicy.quietHours?.endMinutesAfterMidnight
                ?? Self.defaultQuietHoursEnd,
        )
    }

    func refreshNotificationAuthorizationStatus() async {
        guard !isReferencePreview else {
            return
        }
        notificationAuthorizationStatus = await notificationDeliveryController
            .authorizationStatus()
    }

    func requestNotificationAuthorization() {
        guard notificationPolicy.isEnabled else {
            return
        }
        scheduleNotificationPolicyChange(requestsAuthorization: true)
    }

    func setUsageNotificationsEnabled(_ isEnabled: Bool) {
        replaceNotificationPolicy(
            usageThreshold: isEnabled ? notificationUsageThreshold : nil,
            resetReminderLeadTime: notificationPolicy.resetReminderLeadTime,
            warnsWhenDataBecomesStale: notificationPolicy.warnsWhenDataBecomesStale,
            quietHours: notificationPolicy.quietHours,
            requestsAuthorization: isEnabled,
        )
    }

    func setNotificationUsageThreshold(_ threshold: Double) {
        replaceNotificationPolicy(
            usageThreshold: threshold,
            resetReminderLeadTime: notificationPolicy.resetReminderLeadTime,
            warnsWhenDataBecomesStale: notificationPolicy.warnsWhenDataBecomesStale,
            quietHours: notificationPolicy.quietHours,
            requestsAuthorization: true,
        )
    }

    func setResetNotificationsEnabled(_ isEnabled: Bool) {
        replaceNotificationPolicy(
            usageThreshold: notificationPolicy.usageThreshold,
            resetReminderLeadTime: isEnabled ? notificationResetLeadTime : nil,
            warnsWhenDataBecomesStale: notificationPolicy.warnsWhenDataBecomesStale,
            quietHours: notificationPolicy.quietHours,
            requestsAuthorization: isEnabled,
        )
    }

    func setNotificationResetLeadTime(_ leadTime: TimeInterval) {
        replaceNotificationPolicy(
            usageThreshold: notificationPolicy.usageThreshold,
            resetReminderLeadTime: leadTime,
            warnsWhenDataBecomesStale: notificationPolicy.warnsWhenDataBecomesStale,
            quietHours: notificationPolicy.quietHours,
            requestsAuthorization: true,
        )
    }

    func setStaleDataNotificationsEnabled(_ isEnabled: Bool) {
        replaceNotificationPolicy(
            usageThreshold: notificationPolicy.usageThreshold,
            resetReminderLeadTime: notificationPolicy.resetReminderLeadTime,
            warnsWhenDataBecomesStale: isEnabled,
            quietHours: notificationPolicy.quietHours,
            requestsAuthorization: isEnabled,
        )
    }

    func setQuietHoursEnabled(_ isEnabled: Bool) {
        let quietHours: NotificationQuietHours? = if isEnabled {
            try? NotificationQuietHours(
                startMinutesAfterMidnight: Self.defaultQuietHoursStart,
                endMinutesAfterMidnight: Self.defaultQuietHoursEnd,
                timeZone: .autoupdatingCurrent,
            )
        } else {
            nil
        }
        replaceNotificationPolicy(
            usageThreshold: notificationPolicy.usageThreshold,
            resetReminderLeadTime: notificationPolicy.resetReminderLeadTime,
            warnsWhenDataBecomesStale: notificationPolicy.warnsWhenDataBecomesStale,
            quietHours: quietHours,
            requestsAuthorization: false,
        )
    }

    func setQuietHoursStartDate(_ date: Date) {
        replaceQuietHours(
            startMinutesAfterMidnight: minutesAfterMidnight(date),
            endMinutesAfterMidnight: notificationPolicy.quietHours?.endMinutesAfterMidnight
                ?? Self.defaultQuietHoursEnd,
        )
    }

    func setQuietHoursEndDate(_ date: Date) {
        replaceQuietHours(
            startMinutesAfterMidnight: notificationPolicy.quietHours?.startMinutesAfterMidnight
                ?? Self.defaultQuietHoursStart,
            endMinutesAfterMidnight: minutesAfterMidnight(date),
        )
    }

    func deliverNotifications(previous: PaceState, current: PaceState) async {
        let policy = notificationPolicy
        guard policy.isEnabled else {
            return
        }
        do {
            _ = try await notificationDeliveryController.deliver(
                previous: previous,
                current: current,
                policy: policy,
                now: Date(),
            )
            notificationError = nil
        } catch {
            notificationError = "Pace could not schedule a notification."
        }
    }

    private func replaceQuietHours(
        startMinutesAfterMidnight: Int,
        endMinutesAfterMidnight: Int,
    ) {
        do {
            let quietHours = try NotificationQuietHours(
                startMinutesAfterMidnight: startMinutesAfterMidnight,
                endMinutesAfterMidnight: endMinutesAfterMidnight,
                timeZone: .autoupdatingCurrent,
            )
            replaceNotificationPolicy(
                usageThreshold: notificationPolicy.usageThreshold,
                resetReminderLeadTime: notificationPolicy.resetReminderLeadTime,
                warnsWhenDataBecomesStale: notificationPolicy.warnsWhenDataBecomesStale,
                quietHours: quietHours,
                requestsAuthorization: false,
            )
        } catch {
            notificationError = "Quiet hours need different start and end times."
        }
    }

    private func replaceNotificationPolicy(
        usageThreshold: Double?,
        resetReminderLeadTime: TimeInterval?,
        warnsWhenDataBecomesStale: Bool,
        quietHours: NotificationQuietHours?,
        requestsAuthorization: Bool,
    ) {
        do {
            let policy = try PaceNotificationPolicy(
                usageThreshold: usageThreshold,
                resetReminderLeadTime: resetReminderLeadTime,
                warnsWhenDataBecomesStale: warnsWhenDataBecomesStale,
                quietHours: quietHours,
            )
            updatePreferences { $0.notificationPolicy = policy }
            notificationError = nil
            scheduleNotificationPolicyChange(
                requestsAuthorization: requestsAuthorization && policy.isEnabled,
            )
        } catch {
            notificationError = "The notification settings are invalid."
        }
    }

    private func scheduleNotificationPolicyChange(requestsAuthorization: Bool) {
        guard !isReferencePreview else {
            return
        }
        notificationSettingsTask?.cancel()
        notificationSettingsTask = Task { [weak self] in
            guard let self else {
                return
            }
            await notificationDeliveryController.removePending()
            guard requestsAuthorization, !Task.isCancelled else {
                return
            }
            isChangingNotificationAuthorization = true
            defer { isChangingNotificationAuthorization = false }
            do {
                notificationAuthorizationStatus = try await notificationDeliveryController
                    .requestAuthorizationIfNeeded()
                notificationError = nil
            } catch {
                notificationAuthorizationStatus = await notificationDeliveryController
                    .authorizationStatus()
                notificationError = "Pace could not request notification permission."
            }
        }
    }

    private func dateForNotificationTime(_ minutesAfterMidnight: Int) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        return calendar.date(
            bySettingHour: minutesAfterMidnight / 60,
            minute: minutesAfterMidnight % 60,
            second: 0,
            of: Date(),
        ) ?? Date()
    }

    private func minutesAfterMidnight(_ date: Date) -> Int {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

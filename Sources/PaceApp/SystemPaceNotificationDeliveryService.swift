import Foundation
import PaceCore
import UserNotifications

final class SystemPaceNotificationDeliveryService: PaceNotificationDeliveryService {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> PaceNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        return Self.status(settings.authorizationStatus)
    }

    func requestAuthorization() async throws -> PaceNotificationAuthorizationStatus {
        _ = try await center.requestAuthorization(options: [.alert])
        return await authorizationStatus()
    }

    func deliver(_ message: PaceNotificationMessage) async throws {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.threadIdentifier = message.threadIdentifier

        let trigger = message.notBefore.flatMap { deliveryDate -> UNNotificationTrigger? in
            let delay = deliveryDate.timeIntervalSinceNow
            guard delay > 1 else {
                return nil
            }
            return UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger,
        )
        try await center.add(request)
    }

    func removePending() async {
        center.removeAllPendingNotificationRequests()
    }

    private static func status(
        _ status: UNAuthorizationStatus,
    ) -> PaceNotificationAuthorizationStatus {
        switch status {
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .ephemeral:
            .ephemeral
        case .notDetermined:
            .notDetermined
        case .provisional:
            .provisional
        @unknown default:
            .unavailable
        }
    }
}

extension SystemPaceNotificationDeliveryService: @unchecked Sendable {}

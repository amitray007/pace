import Foundation
@testable import PaceCore
import Testing

@Suite("Notification delivery")
struct PaceNotificationDeliveryTests {
    @Test
    func `status checks never request permission`() async {
        let service = StubNotificationDeliveryService(status: .notDetermined)
        let controller = PaceNotificationDeliveryController(service: service)

        #expect(await controller.authorizationStatus() == .notDetermined)
        #expect(await service.requestCount == 0)
    }

    @Test
    func `permission is requested only while status is undetermined`() async throws {
        let service = StubNotificationDeliveryService(
            status: .notDetermined,
            requestedStatus: .authorized,
        )
        let controller = PaceNotificationDeliveryController(service: service)

        #expect(try await controller.requestAuthorizationIfNeeded() == .authorized)
        #expect(try await controller.requestAuthorizationIfNeeded() == .authorized)
        #expect(await service.requestCount == 1)
    }

    @Test
    func `denied authorization prevents native delivery`() async throws {
        let service = StubNotificationDeliveryService(status: .denied)
        let controller = PaceNotificationDeliveryController(service: service)

        let deliveredCount = try await controller.deliver([usageCandidate()])

        #expect(deliveredCount == 0)
        #expect(await service.messages.isEmpty)
    }

    @Test
    func `authorized delivery preserves order content and quiet hour date`() async throws {
        let service = StubNotificationDeliveryService(status: .authorized)
        let controller = PaceNotificationDeliveryController(service: service)
        let notBefore = TestSupport.referenceDate.addingTimeInterval(8 * 60 * 60)
        let usage = try usageCandidate(notBefore: notBefore)
        let stale = staleCandidate()

        let deliveredCount = try await controller.deliver([usage, stale])
        let messages = await service.messages

        #expect(deliveredCount == 2)
        #expect(messages.count == 2)
        #expect(messages[0].title == "Claude · Personal")
        #expect(messages[0].body == "Weekly reached 84% used (alert at 80%).")
        #expect(messages[0].notBefore == notBefore)
        #expect(messages[0].threadIdentifier == "claude")
        #expect(messages[1].body.contains("last known values may be outdated"))
    }

    @Test
    func `state delivery evaluates a real threshold crossing`() async throws {
        let service = StubNotificationDeliveryService(status: .authorized)
        let controller = PaceNotificationDeliveryController(service: service)
        let policy = try PaceNotificationPolicy(usageThreshold: 0.8)
        let account = ProviderAccount(
            id: TestSupport.personalID,
            providerID: .claude,
            identity: ProviderIdentity(subjectID: "personal"),
            credentialBinding: .simulated,
            addedAt: TestSupport.referenceDate,
            displayName: "Personal",
            planName: "Pro",
            isEnabled: true,
            order: 0,
            connectionState: .connected(lastVerifiedAt: TestSupport.referenceDate),
        )
        let previous = try PaceState(
            accounts: [account],
            snapshots: [
                TestSupport.snapshot(
                    accountID: account.id,
                    usedFraction: 0.79,
                ),
            ],
        )
        let current = try PaceState(
            accounts: [account],
            snapshots: [
                TestSupport.snapshot(
                    accountID: account.id,
                    usedFraction: 0.81,
                ),
            ],
        )

        let deliveredCount = try await controller.deliver(
            previous: previous,
            current: current,
            policy: policy,
            now: TestSupport.referenceDate,
        )

        #expect(deliveredCount == 1)
        #expect(await service.messages.first?.body == "Weekly reached 81% used (alert at 80%).")
    }

    @Test
    func `policy changes remove pending deliveries`() async {
        let service = StubNotificationDeliveryService(status: .authorized)
        let controller = PaceNotificationDeliveryController(service: service)

        await controller.removePending()

        #expect(await service.removePendingCount == 1)
    }

    private func usageCandidate(
        notBefore: Date? = nil,
    ) throws -> PaceNotificationCandidate {
        let snapshot = try TestSupport.snapshot(
            accountID: TestSupport.personalID,
            usedFraction: 0.84,
        )
        return PaceNotificationCandidate(
            providerID: .claude,
            accountID: TestSupport.personalID,
            accountDisplayName: "Personal",
            bucketLabel: "Weekly",
            event: .usageThreshold(snapshot.id, usedFraction: 0.84, threshold: 0.8),
            notBefore: notBefore,
        )
    }

    private func staleCandidate() -> PaceNotificationCandidate {
        PaceNotificationCandidate(
            providerID: .claude,
            accountID: TestSupport.personalID,
            accountDisplayName: "Personal",
            bucketLabel: nil,
            event: .staleData,
            notBefore: nil,
        )
    }
}

private actor StubNotificationDeliveryService: PaceNotificationDeliveryService {
    private(set) var messages: [PaceNotificationMessage] = []
    private(set) var removePendingCount = 0
    private(set) var requestCount = 0
    private var status: PaceNotificationAuthorizationStatus
    private let requestedStatus: PaceNotificationAuthorizationStatus

    init(
        status: PaceNotificationAuthorizationStatus,
        requestedStatus: PaceNotificationAuthorizationStatus = .authorized,
    ) {
        self.status = status
        self.requestedStatus = requestedStatus
    }

    func authorizationStatus() -> PaceNotificationAuthorizationStatus {
        status
    }

    func deliver(_ message: PaceNotificationMessage) {
        messages.append(message)
    }

    func removePending() {
        removePendingCount += 1
        messages.removeAll()
    }

    func requestAuthorization() -> PaceNotificationAuthorizationStatus {
        requestCount += 1
        status = requestedStatus
        return status
    }
}

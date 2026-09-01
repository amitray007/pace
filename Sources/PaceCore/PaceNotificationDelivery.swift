import Foundation

public enum PaceNotificationAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    case ephemeral
    case notDetermined
    case provisional
    case unavailable

    public var allowsDelivery: Bool {
        switch self {
        case .authorized, .ephemeral, .provisional:
            true
        case .denied, .notDetermined, .unavailable:
            false
        }
    }
}

public struct PaceNotificationMessage: Equatable, Sendable {
    public let body: String
    public let notBefore: Date?
    public let threadIdentifier: String
    public let title: String

    public init(
        body: String,
        notBefore: Date?,
        threadIdentifier: String,
        title: String,
    ) {
        self.body = body
        self.notBefore = notBefore
        self.threadIdentifier = threadIdentifier
        self.title = title
    }
}

public protocol PaceNotificationDeliveryService: Sendable {
    func authorizationStatus() async -> PaceNotificationAuthorizationStatus
    func deliver(_ message: PaceNotificationMessage) async throws
    func removePending() async
    func requestAuthorization() async throws -> PaceNotificationAuthorizationStatus
}

public actor PaceNotificationDeliveryController {
    private let service: any PaceNotificationDeliveryService

    public init(service: any PaceNotificationDeliveryService) {
        self.service = service
    }

    public func authorizationStatus() async -> PaceNotificationAuthorizationStatus {
        await service.authorizationStatus()
    }

    public func requestAuthorizationIfNeeded() async throws -> PaceNotificationAuthorizationStatus {
        let status = await service.authorizationStatus()
        guard status == .notDetermined else {
            return status
        }
        return try await service.requestAuthorization()
    }

    public func removePending() async {
        await service.removePending()
    }

    @discardableResult
    public func deliver(
        previous: PaceState,
        current: PaceState,
        policy: PaceNotificationPolicy,
        now: Date,
    ) async throws -> Int {
        let candidates = PaceNotificationEvaluator.evaluate(
            previous: previous,
            current: current,
            policy: policy,
            now: now,
        )
        return try await deliver(candidates)
    }

    @discardableResult
    public func deliver(_ candidates: [PaceNotificationCandidate]) async throws -> Int {
        let status = await service.authorizationStatus()
        guard status.allowsDelivery else {
            return 0
        }

        for candidate in candidates {
            try await service.deliver(Self.message(for: candidate))
        }
        return candidates.count
    }

    public static func message(
        for candidate: PaceNotificationCandidate,
    ) -> PaceNotificationMessage {
        let providerName = providerName(candidate.providerID)
        let title = "\(providerName) · \(candidate.accountDisplayName)"
        let body: String
        switch candidate.event {
        case let .resetReminder(_, resetsAt):
            if let bucketLabel = candidate.bucketLabel {
                body =
                    "\(bucketLabel) resets "
                        + "\(resetsAt.formatted(date: .abbreviated, time: .shortened))."
            } else {
                body =
                    "Usage resets "
                        + "\(resetsAt.formatted(date: .abbreviated, time: .shortened))."
            }
        case .staleData:
            body = "Pace could not confirm current usage. The last known values may be outdated."
        case let .usageThreshold(_, usedFraction, threshold):
            let usedPercentage = Int((usedFraction * 100).rounded())
            let thresholdPercentage = Int((threshold * 100).rounded())
            if let bucketLabel = candidate.bucketLabel {
                body =
                    "\(bucketLabel) reached \(usedPercentage)% used "
                        + "(alert at \(thresholdPercentage)%)."
            } else {
                body = "Usage reached \(usedPercentage)% (alert at \(thresholdPercentage)%)."
            }
        }
        return PaceNotificationMessage(
            body: body,
            notBefore: candidate.notBefore,
            threadIdentifier: candidate.providerID.rawValue,
            title: title,
        )
    }

    private static func providerName(_ providerID: ProviderID) -> String {
        switch providerID {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        case .cursor:
            "Cursor"
        case .githubCopilot:
            "GitHub Copilot"
        case .grok:
            "Grok"
        default:
            providerID.rawValue
        }
    }
}

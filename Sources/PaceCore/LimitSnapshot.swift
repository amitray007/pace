import Foundation

public enum QuotaSubjectKind: String, Codable, Sendable {
    case organization
    case personal
    case team
    case unknown
}

public struct QuotaSubject: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: QuotaSubjectID
    public let label: String
    public let kind: QuotaSubjectKind

    public init(id: QuotaSubjectID, label: String, kind: QuotaSubjectKind) {
        self.id = id
        self.label = label
        self.kind = kind
    }
}

public enum Freshness: String, Codable, Sendable {
    case aging
    case current
    case failed
    case signedOut
    case stale
    case unavailable
}

public enum SnapshotValidationError: Error, Equatable, Sendable {
    case invalidUsedFraction(Double)
    case invalidWindowDuration(TimeInterval)
}

public struct LimitSnapshot: Codable, Equatable, Identifiable, Sendable {
    public struct ID: Codable, Equatable, Hashable, Sendable {
        public let providerID: ProviderID
        public let accountID: AccountID
        public let quotaSubjectID: QuotaSubjectID?
        public let bucketID: BucketID

        public init(
            providerID: ProviderID,
            accountID: AccountID,
            quotaSubjectID: QuotaSubjectID?,
            bucketID: BucketID,
        ) {
            self.providerID = providerID
            self.accountID = accountID
            self.quotaSubjectID = quotaSubjectID
            self.bucketID = bucketID
        }
    }

    public let id: ID
    public let label: String
    public let quotaSubject: QuotaSubject?
    public let usedFraction: Double
    public let windowDuration: TimeInterval?
    public let resetsAt: Date?
    public let observedAt: Date
    public var freshness: Freshness

    public var remainingFraction: Double {
        max(0, 1 - usedFraction)
    }

    public init(
        providerID: ProviderID,
        accountID: AccountID,
        bucketID: BucketID,
        label: String,
        quotaSubject: QuotaSubject? = nil,
        usedFraction: Double,
        windowDuration: TimeInterval? = nil,
        resetsAt: Date? = nil,
        observedAt: Date,
        freshness: Freshness,
    ) throws {
        guard usedFraction.isFinite, usedFraction >= 0 else {
            throw SnapshotValidationError.invalidUsedFraction(usedFraction)
        }
        if let windowDuration, !windowDuration.isFinite || windowDuration <= 0 {
            throw SnapshotValidationError.invalidWindowDuration(windowDuration)
        }

        id = ID(
            providerID: providerID,
            accountID: accountID,
            quotaSubjectID: quotaSubject?.id,
            bucketID: bucketID,
        )
        self.label = label
        self.quotaSubject = quotaSubject
        self.usedFraction = usedFraction
        self.windowDuration = windowDuration
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.freshness = freshness
    }
}

public struct ProviderSelection: Codable, Equatable, Sendable {
    public let providerID: ProviderID
    public var accountID: AccountID

    public init(providerID: ProviderID, accountID: AccountID) {
        self.providerID = providerID
        self.accountID = accountID
    }
}

public struct PaceState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var accounts: [ProviderAccount]
    public var snapshots: [LimitSnapshot]
    public var selections: [ProviderSelection]

    public init(
        version: Int = Self.currentVersion,
        accounts: [ProviderAccount] = [],
        snapshots: [LimitSnapshot] = [],
        selections: [ProviderSelection] = [],
    ) {
        self.version = version
        self.accounts = accounts
        self.snapshots = snapshots
        self.selections = selections
    }
}

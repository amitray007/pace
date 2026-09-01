import Foundation
import PaceCore

enum GrokRateLimitNormalizer {
    static func normalize(
        _ result: GrokUsageResult,
        accountID: AccountID,
    ) throws(GrokProviderError) -> [LimitSnapshot] {
        let subject = quotaSubject(for: result.identity)
        var snapshots: [LimitSnapshot] = []
        for metric in result.metrics {
            let values: SnapshotValues
            switch metric {
            case let .percentage(percentage):
                values = SnapshotValues(
                    id: percentage.id,
                    label: percentage.label,
                    usedFraction: percentage.usedFraction,
                    resetsAt: percentage.resetsAt,
                    windowDuration: percentage.windowDuration,
                )
            case let .amount(amount):
                guard let limit = amount.limit, limit > 0 else {
                    continue
                }
                let fraction = NSDecimalNumber(decimal: amount.used / limit).doubleValue
                values = SnapshotValues(
                    id: amount.id,
                    label: amount.label,
                    usedFraction: fraction,
                    resetsAt: amount.resetsAt,
                    windowDuration: nil,
                )
            }
            do {
                try snapshots.append(LimitSnapshot(
                    providerID: .grok,
                    accountID: accountID,
                    bucketID: BucketID(rawValue: values.id),
                    label: values.label,
                    quotaSubject: subject,
                    usedFraction: values.usedFraction,
                    windowDuration: values.windowDuration,
                    resetsAt: values.resetsAt,
                    observedAt: result.observedAt,
                    freshness: .current,
                ))
            } catch {
                throw .invalidResponse
            }
        }
        guard !snapshots.isEmpty else {
            throw .invalidResponse
        }
        return snapshots
    }

    private static func quotaSubject(for identity: GrokIdentity) -> QuotaSubject {
        if let teamID = identity.teamID {
            return QuotaSubject(
                id: QuotaSubjectID(rawValue: "grok-team:\(teamID)"),
                label: "Team",
                kind: .team,
            )
        }
        return QuotaSubject(
            id: QuotaSubjectID(rawValue: "grok-user:\(identity.userID)"),
            label: "Personal",
            kind: .personal,
        )
    }
}

private struct SnapshotValues {
    let id: String
    let label: String
    let usedFraction: Double
    let resetsAt: Date?
    let windowDuration: TimeInterval?
}

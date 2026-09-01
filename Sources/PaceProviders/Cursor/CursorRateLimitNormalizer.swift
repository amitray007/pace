import Foundation
import PaceCore

enum CursorRateLimitNormalizer {
    static func normalize(
        _ result: CursorUsageResult,
        accountID: AccountID,
    ) throws(CursorProviderError) -> [LimitSnapshot] {
        let subject = quotaSubject(for: result.identity)
        var snapshots: [LimitSnapshot] = []
        for metric in result.metrics {
            let values: CursorSnapshotValues
            switch metric {
            case let .percentage(metric):
                values = CursorSnapshotValues(
                    id: metric.id,
                    label: metric.label,
                    usedFraction: metric.usedFraction,
                    windowDuration: metric.windowDuration,
                    resetsAt: metric.resetsAt,
                )
            case let .amount(metric):
                guard let limit = metric.limit, limit > 0 else {
                    continue
                }
                values = CursorSnapshotValues(
                    id: metric.id,
                    label: metric.label,
                    usedFraction: NSDecimalNumber(decimal: metric.used / limit).doubleValue,
                    windowDuration: nil,
                    resetsAt: metric.resetsAt,
                )
            }
            do {
                try snapshots.append(LimitSnapshot(
                    providerID: .cursor,
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
        return snapshots
    }

    private static func quotaSubject(for identity: CursorIdentity) -> QuotaSubject {
        if let teamID = identity.teamID {
            return QuotaSubject(
                id: QuotaSubjectID(rawValue: "cursor-team:\(teamID)"),
                label: "Team",
                kind: .team,
            )
        }
        return QuotaSubject(
            id: QuotaSubjectID(rawValue: "cursor-user:\(identity.userID)"),
            label: "Personal",
            kind: .personal,
        )
    }
}

private struct CursorSnapshotValues {
    let id: String
    let label: String
    let usedFraction: Double
    let windowDuration: TimeInterval?
    let resetsAt: Date?
}

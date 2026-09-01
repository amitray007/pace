import Foundation
import PaceCore

enum ClaudeRateLimitNormalizer {
    static func normalize(
        _ result: ClaudeUsageResult,
        accountID: AccountID,
    ) throws(ClaudeProviderError) -> [LimitSnapshot] {
        let subject = QuotaSubject(
            id: QuotaSubjectID(rawValue: "claude-organization:\(result.identity.organizationID)"),
            label: result.identity.organizationName ?? "Organization",
            kind: .organization,
        )
        var snapshots: [LimitSnapshot] = []
        for metric in result.metrics {
            let values: SnapshotValues
            switch metric {
            case let .percentage(metric):
                values = SnapshotValues(
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
                values = SnapshotValues(
                    id: metric.id,
                    label: metric.label,
                    usedFraction: NSDecimalNumber(decimal: metric.used / limit).doubleValue,
                    windowDuration: nil,
                    resetsAt: nil,
                )
            }
            do {
                try snapshots.append(LimitSnapshot(
                    providerID: .claude,
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
}

private struct SnapshotValues {
    let id: String
    let label: String
    let usedFraction: Double
    let windowDuration: TimeInterval?
    let resetsAt: Date?
}

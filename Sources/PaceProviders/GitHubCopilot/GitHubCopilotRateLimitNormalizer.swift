import Foundation
import PaceCore

enum GitHubCopilotRateLimitNormalizer {
    static func normalize(
        _ result: GitHubCopilotUsageResult,
        accountID: AccountID,
    ) throws(GitHubCopilotProviderError) -> [LimitSnapshot] {
        let subject = QuotaSubject(
            id: QuotaSubjectID(rawValue: "github-user:\(result.identity.userID)"),
            label: "Personal",
            kind: .personal,
        )
        var snapshots: [LimitSnapshot] = []
        for metric in result.metrics {
            let values: GitHubCopilotSnapshotValues
            switch metric {
            case let .percentage(percentage):
                values = GitHubCopilotSnapshotValues(
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
                values = GitHubCopilotSnapshotValues(
                    id: amount.id,
                    label: amount.label,
                    usedFraction: NSDecimalNumber(decimal: amount.used / limit).doubleValue,
                    resetsAt: amount.resetsAt,
                    windowDuration: nil,
                )
            }
            do {
                try snapshots.append(LimitSnapshot(
                    providerID: .githubCopilot,
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
        guard !snapshots.isEmpty || result.isOrganizationManaged else {
            throw .invalidResponse
        }
        return snapshots
    }
}

private struct GitHubCopilotSnapshotValues {
    let id: String
    let label: String
    let usedFraction: Double
    let resetsAt: Date?
    let windowDuration: TimeInterval?
}

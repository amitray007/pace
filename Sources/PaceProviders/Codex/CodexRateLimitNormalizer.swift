import Foundation
import PaceCore

enum CodexRateLimitNormalizer {
    static func normalize(
        _ response: CodexRateLimitsResponse,
        accountID: AccountID,
        observedAt: Date,
    ) throws -> [LimitSnapshot] {
        let context = CodexNormalizationContext(
            accountID: accountID,
            observedAt: observedAt,
        )
        return try orderedBuckets(response).flatMap { bucketID, bucket in
            try [
                snapshot(
                    bucketID: bucketID,
                    bucket: bucket,
                    windowName: "primary",
                    window: bucket.primary,
                    context: context,
                ),
                snapshot(
                    bucketID: bucketID,
                    bucket: bucket,
                    windowName: "secondary",
                    window: bucket.secondary,
                    context: context,
                ),
            ].compactMap(\.self)
        }
    }

    private static func orderedBuckets(
        _ response: CodexRateLimitsResponse,
    ) -> [(String, CodexRateLimitSnapshot)] {
        let returned = response.rateLimitsByLimitID ?? [:]
        if !returned.isEmpty {
            return returned.keys.sorted().compactMap { key in
                returned[key].map { (key, $0) }
            }
        }
        return [(response.rateLimits.limitID ?? "codex", response.rateLimits)]
    }

    private static func snapshot(
        bucketID: String,
        bucket: CodexRateLimitSnapshot,
        windowName: String,
        window: CodexRateLimitWindow?,
        context: CodexNormalizationContext,
    ) throws -> LimitSnapshot? {
        guard let window, window.usedPercent >= 0 else {
            return nil
        }
        let duration = window.windowDurationMins.map { TimeInterval($0 * 60) }
        return try LimitSnapshot(
            providerID: .codex,
            accountID: context.accountID,
            bucketID: BucketID(rawValue: "\(bucketID).\(windowName)"),
            label: label(for: bucket, window: window),
            usedFraction: Double(window.usedPercent) / 100,
            windowDuration: duration,
            resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            observedAt: context.observedAt,
            freshness: .current,
        )
    }

    private static func label(
        for bucket: CodexRateLimitSnapshot,
        window: CodexRateLimitWindow,
    ) -> String {
        let name = bucket.limitName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Codex"
        guard let minutes = window.windowDurationMins, minutes > 0 else {
            return baseName
        }
        let windowLabel = if minutes.isMultiple(of: 1440) {
            "\(minutes / 1440)-day"
        } else if minutes.isMultiple(of: 60) {
            "\(minutes / 60)-hour"
        } else {
            "\(minutes)-minute"
        }
        return "\(baseName) · \(windowLabel)"
    }
}

private struct CodexNormalizationContext {
    let accountID: AccountID
    let observedAt: Date
}

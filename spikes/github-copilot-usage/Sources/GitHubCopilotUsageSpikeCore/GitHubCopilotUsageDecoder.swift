import CoreFoundation
import Foundation

public struct GitHubCopilotDecodedUsage: Equatable, Sendable {
    public let planName: String?
    public let metrics: [GitHubCopilotMetric]
    public let isOrganizationManaged: Bool

    public init(
        planName: String?,
        metrics: [GitHubCopilotMetric],
        isOrganizationManaged: Bool,
    ) {
        self.planName = planName
        self.metrics = metrics
        self.isOrganizationManaged = isOrganizationManaged
    }
}

public enum GitHubCopilotUsageDecoder {
    private static let monthDuration: TimeInterval = 30 * 24 * 60 * 60

    public static func decodeIdentity(_ data: Data) throws -> GitHubIdentity {
        let response: IdentityResponse
        do {
            response = try JSONDecoder().decode(IdentityResponse.self, from: data)
        } catch {
            throw GitHubCopilotSpikeError.invalidResponse
        }
        let login = response.login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.id > 0, !login.isEmpty else {
            throw GitHubCopilotSpikeError.invalidResponse
        }
        return GitHubIdentity(
            userID: response.id,
            login: login,
            displayName: normalized(response.name),
        )
    }

    public static func decodeUsage(_ data: Data) throws -> GitHubCopilotDecodedUsage {
        let root = try decodeRoot(data)
        let reset = try resetDate(from: root)
        let snapshots = root["quota_snapshots"] as? [String: Any]
        var metrics = mappedSnapshotMetrics(snapshots, resetsAt: reset)
        if metrics.isEmpty {
            appendLegacyFreeMetrics(root, resetsAt: reset, to: &metrics)
        }

        let organizationManaged = bool(root["token_based_billing"]) == true
        let hasCredits = metrics.contains(where: { $0.id == "credits" })
        if organizationManaged, !hasCredits {
            appendPersonalCredits(snapshots?["premium_interactions"], to: &metrics)
        }
        guard !metrics.isEmpty || organizationManaged else {
            throw GitHubCopilotSpikeError.quotaUnavailable
        }
        return GitHubCopilotDecodedUsage(
            planName: planLabel(root["copilot_plan"]),
            metrics: metrics,
            isOrganizationManaged: organizationManaged,
        )
    }

    private static func mappedSnapshotMetrics(
        _ snapshots: [String: Any]?,
        resetsAt reset: Date?,
    ) -> [GitHubCopilotMetric] {
        var metrics: [GitHubCopilotMetric] = []
        let credits = snapshotMetric(
            id: "credits",
            label: "Credits",
            raw: snapshots?["premium_interactions"],
            resetsAt: reset,
        )
        if let credits {
            metrics.append(.percentage(credits))
            appendExtraUsage(snapshots?["premium_interactions"], to: &metrics)
        }
        appendSnapshot(
            id: "chat",
            label: "Chat",
            raw: snapshots?["chat"],
            resetsAt: reset,
            to: &metrics,
        )
        appendSnapshot(
            id: "completions",
            label: "Completions",
            raw: snapshots?["completions"],
            resetsAt: reset,
            to: &metrics,
        )
        return metrics
    }

    private static func decodeRoot(_ data: Data) throws -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GitHubCopilotSpikeError.invalidResponse
            }
            return object
        } catch let error as GitHubCopilotSpikeError {
            throw error
        } catch {
            throw GitHubCopilotSpikeError.invalidResponse
        }
    }

    private static func appendSnapshot(
        id: String,
        label: String,
        raw: Any?,
        resetsAt: Date?,
        to metrics: inout [GitHubCopilotMetric],
    ) {
        guard let metric = snapshotMetric(id: id, label: label, raw: raw, resetsAt: resetsAt) else {
            return
        }
        metrics.append(.percentage(metric))
    }

    private static func snapshotMetric(
        id: String,
        label: String,
        raw: Any?,
        resetsAt: Date?,
    ) -> GitHubCopilotPercentageMetric? {
        guard let snapshot = raw as? [String: Any] else {
            return nil
        }
        let entitlement = number(snapshot["entitlement"])
        let remaining = number(snapshot["remaining"])
        if bool(snapshot["unlimited"]) == true || entitlement == -1 || remaining == -1 {
            return nil
        }
        guard entitlement != 0 else {
            return nil
        }

        let usedPercent: Double
        if let percentRemaining = number(snapshot["percent_remaining"]) {
            usedPercent = boundedPercent(100 - percentRemaining)
        } else if let entitlement, entitlement > 0, let remaining {
            usedPercent = boundedPercent(100 - (remaining / entitlement) * 100)
        } else {
            return nil
        }
        return GitHubCopilotPercentageMetric(
            id: id,
            label: label,
            usedFraction: usedPercent / 100,
            resetsAt: resetsAt,
            windowDuration: monthDuration,
        )
    }

    private static func appendExtraUsage(
        _ raw: Any?,
        to metrics: inout [GitHubCopilotMetric],
    ) {
        guard let snapshot = raw as? [String: Any],
              bool(snapshot["overage_permitted"]) == true
        else {
            return
        }
        let used = max(0, number(snapshot["overage_count"]) ?? 0)
        metrics.append(.amount(GitHubCopilotAmountMetric(
            id: "extra-usage",
            label: "Extra Usage",
            used: Decimal(used),
            limit: nil,
            unit: "credits",
            resetsAt: nil,
        )))
    }

    private static func appendPersonalCredits(
        _ raw: Any?,
        to metrics: inout [GitHubCopilotMetric],
    ) {
        guard let snapshot = raw as? [String: Any],
              let used = number(snapshot["credits_used"]),
              used > 0
        else {
            return
        }
        metrics.append(.amount(GitHubCopilotAmountMetric(
            id: "credits",
            label: "Credits",
            used: Decimal(used),
            limit: nil,
            unit: "credits",
            resetsAt: nil,
        )))
    }

    private static func appendLegacyFreeMetrics(
        _ root: [String: Any],
        resetsAt: Date?,
        to metrics: inout [GitHubCopilotMetric],
    ) {
        let remaining = root["limited_user_quotas"] as? [String: Any]
        let limits = root["monthly_quotas"] as? [String: Any]
        for definition in [("chat", "Chat"), ("completions", "Completions")] {
            guard let limit = number(limits?[definition.0]), limit > 0,
                  let left = number(remaining?[definition.0])
            else {
                continue
            }
            metrics.append(.amount(GitHubCopilotAmountMetric(
                id: definition.0,
                label: definition.1,
                used: Decimal(max(0, limit - left)),
                limit: Decimal(limit),
                unit: "requests",
                resetsAt: resetsAt,
            )))
        }
    }

    private static func resetDate(from root: [String: Any]) throws -> Date? {
        guard let raw = (root["quota_reset_date"] as? String)
            ?? (root["limited_user_reset_date"] as? String)
        else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        if let date = iso8601Date(value) ?? dayOnlyDate(value) {
            return date
        }
        throw GitHubCopilotSpikeError.invalidResponse
    }

    private static func iso8601Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static func dayOnlyDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let result = value.doubleValue
        return result.isFinite ? result : nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID()
        else {
            return nil
        }
        return value.boolValue
    }

    private static func boundedPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func planLabel(_ value: Any?) -> String? {
        guard let value = normalized(value as? String) else {
            return nil
        }
        let words = value.split { $0 == "_" || $0 == "-" || $0 == " " }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

private struct IdentityResponse: Decodable {
    let id: Int64
    let login: String
    let name: String?
}

private extension GitHubCopilotMetric {
    var id: String {
        switch self {
        case let .amount(metric):
            metric.id
        case let .percentage(metric):
            metric.id
        }
    }
}

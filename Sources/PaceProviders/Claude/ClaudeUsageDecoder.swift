import Foundation

enum ClaudeUsageDecoder {
    static func decode(_ data: Data) throws(ClaudeProviderError) -> [ClaudeMetric] {
        let envelope: UsageEnvelope
        do {
            envelope = try JSONDecoder().decode(UsageEnvelope.self, from: data)
        } catch {
            throw .invalidResponse
        }

        var percentages = PercentageAccumulator()
        appendLegacyWindow(
            envelope.fiveHour,
            id: "current-session",
            label: "Session",
            duration: 5 * 60 * 60,
            to: &percentages,
        )
        appendLegacyWindow(
            envelope.sevenDay,
            id: "weekly-all-models",
            label: "Weekly",
            duration: 7 * 24 * 60 * 60,
            to: &percentages,
        )

        for limit in envelope.limits ?? [] {
            guard let percent = limit.percent, percent.isFinite, percent >= 0 else {
                continue
            }
            let descriptor = descriptor(for: limit)
            percentages.set(ClaudePercentageMetric(
                id: descriptor.id,
                label: descriptor.label,
                usedFraction: percent / 100,
                windowDuration: descriptor.duration,
                resetsAt: parseDate(limit.resetsAt),
            ))
        }

        var metrics = percentages.values.map(ClaudeMetric.percentage)
        if let amount = extraUsageMetric(envelope.extraUsage) {
            metrics.append(.amount(amount))
        }
        return metrics
    }

    private static func appendLegacyWindow(
        _ window: UsageWindow?,
        id: String,
        label: String,
        duration: TimeInterval,
        to metrics: inout PercentageAccumulator,
    ) {
        guard let utilization = window?.utilization,
              utilization.isFinite,
              utilization >= 0
        else {
            return
        }
        metrics.set(ClaudePercentageMetric(
            id: id,
            label: label,
            usedFraction: utilization / 100,
            windowDuration: duration,
            resetsAt: parseDate(window?.resetsAt),
        ))
    }

    private static func descriptor(for limit: UsageLimit) -> MetricDescriptor {
        let kind = stableComponent(limit.kind)
        switch limit.kind.lowercased() {
        case "session":
            return MetricDescriptor(
                id: "current-session",
                label: "Session",
                duration: 5 * 60 * 60,
            )
        case "weekly_all":
            return MetricDescriptor(
                id: "weekly-all-models",
                label: "Weekly",
                duration: 7 * 24 * 60 * 60,
            )
        case "weekly_scoped":
            let model = limit.scope?.model
            let rawScope = normalized(model?.id) ?? normalized(model?.displayName) ?? "unknown"
            return MetricDescriptor(
                id: "weekly-\(stableComponent(rawScope))",
                label: normalized(model?.displayName) ?? "Scoped weekly",
                duration: 7 * 24 * 60 * 60,
            )
        default:
            let scope = normalized(limit.scope?.model?.id)
                ?? normalized(limit.scope?.model?.displayName)
                ?? normalized(limit.scope?.surface)
            return MetricDescriptor(
                id: scope.map { "\(kind)-\(stableComponent($0))" } ?? kind,
                label: normalized(limit.scope?.model?.displayName) ?? humanized(kind),
                duration: kind.contains("weekly") ? 7 * 24 * 60 * 60 : nil,
            )
        }
    }

    private static func extraUsageMetric(_ extraUsage: ExtraUsage?) -> ClaudeAmountMetric? {
        guard extraUsage?.isEnabled == true,
              let rawUsed = extraUsage?.usedCredits,
              let rawLimit = extraUsage?.monthlyLimit,
              rawUsed.isFinite,
              rawUsed >= 0,
              rawLimit.isFinite,
              rawLimit > 0
        else {
            return nil
        }
        let decimalPlaces = max(0, extraUsage?.decimalPlaces ?? 2)
        let divisor = pow(10, Double(decimalPlaces))
        return ClaudeAmountMetric(
            id: "extra-usage",
            label: "Extra usage",
            used: Decimal(rawUsed / divisor),
            limit: Decimal(rawLimit / divisor),
            unit: normalized(extraUsage?.currency)?.uppercased() ?? "CREDITS",
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = normalized(value) else {
            return nil
        }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }

    private static func stableComponent(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let result = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return result.isEmpty ? "unknown" : result
    }

    private static func humanized(_ value: String) -> String {
        value.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func normalized(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }
}

private struct PercentageAccumulator {
    private var metrics: [String: ClaudePercentageMetric] = [:]
    private var order: [String] = []

    var values: [ClaudePercentageMetric] {
        order.compactMap { metrics[$0] }
    }

    mutating func set(_ metric: ClaudePercentageMetric) {
        if metrics[metric.id] == nil {
            order.append(metric.id)
        }
        metrics[metric.id] = metric
    }
}

private struct MetricDescriptor {
    let id: String
    let label: String
    let duration: TimeInterval?
}

private struct UsageEnvelope: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let limits: [UsageLimit]?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
        case extraUsage = "extra_usage"
    }
}

private struct UsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct UsageLimit: Decodable {
    let kind: String
    let percent: Double?
    let resetsAt: String?
    let scope: UsageScope?

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case resetsAt = "resets_at"
        case scope
    }
}

private struct UsageScope: Decodable {
    let model: UsageModel?
    let surface: String?
}

private struct UsageModel: Decodable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct ExtraUsage: Decodable {
    let isEnabled: Bool
    let usedCredits: Double?
    let monthlyLimit: Double?
    let currency: String?
    let decimalPlaces: Int?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
        case currency
        case decimalPlaces = "decimal_places"
    }
}

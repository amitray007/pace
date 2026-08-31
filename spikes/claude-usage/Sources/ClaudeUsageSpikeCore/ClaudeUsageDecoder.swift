import Foundation

public enum ClaudeUsageDecoder {
    public static func decode(_ data: Data) throws -> [ClaudeMetric] {
        let envelope: UsageEnvelope
        do {
            envelope = try JSONDecoder().decode(UsageEnvelope.self, from: data)
        } catch {
            throw ClaudeSpikeError.invalidResponse
        }

        var percentages = PercentageAccumulator()

        appendLegacyWindow(
            envelope.fiveHour,
            id: "session",
            label: "Session",
            duration: 5 * 60 * 60,
            to: &percentages,
        )
        appendLegacyWindow(
            envelope.sevenDay,
            id: "weekly",
            label: "Weekly",
            duration: 7 * 24 * 60 * 60,
            to: &percentages,
        )

        for limit in envelope.limits ?? [] {
            guard let percent = limit.percent, percent.isFinite, percent >= 0 else {
                continue
            }
            let descriptor = descriptor(for: limit)
            let metric = ClaudePercentageMetric(
                id: descriptor.id,
                label: descriptor.label,
                usedFraction: percent / 100,
                windowDuration: descriptor.duration,
                resetsAt: parseDate(limit.resetsAt),
            )
            percentages.set(metric)
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
        let kind = limit.kind.lowercased()
        switch kind {
        case "session":
            return MetricDescriptor(
                id: "session",
                label: "Session",
                duration: 5 * 60 * 60,
            )
        case "weekly_all":
            return MetricDescriptor(
                id: "weekly",
                label: "Weekly",
                duration: 7 * 24 * 60 * 60,
            )
        case "weekly_scoped":
            let scope = limit.scope?.model
            let rawScope = scope?.id?.nilIfBlank ?? scope?.displayName?.nilIfBlank ?? "unknown"
            return MetricDescriptor(
                id: "weekly:\(stableComponent(rawScope))",
                label: scope?.displayName?.nilIfBlank ?? "Scoped weekly",
                duration: 7 * 24 * 60 * 60,
            )
        default:
            let scope = limit.scope?.model?.id?.nilIfBlank
                ?? limit.scope?.model?.displayName?.nilIfBlank
                ?? limit.scope?.surface?.nilIfBlank
            let suffix = scope.map { ":\(stableComponent($0))" } ?? ""
            return MetricDescriptor(
                id: "\(stableComponent(kind))\(suffix)",
                label: limit.scope?.model?.displayName?.nilIfBlank ?? humanized(kind),
                duration: kind.contains("weekly") ? 7 * 24 * 60 * 60 : nil,
            )
        }
    }

    private static func extraUsageMetric(_ extraUsage: ExtraUsage?) -> ClaudeAmountMetric? {
        guard extraUsage?.isEnabled == true,
              let rawUsed = extraUsage?.usedCredits,
              rawUsed.isFinite,
              rawUsed >= 0
        else {
            return nil
        }
        let decimalPlaces = max(0, extraUsage?.decimalPlaces ?? 2)
        let divisor = pow(10, Double(decimalPlaces))
        let used = Decimal(rawUsed / divisor)
        let limit = extraUsage?.monthlyLimit.flatMap { rawLimit -> Decimal? in
            guard rawLimit.isFinite, rawLimit > 0 else {
                return nil
            }
            return Decimal(rawLimit / divisor)
        }
        return ClaudeAmountMetric(
            id: "extra-usage",
            label: "Extra usage spent",
            value: used,
            limit: limit,
            unit: extraUsage?.currency?.nilIfBlank?.uppercased() ?? "credits",
            semantic: .used,
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.nilIfBlank else {
            return nil
        }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? fractional.parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }

    private static func stableComponent(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        return String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    private static func humanized(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

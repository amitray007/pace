import CoreFoundation
import Foundation

public enum CursorUsageDecoder {
    public static func decode(_ data: Data) throws -> [CursorMetric] {
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CursorSpikeError.invalidResponse
            }
            root = object
        } catch let error as CursorSpikeError {
            throw error
        } catch {
            throw CursorSpikeError.invalidResponse
        }

        guard root["enabled"] as? Bool != false,
              let planUsage = root["planUsage"] as? [String: Any]
        else {
            throw CursorSpikeError.invalidResponse
        }

        let cycle = cycle(from: root)
        var metrics: [CursorMetric] = []
        appendPlanPercentages(planUsage, cycle: cycle, to: &metrics)

        if !metrics.contains(where: { metric in
            guard case let .percentage(value) = metric else { return false }
            return value.id == "total"
        }) {
            appendPlanAmount(planUsage, resetsAt: cycle.resetsAt, to: &metrics)
        }

        if let spendLimit = root["spendLimitUsage"] as? [String: Any] {
            appendOnDemand(spendLimit, resetsAt: cycle.resetsAt, to: &metrics)
        }

        guard !metrics.isEmpty else {
            throw CursorSpikeError.invalidResponse
        }
        return metrics
    }

    public static func decodePlan(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let planInfo = root["planInfo"] as? [String: Any],
              let planName = planInfo["planName"] as? String
        else {
            return nil
        }
        let words = planName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { word in word.prefix(1).uppercased() + word.dropFirst().lowercased() }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    private static func appendPercentage(
        id: String,
        label: String,
        value: Double?,
        cycle: Cycle,
        to metrics: inout [CursorMetric],
    ) {
        guard let value, value.isFinite, value >= 0 else {
            return
        }
        metrics.append(.percentage(CursorPercentageMetric(
            id: id,
            label: label,
            usedFraction: value / 100,
            resetsAt: cycle.resetsAt,
            windowDuration: cycle.duration,
        )))
    }

    private static func appendPlanPercentages(
        _ usage: [String: Any],
        cycle: Cycle,
        to metrics: inout [CursorMetric],
    ) {
        let definitions = [
            ("total", "Total Usage", "totalPercentUsed"),
            ("cursor-models", "Cursor Models", "autoPercentUsed"),
            ("other-models", "Other Models", "apiPercentUsed"),
        ]
        for definition in definitions {
            appendPercentage(
                id: definition.0,
                label: definition.1,
                value: number(usage[definition.2]),
                cycle: cycle,
                to: &metrics,
            )
        }
    }

    private static func appendPlanAmount(
        _ usage: [String: Any],
        resetsAt: Date?,
        to metrics: inout [CursorMetric],
    ) {
        guard let limit = number(usage["limit"]), limit > 0 else {
            return
        }
        let used = number(usage["totalSpend"])
            ?? number(usage["remaining"]).map { max(0, limit - $0) }
        guard let used, used.isFinite, used >= 0 else {
            return
        }
        metrics.append(.amount(CursorAmountMetric(
            id: "total",
            label: "Total Usage",
            used: centsToDollars(used),
            limit: centsToDollars(limit),
            unit: "USD",
            resetsAt: resetsAt,
        )))
    }

    private static func appendOnDemand(
        _ usage: [String: Any],
        resetsAt: Date?,
        to metrics: inout [CursorMetric],
    ) {
        let limit = number(usage["individualLimit"]) ?? number(usage["pooledLimit"])
        guard let limit, limit.isFinite, limit > 0 else {
            return
        }
        let remaining = number(usage["individualRemaining"])
            ?? number(usage["pooledRemaining"])
        let reportedUsed = [
            number(usage["individualUsed"]),
            number(usage["pooledUsed"]),
            number(usage["totalSpend"]),
        ].compactMap(\.self).first(where: { $0 > 0 })
        let used = reportedUsed ?? remaining.map { max(0, limit - $0) } ?? 0
        guard used.isFinite, used >= 0 else {
            return
        }
        metrics.append(.amount(CursorAmountMetric(
            id: "on-demand",
            label: "Extra Usage",
            used: centsToDollars(used),
            limit: centsToDollars(limit),
            unit: "USD",
            resetsAt: resetsAt,
        )))
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let number = value.doubleValue
        return number.isFinite ? number : nil
    }

    private static func date(from timestamp: Double?) -> Date? {
        guard let timestamp, timestamp > 0 else {
            return nil
        }
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }

    private static func cycleDuration(start: Date?, end: Date?) -> TimeInterval? {
        guard let start, let end, end > start else {
            return nil
        }
        return end.timeIntervalSince(start)
    }

    private static func cycle(from root: [String: Any]) -> Cycle {
        let start = date(from: number(root["billingCycleStart"]))
        let end = date(from: number(root["billingCycleEnd"]))
        return Cycle(
            resetsAt: end,
            duration: cycleDuration(start: start, end: end),
        )
    }

    private static func centsToDollars(_ cents: Double) -> Decimal {
        Decimal(cents) / 100
    }
}

private struct Cycle {
    let resetsAt: Date?
    let duration: TimeInterval?
}

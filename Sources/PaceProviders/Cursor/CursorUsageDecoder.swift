import CoreFoundation
import Foundation

enum CursorUsageDecoder {
    static func decode(_ data: Data) throws(CursorProviderError) -> [CursorMetric] {
        let root = try object(from: data)
        guard root["enabled"] as? Bool != false,
              let planUsage = root["planUsage"] as? [String: Any]
        else {
            throw .invalidResponse
        }

        let cycle = cycle(from: root)
        var metrics: [CursorMetric] = []
        appendPlanPercentages(planUsage, cycle: cycle, to: &metrics)
        if !containsTotalPercentage(metrics) {
            appendPlanAmount(planUsage, resetsAt: cycle.resetsAt, to: &metrics)
        }
        if let spendLimit = root["spendLimitUsage"] as? [String: Any] {
            appendOnDemand(spendLimit, resetsAt: cycle.resetsAt, to: &metrics)
        }
        return metrics
    }

    static func decodePlan(_ data: Data) -> String? {
        guard let root = try? object(from: data),
              let planInfo = root["planInfo"] as? [String: Any],
              let planName = planInfo["planName"] as? String
        else {
            return nil
        }
        let words = planName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    private static func object(from data: Data) throws(CursorProviderError) -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CursorProviderError.invalidResponse
            }
            return object
        } catch let error as CursorProviderError {
            throw error
        } catch {
            throw .invalidResponse
        }
    }

    private static func appendPlanPercentages(
        _ usage: [String: Any],
        cycle: CursorBillingCycle,
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

    private static func appendPercentage(
        id: String,
        label: String,
        value: Double?,
        cycle: CursorBillingCycle,
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

    private static func containsTotalPercentage(_ metrics: [CursorMetric]) -> Bool {
        metrics.contains { metric in
            guard case let .percentage(value) = metric else {
                return false
            }
            return value.id == "total"
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
        guard let used, used >= 0 else {
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
        let remaining = number(usage["individualRemaining"]) ?? number(usage["pooledRemaining"])
        let reported = [
            number(usage["individualUsed"]),
            number(usage["pooledUsed"]),
            number(usage["totalSpend"]),
        ].compactMap(\.self)
        let inferred = limit.flatMap { limit in remaining.map { max(0, limit - $0) } }
        let used = reported.first(where: { $0 > 0 }) ?? inferred ?? reported.first
        guard let used, used >= 0 else {
            return
        }
        if let limit, limit > 0 {
            metrics.append(.amount(CursorAmountMetric(
                id: "on-demand",
                label: "Extra Usage",
                used: centsToDollars(used),
                limit: centsToDollars(limit),
                unit: "USD",
                resetsAt: resetsAt,
            )))
        }
    }

    private static func cycle(from root: [String: Any]) -> CursorBillingCycle {
        let start = date(from: number(root["billingCycleStart"]))
        let end = date(from: number(root["billingCycleEnd"]))
        let duration: TimeInterval? = if let start, let end, end > start {
            end.timeIntervalSince(start)
        } else {
            nil
        }
        return CursorBillingCycle(resetsAt: end, duration: duration)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else {
                return nil
            }
            let number = value.doubleValue
            return number.isFinite ? number : nil
        }
        // Connect encodes 64-bit integers such as `billingCycleEnd` as JSON strings.
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces),
              !text.isEmpty,
              let number = Double(text),
              number.isFinite
        else {
            return nil
        }
        return number
    }

    private static func date(from timestamp: Double?) -> Date? {
        guard let timestamp, timestamp > 0 else {
            return nil
        }
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }

    private static func centsToDollars(_ cents: Double) -> Decimal {
        Decimal(cents) / 100
    }
}

private struct CursorBillingCycle {
    let resetsAt: Date?
    let duration: TimeInterval?
}

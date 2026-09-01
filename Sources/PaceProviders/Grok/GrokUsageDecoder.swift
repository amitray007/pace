import Foundation

enum GrokUsageDecoder {
    static func decodeIdentity(_ data: Data) throws(GrokProviderError) -> GrokRemoteIdentity {
        let response: UserResponse
        do {
            response = try JSONDecoder().decode(UserResponse.self, from: data)
        } catch {
            throw .invalidResponse
        }
        guard let userID = normalized(response.userID) else {
            throw .invalidResponse
        }
        return GrokRemoteIdentity(
            identity: GrokIdentity(
                userID: userID,
                principalID: normalized(response.principalID),
                teamID: normalized(response.teamID),
                email: normalized(response.email),
                displayName: displayName(
                    firstName: response.firstName,
                    lastName: response.lastName,
                ),
            ),
            planName: normalized(response.subscriptionTier),
        )
    }

    static func decodeUsage(_ data: Data) throws(GrokProviderError) -> [GrokMetric] {
        let response: BillingResponse
        do {
            response = try JSONDecoder().decode(BillingResponse.self, from: data)
        } catch {
            throw .invalidResponse
        }
        guard let config = response.config else {
            throw .invalidResponse
        }

        var metrics: [GrokMetric] = []
        try appendIncluded(config, to: &metrics)
        appendOnDemand(config, to: &metrics)
        guard !metrics.isEmpty else {
            throw .invalidResponse
        }
        return metrics
    }

    private static func appendIncluded(
        _ config: BillingConfig,
        to metrics: inout [GrokMetric],
    ) throws(GrokProviderError) {
        if let period = config.currentPeriod {
            let cycle = try cycle(from: period)
            let percentage = config.creditUsagePercent ?? 0
            guard percentage.isFinite, percentage >= 0 else {
                throw .invalidResponse
            }
            metrics.append(.percentage(GrokPercentageMetric(
                id: cycle.id,
                label: cycle.label,
                usedFraction: percentage / 100,
                resetsAt: cycle.end,
                windowDuration: cycle.duration,
            )))
            return
        }

        if let percentage = config.creditUsagePercent {
            guard percentage.isFinite, percentage >= 0 else {
                throw .invalidResponse
            }
            metrics.append(.percentage(GrokPercentageMetric(
                id: "included",
                label: "Included Credits",
                usedFraction: percentage / 100,
                resetsAt: nil,
                windowDuration: nil,
            )))
            return
        }

        if let limit = config.monthlyLimit?.value, limit > 0 {
            let used = config.used?.value ?? 0
            guard used >= 0 else {
                throw .invalidResponse
            }
            try metrics.append(.amount(GrokAmountMetric(
                id: "included-monthly",
                label: "Monthly Limit",
                used: centsToDollars(used),
                limit: centsToDollars(limit),
                resetsAt: optionalDate(config.billingPeriodEnd),
            )))
        }
    }

    private static func appendOnDemand(
        _ config: BillingConfig,
        to metrics: inout [GrokMetric],
    ) {
        guard let limit = config.onDemandCap?.value, limit > 0 else {
            return
        }
        let used = max(0, config.onDemandUsed?.value ?? 0)
        metrics.append(.amount(GrokAmountMetric(
            id: "on-demand",
            label: "Pay As You Go",
            used: centsToDollars(used),
            limit: centsToDollars(limit),
            resetsAt: nil,
        )))
    }

    private static func cycle(from period: UsagePeriod) throws(GrokProviderError) -> Cycle {
        let start = try optionalDate(period.start)
        let end = try optionalDate(period.end)
        let duration: TimeInterval? = if let start, let end, end > start {
            end.timeIntervalSince(start)
        } else {
            nil
        }
        switch period.type?.uppercased() {
        case "USAGE_PERIOD_TYPE_WEEKLY":
            return Cycle(id: "included-weekly", label: "Weekly Limit", end: end, duration: duration)
        case "USAGE_PERIOD_TYPE_MONTHLY":
            return Cycle(
                id: "included-monthly",
                label: "Monthly Limit",
                end: end,
                duration: duration,
            )
        default:
            return Cycle(id: "included", label: "Included Credits", end: end, duration: duration)
        }
    }

    private static func optionalDate(_ value: String?) throws(GrokProviderError) -> Date? {
        guard let value else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        guard let date = standard.date(from: value) else {
            throw .invalidResponse
        }
        return date
    }

    private static func centsToDollars(_ cents: Decimal) -> Decimal {
        cents / 100
    }

    private static func normalized(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private static func displayName(firstName: String?, lastName: String?) -> String? {
        let values = [firstName, lastName].compactMap(normalized)
        return values.isEmpty ? nil : values.joined(separator: " ")
    }
}

struct GrokRemoteIdentity: Equatable, Sendable {
    let identity: GrokIdentity
    let planName: String?
}

private struct UserResponse: Decodable {
    let userID: String?
    let email: String?
    let firstName: String?
    let lastName: String?
    let principalID: String?
    let teamID: String?
    let subscriptionTier: String?

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case email
        case firstName
        case lastName
        case principalID = "principalId"
        case teamID = "teamId"
        case subscriptionTier
    }
}

private struct BillingResponse: Decodable {
    let config: BillingConfig?
}

private struct BillingConfig: Decodable {
    let creditUsagePercent: Double?
    let currentPeriod: UsagePeriod?
    let monthlyLimit: Cent?
    let used: Cent?
    let onDemandCap: Cent?
    let onDemandUsed: Cent?
    let billingPeriodEnd: String?
}

private struct UsagePeriod: Decodable {
    let type: String?
    let start: String?
    let end: String?
}

private struct Cent: Decodable {
    let value: Decimal

    private enum CodingKeys: String, CodingKey {
        case value = "val"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.value) else {
            value = 0
            return
        }
        if let value = try? container.decode(Decimal.self, forKey: .value) {
            self.value = value
        } else if let string = try? container.decode(String.self, forKey: .value) {
            guard let value = Decimal(string: string) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Expected a numeric cent value.",
                )
            }
            self.value = value
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Expected a numeric cent value.",
            )
        }
    }
}

private struct Cycle {
    let id: String
    let label: String
    let end: Date?
    let duration: TimeInterval?
}

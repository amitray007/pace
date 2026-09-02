import PaceCore
import SwiftUI

struct UsageStatusPresentation {
    enum Severity: Equatable {
        case error
        case neutral
        case positive
        case warning
    }

    let title: String
    let detail: String
    let symbolName: String
    let severity: Severity
    let observationText: String

    /// What to show when a provider has no usage status yet.
    ///
    /// Absence means two different things depending on when it is observed.
    /// Before the first refresh finishes, the providers simply have not been
    /// read; afterwards, there is genuinely nothing configured. Telling a user
    /// with a working account to go add one is worse than saying nothing, so
    /// the two are distinguished here rather than at each call site.
    static func missing(isLoading: Bool) -> Self {
        isLoading
            ? Self(
                title: "Loading usage",
                detail: "Reading this provider's limits.",
                symbolName: "arrow.clockwise",
                severity: .neutral,
                observationText: "Not observed",
            )
            : Self(
                title: "No account configured",
                detail: "Add an account for this provider to see usage.",
                symbolName: "person.crop.circle.badge.questionmark",
                severity: .neutral,
                observationText: "Not observed",
            )
    }

    var color: Color {
        switch severity {
        case .error:
            .red
        case .neutral:
            .secondary
        case .positive:
            .green
        case .warning:
            .orange
        }
    }

    static func resolve(
        _ status: AccountUsageStatus,
        referenceDate: Date = SimulatedScenarios.referenceDate,
    ) -> Self {
        if status.hasData {
            return dataPresentation(status, referenceDate: referenceDate)
        }
        return noDataPresentation(status, referenceDate: referenceDate)
    }

    private static func dataPresentation(
        _ status: AccountUsageStatus,
        referenceDate: Date,
    ) -> Self {
        switch status.dataFreshness {
        case .current:
            if let issue = status.connectionIssue {
                return issuePresentation(
                    issue,
                    observationText: observationText(status.observedAt),
                    retainsLastGoodData: true,
                    referenceDate: referenceDate,
                )
            }
            return Self(
                title: "Current",
                detail: "Usage is current.",
                symbolName: "checkmark.circle.fill",
                severity: .positive,
                observationText: observationText(status.observedAt),
            )
        case .aging:
            return Self(
                title: "Aging data",
                detail: "Usage has not refreshed recently.",
                symbolName: "clock.badge.exclamationmark",
                severity: .warning,
                observationText: observationText(status.observedAt),
            )
        case .stale:
            let reason = status.connectionIssue.map {
                issueDetail($0, referenceDate: referenceDate)
            }
            return Self(
                title: "Stale data",
                detail: reason ?? "The latest refresh did not return current usage.",
                symbolName: "clock.arrow.circlepath",
                severity: .warning,
                observationText: observationText(status.observedAt),
            )
        case .noData:
            return noDataPresentation(status, referenceDate: referenceDate)
        }
    }

    private static func noDataPresentation(
        _ status: AccountUsageStatus,
        referenceDate: Date,
    ) -> Self {
        guard let issue = status.connectionIssue else {
            return Self(
                title: "No limits returned",
                detail: "The provider returned no quota buckets.",
                symbolName: "minus.circle",
                severity: .neutral,
                observationText: "Not observed",
            )
        }
        return issuePresentation(
            issue,
            observationText: "Not observed",
            retainsLastGoodData: false,
            referenceDate: referenceDate,
        )
    }

    private static func issuePresentation(
        _ issue: AccountConnectionIssue,
        observationText: String,
        retainsLastGoodData: Bool,
        referenceDate: Date,
    ) -> Self {
        let title: String
        let symbolName: String
        let severity: Severity
        switch issue {
        case .needsAuthentication:
            title = retainsLastGoodData ? "Stale data" : "Sign in required"
            symbolName = "person.crop.circle.badge.exclamationmark"
            severity = .warning
        case .identityMismatch:
            title = retainsLastGoodData ? "Stale data" : "Account changed"
            symbolName = "person.crop.circle.badge.questionmark"
            severity = .error
        case .rateLimited:
            title = retainsLastGoodData ? "Stale data" : "Rate limited"
            symbolName = "hourglass"
            severity = .warning
        case .unavailable:
            title = retainsLastGoodData ? "Stale data" : "Usage unavailable"
            symbolName = "wifi.exclamationmark"
            severity = .warning
        case .failed:
            title = retainsLastGoodData ? "Stale data" : "Refresh failed"
            symbolName = "exclamationmark.triangle.fill"
            severity = .error
        }
        return Self(
            title: title,
            detail: issueDetail(issue, referenceDate: referenceDate),
            symbolName: symbolName,
            severity: severity,
            observationText: observationText,
        )
    }

    private static func issueDetail(
        _ issue: AccountConnectionIssue,
        referenceDate: Date,
    ) -> String {
        switch issue {
        case .needsAuthentication:
            "Reconnect this account to refresh usage."
        case .identityMismatch:
            "The provider profile now belongs to a different account."
        case let .rateLimited(retryAt):
            retryAt.map {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                return "Try again \(formatter.localizedString(for: $0, relativeTo: referenceDate))."
            } ?? "The provider asked Pace to wait before refreshing."
        case .unavailable:
            "The provider could not return usage."
        case .failed:
            "The latest refresh failed."
        }
    }

    private static func observationText(_ observedAt: Date?) -> String {
        guard let observedAt else {
            return "Not observed"
        }
        return "Observed \(observedAt.formatted(date: .omitted, time: .shortened))"
    }
}

struct UsageStatusLabel: View {
    let presentation: UsageStatusPresentation

    var body: some View {
        Label(presentation.title, systemImage: presentation.symbolName)
            .foregroundStyle(presentation.color)
            .accessibilityLabel("\(presentation.title). \(presentation.detail)")
    }
}

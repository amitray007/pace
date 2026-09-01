import PaceCore
import SwiftUI

struct MenuQuotaRow: View {
    let snapshot: LimitSnapshot
    let referenceDate: Date
    let accent: Color
    let increasedContrast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.label)
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(snapshot.usedFraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            }
            // The bar reports how much of the quota is gone, so it follows the
            // usage-level palette rather than the provider's brand colour. The
            // provider is already identified by the tab and the header mark.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(
                        Color.paceUsageTrack(increasedContrast: increasedContrast),
                    )
                    Capsule()
                        .fill(Color.paceUsageAccent(forFraction: snapshot.usedFraction))
                        .frame(width: proxy.size.width * min(snapshot.usedFraction, 1))
                }
            }
            .frame(height: 4)

            HStack {
                Text(resetDescription)
                Spacer()
                Text(observationDescription)
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .focusable()
    }

    private var resetDescription: String {
        QuotaResetText.description(
            resetsAt: snapshot.resetsAt,
            relativeTo: referenceDate,
        )
    }

    private var accessibilityDescription: String {
        "\(snapshot.label), \(Int(snapshot.usedFraction * 100)) percent used, " +
            "\(resetDescription), \(observationDescription)"
    }

    private var observationDescription: String {
        let observation = snapshot.observedAt.formatted(date: .omitted, time: .shortened)
        switch snapshot.freshness {
        case .current:
            return "Observed \(observation)"
        case .aging:
            return "Aging · \(observation)"
        case .failed:
            return "Failed · \(observation)"
        case .signedOut:
            return "Signed out · \(observation)"
        case .stale:
            return "Stale · \(observation)"
        case .unavailable:
            return "Unavailable · \(observation)"
        }
    }
}

struct MenuUsageStateView: View {
    let presentation: UsageStatusPresentation

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: presentation.symbolName)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(presentation.color)
            Text(presentation.title)
                .font(.system(size: 12, weight: .semibold))
            Text(presentation.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.title). \(presentation.detail)")
        .focusable()
    }
}

struct AllAccountsRow: View {
    let account: ProviderAccount
    let snapshots: [LimitSnapshot]
    let status: AccountUsageStatus
    let accent: Color
    let increasedContrast: Bool

    var body: some View {
        let urgent = snapshots.max { $0.usedFraction < $1.usedFraction }
        let presentation = UsageStatusPresentation.resolve(status)
        HStack(spacing: 12) {
            Circle()
                .fill(accent.opacity(0.16))
                .frame(width: 30, height: 30)
                .overlay {
                    Text(account.displayName.prefix(1))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(account.planName ?? "Plan unavailable") · \(presentation.title)")
                    .font(.system(size: 10))
                    .foregroundStyle(presentation.color)
            }
            Spacer()
            if let urgent {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(urgent.usedFraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Text(urgent.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(11)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if increasedContrast {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(account.displayName), \(presentation.title). \(presentation.detail)",
        )
        .focusable()
    }
}

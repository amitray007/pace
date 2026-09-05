import AppKit
import PaceCore
import SwiftUI

struct EdgeDetailPanel: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let content: RailDetailContent
    var isActive = true

    private var providerID: ProviderID {
        content.providerID
    }

    private var snapshots: [LimitSnapshot] {
        content.snapshots
    }

    private var presentation: UsageStatusPresentation {
        content.presentation
    }

    var body: some View {
        let style = ProviderStyle.resolve(providerID)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ProviderMark(providerID: providerID, color: .white, size: 13)
                Text("\(style.name) Usage")
                    .font(.system(size: 13, weight: .bold))
                Spacer(minLength: 0)
            }

            if snapshots.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: presentation.symbolName)
                        .foregroundStyle(presentation.color)
                    Text(presentation.title)
                        .font(.system(size: 10, weight: .semibold))
                    Text(presentation.detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                quotaContent
            }
            Divider()
                .overlay(Color.white.opacity(0.14))

            HStack(spacing: 8) {
                if snapshots.isEmpty || presentation.severity != .positive {
                    Text(presentation.title)
                        .lineLimit(1)
                        .foregroundStyle(presentation.color)
                } else {
                    Text(content.accountName).lineLimit(1).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 4)
                RefreshCountdownView(
                    nextRefreshAt: content.nextRefreshAt,
                    isRefreshing: content.isRefreshing,
                    style: .sentence,
                    isActive: isActive,
                )
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 9.5, weight: .medium))
        }
        .padding(.horizontal, 16)
        // The title and the footer line sit directly against these edges, so
        // this is what keeps them off the panel's rounded border.
        .padding(.vertical, 16)
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: EdgeRailGeometry.detailWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(style.name) usage for \(content.accountName). " +
                "\(presentation.title). \(presentation.detail)",
        )
    }

    @ViewBuilder
    private var quotaContent: some View {
        if snapshots.count <= EdgeRailGeometry.maximumDetailQuotaRows {
            VStack(alignment: .leading, spacing: 9) { quotaRows() }
        } else {
            // The first visible rows define the viewport's natural height.
            // The overlay scrolls the full list inside that exact space.
            VStack(alignment: .leading, spacing: 9) {
                quotaRows(limit: EdgeRailGeometry.maximumDetailQuotaRows)
            }
            .hidden()
            .overlay {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 9) { quotaRows() }
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    /// The reference quota block puts the label and its reset time on one line,
    /// the bar beneath them, and the used percentage on its own line below the
    /// bar. Measured from `settings-claude-detail.png`.
    private func quotaRows(limit: Int? = nil) -> some View {
        let rows = Array(zip(snapshots, content.resetTexts).prefix(limit ?? snapshots.count))
        return ForEach(rows, id: \.0.id) { snapshot, resetText in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(snapshot.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(resetText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(
                            Color.paceUsageTrack(increasedContrast: usesIncreasedContrast),
                        )
                        Capsule()
                            .fill(Color.paceUsageAccent(forFraction: snapshot.usedFraction))
                            .frame(
                                width: max(
                                    proxy.size.width * min(snapshot.usedFraction, 1),
                                    snapshot.usedFraction > 0 ? 3 : 0,
                                ),
                            )
                    }
                }
                .frame(height: 4)

                Text(usedText(for: snapshot))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }

    private func usedText(for snapshot: LimitSnapshot) -> String {
        let percentage = Int((min(max(snapshot.usedFraction, 0), 1) * 100).rounded())
        return "\(percentage)% Used"
    }

    private var usesIncreasedContrast: Bool {
        colorSchemeContrast == .increased || content.increasedContrast
    }
}

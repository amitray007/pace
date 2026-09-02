import Foundation
import PaceCore

/// Everything one provider's detail panel draws, resolved to what is shown.
///
/// The time-dependent wording is resolved here rather than inside the panel.
/// Comparing a reference date meant every panel reported a change whenever the
/// minute ticked over, and the rail re-rendered all of them on the same run
/// loop pass that started the reveal. Comparing the resulting strings only
/// reports a change when something on screen would differ.
struct RailDetailContent: Equatable {
    let providerID: ProviderID
    let snapshots: [LimitSnapshot]
    let presentation: UsageStatusPresentation
    /// One reset line per snapshot, in the same order.
    let resetTexts: [String]
    let increasedContrast: Bool
    let nextRefreshAt: Date?
    let isRefreshing: Bool
    let accountName: String

    init(
        providerID: ProviderID,
        snapshots: [LimitSnapshot],
        status: AccountUsageStatus?,
        increasedContrast: Bool,
        nextRefreshAt: Date?,
        isRefreshing: Bool,
        referenceDate: Date,
        accountName: String,
    ) {
        self.providerID = providerID
        self.snapshots = snapshots
        presentation = status.map {
            UsageStatusPresentation.resolve($0, referenceDate: referenceDate)
        } ?? .missing(isLoading: isRefreshing)
        resetTexts = snapshots.map { snapshot in
            QuotaResetText.description(
                resetsAt: snapshot.resetsAt,
                relativeTo: referenceDate,
            )
        }
        self.increasedContrast = increasedContrast
        self.nextRefreshAt = nextRefreshAt
        self.isRefreshing = isRefreshing
        self.accountName = accountName
    }

    /// The panel height this content needs. Each hosted panel is sized to its
    /// own content, so a change in the visible panel's height never touches
    /// the other panels' frames.
    var panelHeight: CGFloat {
        EdgeRailGeometry.detailHeight(quotaCount: snapshots.count)
    }
}

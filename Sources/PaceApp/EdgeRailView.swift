import AppKit
import PaceCore
import SwiftUI

enum EdgeRailGeometry {
    static let maximumProviderRows = 5

    static var canvasSize: NSSize {
        NSSize(
            width: railOriginX + railWidth,
            height: canvasHeight(providerCount: maximumProviderRows),
        )
    }

    static func canvasHeight(providerCount: Int) -> CGFloat {
        let rows = max(providerCount, 1)
        let lastRing = firstProviderCenterY + CGFloat(rows - 1) * providerPitch
        return lastRing + trailingSpace
    }

    static let firstProviderCenterY: CGFloat = 92

    static var providerPitch: CGFloat {
        44 + 27.0 * 44 / 117 + 17 + 83.5 * 44 / 117
    }

    static var trailingSpace: CGFloat {
        railWidth * 2
    }

    static let referenceDisplayScale = CGFloat(RailScale.canvasFraction)

    static func displayScale(for preferences: PacePreferences) -> CGFloat {
        referenceDisplayScale * preferences.railScale.multiplier
    }

    static let railWidth: CGFloat = 70
    static let detailWidth: CGFloat = 262
    static let connectorWidth: CGFloat = 28

    static let maximumDetailQuotaRows = 5
    static let railOriginX = detailWidth + connectorWidth
    static let railTopY: CGFloat = 30
    static func providerCentersY(count: Int) -> [CGFloat] {
        (0 ..< max(count, 0)).map { index in
            firstProviderCenterY + CGFloat(index) * providerPitch
        }
    }

    static func providerTopY(count: Int) -> [CGFloat] {
        providerCentersY(count: count).map { $0 - ringDiameter / 2 }
    }

    static let providerRowHeight: CGFloat = 72
    static let ringDiameter: CGFloat = 44
    static let markDiameter: CGFloat = 21

    static func detailPanelY(centerY: CGFloat, height: CGFloat) -> CGFloat {
        min(max(centerY - height / 2, 0), canvasSize.height - height)
    }
}

struct EdgeRailView: View {
    @Bindable var model: PacePresentationModel
    let bridge: RailSurfaceBridge
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let ids = Array(model.visibleProviderIDs.prefix(EdgeRailGeometry.maximumProviderRows))
        let highContrast = contrast == .increased || model.forcesIncreasedContrast
        let contents = ids.map { providerID in
            let account = model.selectedAccount(for: providerID)
            return RailDetailContent(
                providerID: providerID,
                snapshots: account.map { model.snapshots(for: $0.id) } ?? [],
                status: account.map(model.usageStatus(for:)),
                increasedContrast: highContrast,
                nextRefreshAt: model.nextRefreshAt,
                isRefreshing: model.isRefreshing || model.isPerformingFirstRefresh,
                referenceDate: model.presentationReferenceDate.rounded(toNearest: 60),
                accountName: account.map(model.displayName(for:)) ?? "no account",
            )
        }
        let rows = ids.map { providerID in
            RailProviderContent(
                id: providerID,
                usage: model.headlineUsage(for: providerID),
                status: model.selectedAccount(for: providerID).map(model.usageStatus(for:)),
                increasedContrast: highContrast,
            )
        }
        RailSurfaceRepresentable(
            state: RailSurfaceState(
                rows: rows,
                contents: contents,
                preview: model.railPreviewState,
                edge: model.preferences.railEdge,
                reducesMotion: reducesMotion,
            ),
            bridge: bridge,
            selectProvider: model.showRailDetails,
            openSettings: { openSettings() },
        )
        .frame(width: EdgeRailGeometry.canvasSize.width, height: EdgeRailGeometry.canvasSize.height)
        .scaleEffect(
            EdgeRailGeometry.displayScale(for: model.preferences),
            anchor: model.preferences.railEdge == .right ? .trailing : .leading,
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pace edge usage rail")
        .onReceive(NotificationCenter.default.publisher(for: .paceOpenSettings)) { _ in
            openSettings()
        }
    }
}

struct EdgeProviderRow: View {
    let providerID: ProviderID
    let usage: Double?
    let status: AccountUsageStatus?
    let increasedContrast: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        let style = ProviderStyle.resolve(providerID)
        let presentation = status.map { UsageStatusPresentation.resolve($0) }
        Button(action: action) {
            VStack(spacing: 27 * 44 / 117) {
                ZStack {
                    ProgressRingLayerRepresentable(
                        fraction: usage ?? 0,
                        // The reference accent encodes remaining headroom, not
                        // provider identity.
                        color: UsageLevelPalette.accent(forFraction: usage),
                        increasedContrast: increasedContrast,
                        reducesMotion: reducesMotion,
                    )
                    .frame(
                        width: EdgeRailGeometry.ringDiameter,
                        height: EdgeRailGeometry.ringDiameter,
                    )

                    // The mark carries the provider's identity; the arc around
                    // it carries usage level. Colouring the arc by brand would
                    // lose the at-a-glance reading of which quota is nearly
                    // exhausted.
                    ProviderMark(
                        providerID: providerID,
                        color: .white,
                        size: EdgeRailGeometry.markDiameter,
                    )
                }
                if let usage {
                    Text(usage, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(
                            reducesMotion ? nil : .spring(response: 0.9, dampingFraction: 0.9),
                            value: usage,
                        )
                } else {
                    Text("—")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            usage.map { "\(style.name), \(Int($0 * 100)) percent used" }
                ?? "\(style.name), \(presentation?.title ?? "usage unavailable")",
        )
    }
}

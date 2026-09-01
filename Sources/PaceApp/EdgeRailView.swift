import AppKit
import PaceCore
import SwiftUI

enum EdgeRailGeometry {
    static let canvasSize = NSSize(width: 324, height: 416)
    static let displayScale: CGFloat = 0.86
    static let railWidth: CGFloat = 70
    static let detailWidth: CGFloat = 226
    static let connectorWidth: CGFloat = 28

    /// The panel is only as tall as its content. A fixed height leaves an empty
    /// band under an account that reports fewer quotas than the maximum, which
    /// the reference never shows.
    static let detailChromeHeight: CGFloat = 71
    static let detailQuotaRowHeight: CGFloat = 38
    static let detailEmptyStateHeight: CGFloat = 56
    static let maximumDetailQuotaRows = 3
    static let railOriginX = detailWidth + connectorWidth
    static let railTopY: CGFloat = 30
    /// Ring centres use the reference's measured 1.4748 pitch-to-width ratio,
    /// which is 103.2 pt on a 70 pt rail.
    static let providerCentersY: [CGFloat] = [92, 195.2, 298.5]
    /// Each ring row is centred on its provider centre.
    static var providerTopY: [CGFloat] {
        providerCentersY.map { $0 - providerRowHeight / 2 }
    }

    /// Ring top to percentage baseline measures 135 px on a 139 px rail.
    static let providerRowHeight: CGFloat = 68
    /// The running reference application draws an 87 px ring track on a 139 px
    /// rail, so 0.626 of the rail's width.
    static let ringDiameter: CGFloat = railWidth * 0.6259
    /// Reference provider mark fills roughly 0.42 of the ring's outer diameter.
    static let markDiameter: CGFloat = 21

    /// The panel height for an account reporting `quotaCount` quotas.
    static func detailHeight(quotaCount: Int) -> CGFloat {
        let rows = min(quotaCount, maximumDetailQuotaRows)
        let body = rows == 0
            ? detailEmptyStateHeight
            : CGFloat(rows) * detailQuotaRowHeight
        return detailChromeHeight + body
    }

    /// The panel's top edge for a detail of `height` attached to a ring at
    /// `centerY`, clamped so it stays inside the canvas.
    static func detailPanelY(centerY: CGFloat, height: CGFloat) -> CGFloat {
        min(max(centerY - height / 2, 0), canvasSize.height - height)
    }
}

struct EdgeRailView: View {
    @Bindable var model: PacePresentationModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.openSettings) private var openSettings
    @State private var isSettingsHovered = false

    var body: some View {
        let providerIDs = Array(model.visibleProviderIDs.prefix(3))
        let isExpanded = model.railPreviewState != .mini
        ZStack(alignment: .topLeading) {
            RailShellLayerRepresentable(
                state: RailShellState(
                    previewState: model.railPreviewState,
                    edge: model.preferences.railEdge,
                    detailCenterY: detailCenterY(providerIDs: providerIDs),
                    detailHeight: detailHeight(
                        providerID: model.railPreviewState.detailProviderID,
                        contents: detailContents(providerIDs: providerIDs),
                    ),
                    showsSettingsCircle: isSettingsHovered,
                    reducesMotion: accessibilityReduceMotion,
                ),
            )

            providerRows(providerIDs: providerIDs)
                .opacity(isExpanded ? 1 : 0)
                .animation(contentAnimation(isVisible: isExpanded), value: isExpanded)
                .accessibilityHidden(!isExpanded)

            settingsMark
                .opacity(isExpanded ? 1 : 0)
                .animation(contentAnimation(isVisible: isExpanded), value: isExpanded)
                .accessibilityHidden(!isExpanded)

            detailContent(providerIDs: providerIDs)
        }
        .scaleEffect(
            EdgeRailGeometry.displayScale,
            anchor: model.preferences.railEdge == .right ? .trailing : .leading,
        )
        .frame(
            width: EdgeRailGeometry.canvasSize.width,
            height: EdgeRailGeometry.canvasSize.height,
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pace edge usage rail")
        .onReceive(NotificationCenter.default.publisher(for: .paceOpenSettings)) { _ in
            openSettings()
        }
    }

    private func providerRows(providerIDs: [ProviderID]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(providerIDs.enumerated()), id: \.element) { index, providerID in
                let account = model.selectedAccount(for: providerID)
                let status = account.map(model.usageStatus(for:))
                EdgeProviderRow(
                    providerID: providerID,
                    usage: model.headlineUsage(for: providerID),
                    status: status,
                    increasedContrast: usesIncreasedContrast,
                    action: {
                        model.showRailDetails(for: providerID)
                    },
                )
                .frame(
                    width: EdgeRailGeometry.railWidth,
                    height: EdgeRailGeometry.providerRowHeight,
                )
                .offset(
                    x: railContentOriginX,
                    y: EdgeRailGeometry.providerTopY[index],
                )
            }
        }
        .frame(
            width: EdgeRailGeometry.canvasSize.width,
            height: EdgeRailGeometry.canvasSize.height,
            alignment: .topLeading,
        )
    }

    /// The settings control.
    ///
    /// At rest the reference shows only the shell's arc, with no glyph. The
    /// gear and its filled circle are the hover state, so the glyph fades in
    /// with the pointer rather than sitting on the resting silhouette.
    private var settingsMark: some View {
        let circle = RailShellMetrics.settingsCircleRect
        return Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: RailShellMetrics.settingsGlyphSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: circle.width, height: circle.height)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .opacity(isSettingsHovered ? 1 : 0)
        .animation(
            .easeOut(duration: RailMotion.contentFadeDuration),
            value: isSettingsHovered,
        )
        .onHover { isHovering in
            isSettingsHovered = isHovering
        }
        .offset(x: settingsOriginX, y: circle.minY)
        .accessibilityLabel("Pace settings")
    }

    private func detailContents(providerIDs: [ProviderID]) -> [RailDetailContent] {
        providerIDs.map { contentProviderID in
            let account = model.selectedAccount(for: contentProviderID)
            return RailDetailContent(
                providerID: contentProviderID,
                account: account,
                snapshots: account.map { model.snapshots(for: $0.id) } ?? [],
                status: account.map(model.usageStatus(for:)),
                increasedContrast: usesIncreasedContrast,
            )
        }
    }

    private func detailContent(providerIDs: [ProviderID]) -> some View {
        let providerID = model.railPreviewState.detailProviderID
        let contents = detailContents(providerIDs: providerIDs)
        let centerY = detailCenterY(providerIDs: providerIDs) ?? 92
        let panelHeight = detailHeight(providerID: providerID, contents: contents)
        return RailDetailContentLayerRepresentable(
            contents: contents,
            visibleProviderID: providerID,
            edge: model.preferences.railEdge,
            panelY: EdgeRailGeometry.detailPanelY(centerY: centerY, height: panelHeight),
            panelHeight: panelHeight,
            reducesMotion: accessibilityReduceMotion,
        )
        .frame(
            width: EdgeRailGeometry.canvasSize.width,
            height: EdgeRailGeometry.canvasSize.height,
        )
        .accessibilityHidden(providerID == nil)
    }

    /// Keeps the shell path and the hosted content on one height. While the
    /// panel is hidden it retains the last shown provider's height so the
    /// dismissal animation does not resize mid-flight.
    private func detailHeight(
        providerID: ProviderID?,
        contents: [RailDetailContent],
    ) -> CGFloat {
        let content = providerID.flatMap { shownProviderID in
            contents.first { $0.providerID == shownProviderID }
        }
        return EdgeRailGeometry.detailHeight(quotaCount: content?.snapshots.count ?? 0)
    }

    private func detailCenterY(providerIDs: [ProviderID]) -> CGFloat? {
        guard let providerID = model.railPreviewState.detailProviderID,
              let index = providerIDs.firstIndex(of: providerID),
              EdgeRailGeometry.providerCentersY.indices.contains(index)
        else {
            return nil
        }
        return EdgeRailGeometry.providerCentersY[index]
    }

    private var railContentOriginX: CGFloat {
        model.preferences.railEdge == .right ? EdgeRailGeometry.railOriginX : 0
    }

    /// Mirrors the shell's settings circle so the glyph stays centred in it on
    /// either edge.
    private var settingsOriginX: CGFloat {
        let circle = RailShellMetrics.settingsCircleRect
        return model.preferences.railEdge == .right
            ? circle.minX
            : EdgeRailGeometry.canvasSize.width - circle.maxX
    }

    private var usesIncreasedContrast: Bool {
        colorSchemeContrast == .increased || model.forcesIncreasedContrast
    }

    private func contentAnimation(isVisible: Bool) -> Animation {
        let duration = accessibilityReduceMotion
            ? RailMotion.reducedMotionFadeDuration
            : isVisible
            ? RailMotion.contentFadeDuration
            : RailMotion.contentDismissDuration
        let animation = Animation.easeOut(duration: duration)
        return isVisible && !accessibilityReduceMotion
            ? animation.delay(RailMotion.contentRevealDelay)
            : animation
    }
}

private struct EdgeProviderRow: View {
    let providerID: ProviderID
    let usage: Double?
    let status: AccountUsageStatus?
    let increasedContrast: Bool
    let action: () -> Void

    var body: some View {
        let style = ProviderStyle.resolve(providerID)
        let presentation = status.map { UsageStatusPresentation.resolve($0) }
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    ProgressRingLayerRepresentable(
                        fraction: usage ?? 0,
                        // The reference accent encodes remaining headroom, not
                        // provider identity.
                        color: UsageLevelPalette.accent(forFraction: usage),
                        increasedContrast: increasedContrast,
                    )
                    .frame(
                        width: EdgeRailGeometry.ringDiameter,
                        height: EdgeRailGeometry.ringDiameter,
                    )

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

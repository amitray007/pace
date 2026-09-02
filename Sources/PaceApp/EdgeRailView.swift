import AppKit
import PaceCore
import SwiftUI

enum EdgeRailGeometry {
    /// The most provider rows the rail will show at once.
    ///
    /// Pace supports five providers, and the rail sizes itself to however many
    /// have accounts rather than to a fixed three.
    static let maximumProviderRows = 5

    /// The transparent canvas the rail is drawn inside.
    ///
    /// Its height follows the number of provider rows, plus the space the
    /// contour and the settings arc need below the last ring. Its width is
    /// derived from the parts it has to hold rather than stated: a literal
    /// width silently disagreed with `railOriginX` when the detail panel grew,
    /// which pushed the rail off the canvas and left the panel unattached.
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

    /// Where the first provider ring sits, measured from the canvas top.
    static let firstProviderCenterY: CGFloat = 92

    /// Distance between adjacent ring centres, from the reference's measured
    /// 1.4748 pitch-to-width ratio.
    static var providerPitch: CGFloat {
        railWidth * 1.4748
    }

    /// Room below the last ring for the bottom contour and the settings arc.
    static var trailingSpace: CGFloat {
        railWidth * 1.7
    }

    /// The fraction of the canvas the reference rail fills at the `medium`
    /// scale step.
    static let referenceDisplayScale = CGFloat(RailScale.canvasFraction)

    /// The rail's on-screen scale for a set of preferences.
    ///
    /// The visual panel and the pointer's hit regions must agree on this, or
    /// the rail would accept clicks where it is not drawn.
    static func displayScale(for preferences: PacePreferences) -> CGFloat {
        referenceDisplayScale * preferences.railScale.multiplier
    }

    static let railWidth: CGFloat = 70
    /// Wide enough for a quota label and its reset time on one line without
    /// either truncating. The reference panel is proportionally wider than the
    /// rail it attaches to, and at the previous 226 the type had to be shrunk
    /// far enough that the title, rows, and footer no longer read as one scale.
    static let detailWidth: CGFloat = 262
    static let connectorWidth: CGFloat = 28

    /// The panel is only as tall as its content. A fixed height leaves an empty
    /// band under an account that reports fewer quotas than the maximum, which
    /// the reference never shows.
    /// Everything in the panel that is not a quota row: the header, the
    /// divider, the footer line, and the vertical padding above and below.
    /// Under-budgeting this does not clip anything, it squeezes the header and
    /// footer against the rounded border instead.
    static let detailChromeHeight: CGFloat = 86
    static let detailQuotaRowHeight: CGFloat = 43
    static let detailEmptyStateHeight: CGFloat = 62
    static let maximumDetailQuotaRows = 3
    static let railOriginX = detailWidth + connectorWidth
    static let railTopY: CGFloat = 30
    /// Ring centres for the rows currently shown.
    ///
    /// Generated from the measured pitch rather than listed, so the rail can
    /// show however many providers have accounts.
    static func providerCentersY(count: Int) -> [CGFloat] {
        (0 ..< max(count, 0)).map { index in
            firstProviderCenterY + CGFloat(index) * providerPitch
        }
    }

    /// Each ring row is centred on its provider centre.
    static func providerTopY(count: Int) -> [CGFloat] {
        providerCentersY(count: count).map { $0 - providerRowHeight / 2 }
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
        let providerIDs = Array(
            model.visibleProviderIDs.prefix(EdgeRailGeometry.maximumProviderRows),
        )
        let isExpanded = model.railPreviewState != .mini
        let contents = detailContents(providerIDs: providerIDs)
        let shellState = RailShellState(
            providerRowCount: providerIDs.count,
            previewState: model.railPreviewState,
            edge: model.preferences.railEdge,
            detailCenterY: detailCenterY(providerIDs: providerIDs),
            detailHeight: detailHeight(
                providerID: model.railPreviewState.detailProviderID,
                contents: contents,
            ),
            showsSettingsCircle: isSettingsHovered,
            reducesMotion: accessibilityReduceMotion,
        )
        ZStack(alignment: .topLeading) {
            RailShellLayerRepresentable(state: shellState)

            // Clipped to the shell so the rings can only be seen where the
            // silhouette already is. Without it they faded in at their final
            // positions while the shape was still growing toward them, which
            // read as content arriving rather than the handle expanding.
            //
            // The mask is a second instance of the shell view itself, fed the
            // same state. Its opaque fills are the mask's alpha, its paths are
            // the shell's paths in the shell's coordinate space, and its
            // animations run through the same code with the same retargeting,
            // so the two silhouettes cannot drift apart or fall out of step.
            //
            // Only the rail's own contents are masked. The detail panel is
            // hosted by its own layer and appears with its shell rather than
            // growing, so it has nothing to be revealed through.
            ZStack(alignment: .topLeading) {
                providerRows(providerIDs: providerIDs)
                    .opacity(isExpanded ? 1 : 0)
                    .animation(contentAnimation(isVisible: isExpanded), value: isExpanded)
                    .accessibilityHidden(!isExpanded)

                settingsMark
                    .opacity(isExpanded ? 1 : 0)
                    .animation(contentAnimation(isVisible: isExpanded), value: isExpanded)
                    .accessibilityHidden(!isExpanded)
            }
            // The shell flips its paths against its own bounds, so the group
            // must be the full canvas or the mask lands in the wrong place and
            // clips the rows it is meant to reveal.
            .frame(
                width: EdgeRailGeometry.canvasSize.width,
                height: EdgeRailGeometry.canvasSize.height,
                alignment: .topLeading,
            )
            .mask(RailShellLayerRepresentable(state: shellState))

            detailContent(providerIDs: providerIDs, contents: contents)
        }
        .scaleEffect(
            EdgeRailGeometry.displayScale(for: model.preferences),
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
                    y: EdgeRailGeometry.providerTopY(count: providerIDs.count)[index],
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
    /// At rest the reference shows only the shell's small arc, with no glyph.
    /// The gear and its filled circle are the hover state, so the glyph fades
    /// in with the pointer rather than sitting on the resting silhouette. The
    /// hover region is larger than the arc it reveals from, so the control can
    /// be found by moving toward it rather than by hitting it exactly.
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
            RailMotion.contentTiming(
                duration: RailMotion.Transition.reveal.contentDuration,
            ),
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
                snapshots: account.map { model.snapshots(for: $0.id) } ?? [],
                status: account.map(model.usageStatus(for:)),
                increasedContrast: usesIncreasedContrast,
                nextRefreshAt: model.nextRefreshAt,
                // The startup refresh counts as refreshing here. The rail has
                // no other way to say that stored numbers are being replaced.
                isRefreshing: model.isRefreshing || model.isPerformingFirstRefresh,
                referenceDate: model.presentationReferenceDate
                    .rounded(toNearest: 60),
                accountName: account.map(model.displayName(for:)) ?? "no account",
            )
        }
    }

    private func detailContent(
        providerIDs: [ProviderID],
        contents: [RailDetailContent],
    ) -> some View {
        let providerID = model.railPreviewState.detailProviderID
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
              EdgeRailGeometry.providerCentersY(count: providerIDs.count)
                  .indices.contains(index)
        else {
            return nil
        }
        return EdgeRailGeometry.providerCentersY(count: providerIDs.count)[index]
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
            ? RailMotion.Transition.reveal.contentDuration
            : RailMotion.contentDismissDuration
        let animation = RailMotion.contentTiming(duration: duration)
        return isVisible && !accessibilityReduceMotion
            ? animation.delay(RailMotion.Transition.reveal.contentDelay)
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

                    // The mark carries the provider's identity; the arc around
                    // it carries usage level. Colouring the arc by brand would
                    // lose the at-a-glance reading of which quota is nearly
                    // exhausted.
                    ProviderMark(
                        providerID: providerID,
                        color: style.accent,
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

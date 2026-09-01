import AppKit
import PaceCore
import SwiftUI

enum EdgeRailGeometry {
    static let canvasSize = NSSize(width: 324, height: 416)
    static let railWidth: CGFloat = 70
    static let detailWidth: CGFloat = 226
    static let connectorWidth: CGFloat = 28
    static let railOriginX = detailWidth + connectorWidth
    static let railTopY: CGFloat = 30
    static let providerCentersY: [CGFloat] = [92, 194, 297]
    static let providerTopY: [CGFloat] = [60, 162, 265]
}

struct EdgeRailView: View {
    @Bindable var model: PacePresentationModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let providerIDs = Array(model.visibleProviderIDs.prefix(3))
        let isExpanded = model.railPreviewState != .mini
        ZStack(alignment: .topLeading) {
            RailShellLayerRepresentable(
                previewState: model.railPreviewState,
                edge: model.preferences.railEdge,
                detailCenterY: detailCenterY(providerIDs: providerIDs),
                reducesMotion: accessibilityReduceMotion,
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
                .frame(width: EdgeRailGeometry.railWidth, height: 64)
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

    private var settingsMark: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .offset(x: settingsOriginX, y: 367)
        .accessibilityLabel("Pace settings")
    }

    private func detailContent(providerIDs: [ProviderID]) -> some View {
        let providerID = model.railPreviewState.detailProviderID
        let account = providerID.flatMap { model.selectedAccount(for: $0) }
        let status = account.map(model.usageStatus(for:))
        let centerY = detailCenterY(providerIDs: providerIDs) ?? 92
        let panelY = min(max(centerY - 69.5, 0), 205)
        return RailDetailContentLayerRepresentable(
            providerID: providerID,
            account: account,
            snapshots: account.map { model.snapshots(for: $0.id) } ?? [],
            status: status,
            edge: model.preferences.railEdge,
            panelY: panelY,
            reducesMotion: accessibilityReduceMotion,
            increasedContrast: usesIncreasedContrast,
        )
        .frame(
            width: EdgeRailGeometry.canvasSize.width,
            height: EdgeRailGeometry.canvasSize.height,
        )
        .accessibilityHidden(providerID == nil)
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

    private var settingsOriginX: CGFloat {
        model.preferences.railEdge == .right ? EdgeRailGeometry.railOriginX + 10 : 10
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
            VStack(spacing: 8) {
                ZStack {
                    ProgressRingLayerRepresentable(
                        fraction: usage ?? 0,
                        color: usage == nil
                            ? NSColor.secondaryLabelColor
                            : style.accentColor,
                        increasedContrast: increasedContrast,
                    )
                    .frame(width: 40, height: 40)

                    ProviderMark(providerID: providerID, color: .white, size: 13)
                }
                if let usage {
                    Text(usage, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                } else {
                    Text("—")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
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

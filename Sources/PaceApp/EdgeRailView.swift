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
    }

    private func providerRows(providerIDs: [ProviderID]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(providerIDs.enumerated()), id: \.element) { index, providerID in
                EdgeProviderRow(
                    providerID: providerID,
                    usage: model.headlineUsage(for: providerID) ?? 0,
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
        Image(systemName: "gearshape")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 50, height: 50)
            .offset(x: settingsOriginX, y: 367)
            .accessibilityLabel("Pace settings")
    }

    private func detailContent(providerIDs: [ProviderID]) -> some View {
        let providerID = model.railPreviewState.detailProviderID
        let account = providerID.flatMap { model.selectedAccount(for: $0) }
        let centerY = detailCenterY(providerIDs: providerIDs) ?? 92
        let panelY = min(max(centerY - 69.5, 0), 205)
        return RailDetailContentLayerRepresentable(
            providerID: providerID,
            account: account,
            snapshots: account.map { model.snapshots(for: $0.id) } ?? [],
            edge: model.preferences.railEdge,
            panelY: panelY,
            reducesMotion: accessibilityReduceMotion,
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
    let usage: Double

    var body: some View {
        let style = ProviderStyle.resolve(providerID)
        VStack(spacing: 8) {
            ZStack {
                ProgressRingLayerRepresentable(
                    fraction: usage,
                    color: style.accentColor,
                )
                .frame(width: 40, height: 40)

                ProviderMark(providerID: providerID, color: .white, size: 13)
            }
            Text(usage, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(style.name), \(Int(usage * 100)) percent used",
        )
    }
}

private struct EdgeDetailPanel: View {
    let providerID: ProviderID
    let account: ProviderAccount?
    let snapshots: [LimitSnapshot]

    var body: some View {
        let style = ProviderStyle.resolve(providerID)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                ProviderMark(providerID: providerID, color: .white, size: 10)
                Text("\(style.name) Usage")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(account?.displayName ?? "No account")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ForEach(snapshots.prefix(2)) { snapshot in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(snapshot.label)
                        Spacer()
                        Text(snapshot.usedFraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.system(size: 8.5, weight: .medium))

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                            Capsule()
                                .fill(style.accent)
                                .frame(width: proxy.size.width * min(snapshot.usedFraction, 1))
                        }
                    }
                    .frame(height: 3)

                    Text(resetText(for: snapshot))
                        .font(.system(size: 7.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            Divider()
                .overlay(Color.white.opacity(0.14))

            HStack(spacing: 8) {
                Text(account?.planName ?? "Plan unavailable")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(observationText)
                    .lineLimit(1)
            }
            .font(.system(size: 7.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(style.name) usage for \(account?.displayName ?? "no account")")
    }

    private func resetText(for snapshot: LimitSnapshot) -> String {
        guard let resetsAt = snapshot.resetsAt else {
            return "Reset unavailable"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relativeReset = formatter.localizedString(
            for: resetsAt,
            relativeTo: SimulatedScenarios.referenceDate,
        )
        return "Resets \(relativeReset)"
    }

    private var observationText: String {
        guard let latestObservation = snapshots.map(\.observedAt).max() else {
            return "Not observed"
        }
        let prefix = snapshots.allSatisfy { $0.freshness == .current } ? "Observed" : "Stale"
        return "\(prefix) \(latestObservation.formatted(date: .omitted, time: .shortened))"
    }
}

private struct RailDetailContentLayerRepresentable: NSViewRepresentable {
    let providerID: ProviderID?
    let account: ProviderAccount?
    let snapshots: [LimitSnapshot]
    let edge: RailEdge
    let panelY: CGFloat
    let reducesMotion: Bool

    private var state: RailDetailContentState {
        RailDetailContentState(
            providerID: providerID,
            account: account,
            snapshots: snapshots,
            edge: edge,
            panelY: panelY,
            reducesMotion: reducesMotion,
        )
    }

    func makeNSView(context _: Context) -> RailDetailContentLayerView {
        RailDetailContentLayerView()
    }

    func updateNSView(_ view: RailDetailContentLayerView, context _: Context) {
        view.update(state)
    }
}

private struct RailDetailContentState {
    let providerID: ProviderID?
    let account: ProviderAccount?
    let snapshots: [LimitSnapshot]
    let edge: RailEdge
    let panelY: CGFloat
    let reducesMotion: Bool
}

private final class RailDetailContentLayerView: NSView {
    private let contentView = NSHostingView(rootView: AnyView(EmptyView()))
    private var providerID: ProviderID?
    private var hasReceivedState = false

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        contentView.wantsLayer = true
        contentView.layer?.actions = [
            "position": NSNull(),
            "opacity": NSNull(),
        ]
        contentView.layer?.opacity = 0
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func update(_ state: RailDetailContentState) {
        let previousProviderID = providerID
        let layer = contentView.layer
        let currentPosition = layer?.presentation()?.position ?? layer?.position
        let currentOpacity = layer?.presentation()?.opacity ?? layer?.opacity ?? 0

        if let nextProviderID = state.providerID {
            contentView.rootView = AnyView(
                EdgeDetailPanel(
                    providerID: nextProviderID,
                    account: state.account,
                    snapshots: state.snapshots,
                ),
            )
            contentView.frame = targetFrame(edge: state.edge, panelY: state.panelY)
        }

        let targetPosition = layer?.position
        let isVisible = state.providerID != nil
        let shouldAnimate = hasReceivedState && previousProviderID != state.providerID
        providerID = state.providerID
        hasReceivedState = true
        setModelOpacity(isVisible ? 1 : 0, on: layer)

        guard shouldAnimate, let layer else {
            layer?.removeAnimation(forKey: "pace.detailPosition")
            layer?.removeAnimation(forKey: "pace.detailOpacity")
            return
        }

        let shouldAnimatePosition = !state.reducesMotion && isVisible &&
            previousProviderID != nil && currentPosition != targetPosition
        animatePosition(
            on: layer,
            from: currentPosition,
            to: targetPosition,
            enabled: shouldAnimatePosition,
        )
        animateOpacity(
            on: layer,
            from: currentOpacity,
            isVisible: isVisible,
            isReveal: previousProviderID == nil,
            reducesMotion: state.reducesMotion,
        )
    }

    private func animatePosition(
        on layer: CALayer,
        from currentPosition: CGPoint?,
        to targetPosition: CGPoint?,
        enabled: Bool,
    ) {
        guard enabled, let currentPosition, let targetPosition else {
            layer.removeAnimation(forKey: "pace.detailPosition")
            return
        }
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = currentPosition
        animation.toValue = targetPosition
        animation.duration = RailMotion.detailDuration
        animation.timingFunction = RailMotion.timingFunction
        layer.add(animation, forKey: "pace.detailPosition")
    }

    private func animateOpacity(
        on layer: CALayer,
        from currentOpacity: Float,
        isVisible: Bool,
        isReveal: Bool,
        reducesMotion: Bool,
    ) {
        let targetOpacity: Float = isVisible ? 1 : 0
        guard currentOpacity != targetOpacity else {
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = currentOpacity
        animation.toValue = targetOpacity
        animation.duration = reducesMotion
            ? RailMotion.reducedMotionFadeDuration
            : isVisible
            ? RailMotion.contentFadeDuration
            : RailMotion.contentDismissDuration
        animation.timingFunction = RailMotion.timingFunction
        if isVisible, isReveal, !reducesMotion {
            animation.beginTime = CACurrentMediaTime() + RailMotion.contentRevealDelay
            animation.fillMode = .backwards
        }
        layer.add(animation, forKey: "pace.detailOpacity")
    }

    private func setModelOpacity(_ opacity: Float, on layer: CALayer?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = opacity
        CATransaction.commit()
    }

    private func targetFrame(edge: RailEdge, panelY: CGFloat) -> CGRect {
        let originX = edge == .right
            ? 0
            : EdgeRailGeometry.canvasSize.width - EdgeRailGeometry.detailWidth
        return CGRect(
            x: originX,
            y: panelY,
            width: EdgeRailGeometry.detailWidth,
            height: 139,
        )
    }
}

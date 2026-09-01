import AppKit
import PaceCore
import SwiftUI

private struct EdgeDetailPanel: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let providerID: ProviderID
    let account: ProviderAccount?
    let snapshots: [LimitSnapshot]
    let status: AccountUsageStatus?
    let increasedContrast: Bool

    var body: some View {
        let style = ProviderStyle.resolve(providerID)
        let presentation = status.map { UsageStatusPresentation.resolve($0) } ??
            UsageStatusPresentation(
                title: "No account configured",
                detail: "Add an account for this provider to see usage.",
                symbolName: "person.crop.circle.badge.questionmark",
                severity: .neutral,
                observationText: "Not observed",
            )
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

            if snapshots.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: presentation.symbolName)
                        .foregroundStyle(presentation.color)
                    Text(presentation.title)
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(presentation.detail)
                        .font(.system(size: 7.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                quotaRows(style: style)
            }
            Spacer(minLength: 0)

            Divider()
                .overlay(Color.white.opacity(0.14))

            HStack(spacing: 8) {
                Text(footerTitle(presentation))
                    .lineLimit(1)
                    .foregroundStyle(footerColor(presentation))
                Spacer(minLength: 4)
                Text(presentation.observationText)
                    .lineLimit(1)
            }
            .font(.system(size: 7.5, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(style.name) usage for \(account?.displayName ?? "no account"). " +
                "\(presentation.title). \(presentation.detail)",
        )
    }

    private func quotaRows(style: ProviderStyle) -> some View {
        ForEach(snapshots.prefix(2)) { snapshot in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snapshot.label)
                    Spacer()
                    Text(
                        snapshot.usedFraction,
                        format: .percent.precision(.fractionLength(0)),
                    )
                    .monospacedDigit()
                }
                .font(.system(size: 8.5, weight: .medium))

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(
                            Color.white.opacity(usesIncreasedContrast ? 0.34 : 0.14),
                        )
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
    }

    private func footerTitle(_ presentation: UsageStatusPresentation) -> String {
        snapshots.isEmpty || presentation.severity == .positive
            ? account?.planName ?? "Plan unavailable"
            : presentation.title
    }

    private var usesIncreasedContrast: Bool {
        colorSchemeContrast == .increased || increasedContrast
    }

    private func footerColor(_ presentation: UsageStatusPresentation) -> Color {
        snapshots.isEmpty || presentation.severity == .positive
            ? .secondary
            : presentation.color
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
}

struct RailDetailContentLayerRepresentable: NSViewRepresentable {
    let providerID: ProviderID?
    let account: ProviderAccount?
    let snapshots: [LimitSnapshot]
    let status: AccountUsageStatus?
    let edge: RailEdge
    let panelY: CGFloat
    let reducesMotion: Bool
    let increasedContrast: Bool

    private var state: RailDetailContentState {
        RailDetailContentState(
            providerID: providerID,
            account: account,
            snapshots: snapshots,
            status: status,
            edge: edge,
            panelY: panelY,
            reducesMotion: reducesMotion,
            increasedContrast: increasedContrast,
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
    let status: AccountUsageStatus?
    let edge: RailEdge
    let panelY: CGFloat
    let reducesMotion: Bool
    let increasedContrast: Bool
}

final class RailDetailContentLayerView: NSView {
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

    fileprivate func update(_ state: RailDetailContentState) {
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
                    status: state.status,
                    increasedContrast: state.increasedContrast,
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

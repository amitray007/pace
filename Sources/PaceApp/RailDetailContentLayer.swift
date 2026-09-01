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
            // The reference header is only the provider mark and title. The
            // account identity and plan stay in the footer so the title line
            // never truncates an address.
            HStack(spacing: 7) {
                ProviderMark(providerID: providerID, color: .white, size: 12)
                Text("\(style.name) Usage")
                    .font(.system(size: 12, weight: .bold))
                Spacer(minLength: 0)
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
                quotaRows()
            }
            Spacer(minLength: 0)

            Divider()
                .overlay(Color.white.opacity(0.14))

            HStack(spacing: 8) {
                Text(footerTitle(presentation))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(footerColor(presentation))
                Spacer(minLength: 4)
                Text(presentation.observationText)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 8, weight: .medium))
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

    /// The reference quota block puts the label and its reset time on one line,
    /// the bar beneath them, and the used percentage on its own line below the
    /// bar. Measured from `settings-claude-detail.png`.
    private func quotaRows() -> some View {
        ForEach(snapshots.prefix(2)) { snapshot in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(snapshot.label)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(resetText(for: snapshot))
                        .font(.system(size: 9))
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
                .frame(height: 3.5)

                Text(usedText(for: snapshot))
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }

    private func usedText(for snapshot: LimitSnapshot) -> String {
        let percentage = Int((min(max(snapshot.usedFraction, 0), 1) * 100).rounded())
        return "\(percentage)% Used"
    }

    /// The footer carries account identity while usage is healthy, and the
    /// status title instead when something needs attention.
    private func footerTitle(_ presentation: UsageStatusPresentation) -> String {
        guard !snapshots.isEmpty, presentation.severity == .positive else {
            return presentation.title
        }
        guard let account else {
            return "No account"
        }
        guard let planName = account.planName else {
            return account.displayName
        }
        return "\(account.displayName) · \(planName)"
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

struct RailDetailContent: Equatable {
    let providerID: ProviderID
    let account: ProviderAccount?
    let snapshots: [LimitSnapshot]
    let status: AccountUsageStatus?
    let increasedContrast: Bool
}

struct RailDetailContentLayerRepresentable: NSViewRepresentable {
    let contents: [RailDetailContent]
    let visibleProviderID: ProviderID?
    let edge: RailEdge
    let panelY: CGFloat
    let reducesMotion: Bool

    private var state: RailDetailContentState {
        RailDetailContentState(
            contents: contents,
            visibleProviderID: visibleProviderID,
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
    let contents: [RailDetailContent]
    let visibleProviderID: ProviderID?
    let edge: RailEdge
    let panelY: CGFloat
    let reducesMotion: Bool
}

final class RailDetailContentLayerView: NSView {
    private let contentContainerView = NSView()
    private var contentViews: [ProviderID: NSHostingView<AnyView>] = [:]
    private var hasReceivedState = false
    private var renderedContents: [ProviderID: RailDetailContent] = [:]
    private var visibleProviderID: ProviderID?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        contentContainerView.wantsLayer = true
        contentContainerView.layer?.actions = [
            "position": NSNull(),
            "opacity": NSNull(),
        ]
        contentContainerView.layer?.opacity = 0
        addSubview(contentContainerView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    fileprivate func update(_ state: RailDetailContentState) {
        let previousProviderID = visibleProviderID
        let layer = contentContainerView.layer
        let currentPosition = layer?.presentation()?.position ?? layer?.position
        let currentOpacity = layer?.presentation()?.opacity ?? layer?.opacity ?? 0

        contentContainerView.frame = targetFrame(edge: state.edge, panelY: state.panelY)
        reconcileContentViews(state.contents)
        updateContentVisibility(state.visibleProviderID)

        let targetPosition = layer?.position
        let isVisible = state.visibleProviderID != nil
        let shouldAnimate = hasReceivedState && previousProviderID != state.visibleProviderID
        visibleProviderID = state.visibleProviderID
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

    private func reconcileContentViews(_ contents: [RailDetailContent]) {
        let retainedProviderIDs = Set(contents.map(\.providerID))
        let removedProviderIDs = contentViews.keys.filter {
            !retainedProviderIDs.contains($0)
        }
        for providerID in removedProviderIDs {
            contentViews.removeValue(forKey: providerID)?.removeFromSuperview()
            renderedContents.removeValue(forKey: providerID)
        }

        for content in contents {
            let providerID = content.providerID
            let isNewContentView = contentViews[providerID] == nil
            let contentView = contentViews[providerID] ?? makeContentView(for: content)
            let contentChanged = renderedContents[providerID] != content
            if contentChanged {
                contentView.rootView = AnyView(detailPanel(for: content))
                renderedContents[providerID] = content
            }
            let frameChanged = contentView.frame != contentContainerView.bounds
            if frameChanged {
                contentView.frame = contentContainerView.bounds
            }
            if isNewContentView || contentChanged || frameChanged {
                contentView.layoutSubtreeIfNeeded()
                contentView.displayIfNeeded()
            }
        }
    }

    private func makeContentView(
        for content: RailDetailContent,
    ) -> NSHostingView<AnyView> {
        let contentView = NSHostingView(rootView: AnyView(detailPanel(for: content)))
        contentView.autoresizingMask = [.width, .height]
        contentContainerView.addSubview(contentView)
        contentViews[content.providerID] = contentView
        renderedContents[content.providerID] = content
        return contentView
    }

    private func detailPanel(for content: RailDetailContent) -> EdgeDetailPanel {
        EdgeDetailPanel(
            providerID: content.providerID,
            account: content.account,
            snapshots: content.snapshots,
            status: content.status,
            increasedContrast: content.increasedContrast,
        )
    }

    private func updateContentVisibility(_ providerID: ProviderID?) {
        for (contentProviderID, contentView) in contentViews {
            contentView.isHidden = contentProviderID != providerID
        }
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

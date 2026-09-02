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
    let nextRefreshAt: Date?
    let isRefreshing: Bool

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

            // The rail is ambient and sits on the desktop, so it does not carry
            // the account address. What it shows instead is when the numbers
            // above it will next change.
            HStack(spacing: 8) {
                if snapshots.isEmpty || presentation.severity != .positive {
                    Text(presentation.title)
                        .lineLimit(1)
                        .foregroundStyle(presentation.color)
                }
                Spacer(minLength: 0)
                RefreshCountdownView(
                    nextRefreshAt: nextRefreshAt,
                    isRefreshing: isRefreshing,
                    style: .sentence,
                )
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
        ForEach(snapshots.prefix(3)) { snapshot in
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

    private var usesIncreasedContrast: Bool {
        colorSchemeContrast == .increased || increasedContrast
    }

    private func resetText(for snapshot: LimitSnapshot) -> String {
        QuotaResetText.description(
            resetsAt: snapshot.resetsAt,
            relativeTo: SimulatedScenarios.referenceDate,
        )
    }
}

struct RailDetailContent: Equatable {
    let providerID: ProviderID
    let account: ProviderAccount?
    let snapshots: [LimitSnapshot]
    let status: AccountUsageStatus?
    let increasedContrast: Bool
    let nextRefreshAt: Date?
    let isRefreshing: Bool
}

struct RailDetailContentLayerRepresentable: NSViewRepresentable {
    let contents: [RailDetailContent]
    let visibleProviderID: ProviderID?
    let edge: RailEdge
    let panelY: CGFloat
    let panelHeight: CGFloat
    let reducesMotion: Bool

    private var state: RailDetailContentState {
        RailDetailContentState(
            contents: contents,
            visibleProviderID: visibleProviderID,
            edge: edge,
            panelY: panelY,
            panelHeight: panelHeight,
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
    let panelHeight: CGFloat
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

        contentContainerView.frame = targetFrame(
            edge: state.edge,
            panelY: state.panelY,
            panelHeight: state.panelHeight,
        )
        reconcileContentViews(state.contents)
        // Crossfade only when moving between two providers. Opening and closing
        // are carried by the container's own fade.
        let isProviderSwitch = hasReceivedState &&
            previousProviderID != nil &&
            state.visibleProviderID != nil &&
            previousProviderID != state.visibleProviderID
        updateContentVisibility(
            state.visibleProviderID,
            animated: isProviderSwitch,
            reducesMotion: state.reducesMotion,
        )

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
        contentView.wantsLayer = true
        contentView.layer?.actions = ["opacity": NSNull()]
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
            nextRefreshAt: content.nextRefreshAt,
            isRefreshing: content.isRefreshing,
        )
    }

    /// Crossfades between provider panels instead of swapping them.
    ///
    /// docs/interactions.md asks for content to crossfade while the shell
    /// moves. Toggling `isHidden` made the outgoing provider vanish and the
    /// incoming one appear instantly part-way through the glide, so the panel
    /// read as two separate cards rather than one that changed contents.
    private func updateContentVisibility(
        _ providerID: ProviderID?,
        animated: Bool,
        reducesMotion: Bool,
    ) {
        for (contentProviderID, contentView) in contentViews {
            let isVisible = contentProviderID == providerID
            // A hidden view is not rendered at all, so it has to stay visible
            // for its fade out to be seen.
            contentView.isHidden = false
            let target: Float = isVisible ? 1 : 0
            guard let layer = contentView.layer else {
                continue
            }
            let current = layer.presentation()?.opacity ?? layer.opacity
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = target
            CATransaction.commit()

            guard animated, current != target else {
                layer.removeAnimation(forKey: "pace.contentCrossfade")
                continue
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = current
            fade.toValue = target
            fade.duration = reducesMotion
                ? RailMotion.reducedMotionFadeDuration
                : RailMotion.Transition.detail.contentDuration
            fade.timingFunction = RailMotion.detailTimingFunction
            layer.add(fade, forKey: "pace.contentCrossfade")
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
        // The panel appears rather than fading in, so its shell and its
        // contents can never arrive at different times.
        guard RailMotion.animatesDetailAppearance || !isReveal else {
            layer.removeAnimation(forKey: "pace.detailOpacity")
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = currentOpacity
        animation.toValue = targetOpacity
        animation.duration = reducesMotion
            ? RailMotion.reducedMotionFadeDuration
            : RailMotion.contentDismissDuration
        animation.timingFunction = RailMotion.timingFunction
        layer.add(animation, forKey: "pace.detailOpacity")
    }

    private func setModelOpacity(_ opacity: Float, on layer: CALayer?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = opacity
        CATransaction.commit()
    }

    private func targetFrame(
        edge: RailEdge,
        panelY: CGFloat,
        panelHeight: CGFloat,
    ) -> CGRect {
        let originX = edge == .right
            ? 0
            : EdgeRailGeometry.canvasSize.width - EdgeRailGeometry.detailWidth
        return CGRect(
            x: originX,
            y: panelY,
            width: EdgeRailGeometry.detailWidth,
            height: panelHeight,
        )
    }
}

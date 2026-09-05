import AppKit
import PaceCore
import QuartzCore
import SwiftUI

struct RailProviderContent: Equatable {
    let id: ProviderID
    let usage: Double?
    let status: AccountUsageStatus?
    let increasedContrast: Bool
}

struct RailSurfaceState: Equatable {
    let rows: [RailProviderContent]
    let contents: [RailDetailContent]
    let preview: RailPreviewState
    let edge: RailEdge
    let reducesMotion: Bool
}

struct RailSurfaceRepresentable: NSViewRepresentable {
    let state: RailSurfaceState
    let bridge: RailSurfaceBridge
    let selectProvider: (ProviderID) -> Void
    let openSettings: () -> Void

    func makeNSView(context _: Context) -> RailSurfaceView {
        RailSurfaceView()
    }

    func updateNSView(_ view: RailSurfaceView, context _: Context) {
        view.bridge = bridge
        bridge.surface = view
        view.selectProvider = selectProvider
        view.openSettings = openSettings
        if view.state == nil {
            view.settingsGlyph
                .rootView = RailSettingsGlyph(action: { [weak view] in view?.openSettings() })
        }
        view.update(state)
    }
}

/// Samples one timeline for the shell, mask, card, and content. Core Animation
/// runs the visual tracks; the optional input clock follows the visible card.
final class RailSurfaceView: NSView {
    var selectProvider: (ProviderID) -> Void = { _ in }
    var openSettings: () -> Void = {}
    weak var bridge: RailSurfaceBridge?
    private(set) var state: RailSurfaceState?
    let shell = CAShapeLayer()
    let railMask = CAShapeLayer()
    let detailShell = CAShapeLayer()
    let detailMask = CAShapeLayer()
    let orbArc = CAShapeLayer()
    let orbDisc = CAShapeLayer()
    let highlight = CAShapeLayer()
    let rowsContainer = NSView()
    let detailContainer = NSView()
    let settingsGlyph = NSHostingView(rootView: RailSettingsGlyph(action: {}))
    var rowViews: [ProviderID: NSHostingView<EdgeProviderRow>] = [:]
    var detailViews: [ProviderID: NSHostingView<EdgeDetailPanel>] = [:]
    var rowTracks: [ProviderID: RailMotion.Track] = [:]
    var contentTracks: [ProviderID: RailMotion.Track] = [:]
    var expansion = RailMotion.Track(0)
    var detailCenter = RailMotion.Track(92)
    var detailHeight = RailMotion.Track(172)
    var detailPresence = RailMotion.Track(0)
    var orbPresence = RailMotion.Track(0)
    var settingsHover = RailMotion.Track(0)
    var displayLink: CADisplayLink?
    var completionWork: DispatchWorkItem?
    private var linkTarget: RailDisplayLinkTarget?
    var requestedSettingsHover = false
    private var lastLayoutBounds = CGRect.zero
    private(set) var lastFrameTime: TimeInterval = 0
    var renderedDetailRect = CGRect.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        rowsContainer.wantsLayer = true
        detailContainer.wantsLayer = true
        detailContainer.autoresizesSubviews = false
        for shape in [shell, detailShell, orbArc, orbDisc] {
            shape.fillColor = NSColor.black.cgColor
        }
        railMask.fillColor = NSColor.black.cgColor
        detailMask.fillColor = NSColor.black.cgColor
        layer?.addSublayer(detailShell)
        layer?.addSublayer(shell)
        addSubview(rowsContainer)
        rowsContainer.layer?.mask = railMask
        addSubview(detailContainer)
        detailContainer.layer?.mask = detailMask
        layer?.addSublayer(orbArc)
        layer?.addSublayer(orbDisc)
        addSubview(settingsGlyph)
        highlight.fillColor = nil
        highlight.strokeColor = RailShellMetrics.handleHighlightColor.cgColor
        highlight.lineWidth = 1
        layer?.addSublayer(highlight)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    isolated deinit {
        displayLink?.invalidate()
        completionWork?.cancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let target = RailDisplayLinkTarget(owner: self)
        linkTarget = target
        let link = displayLink(target: target, selector: #selector(RailDisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = RailMotion.preferredFrameRateRange
        link.add(to: .main, forMode: .common)
        displayLink = link
        animateSurface(at: CACurrentMediaTime())
    }

    override func layout() {
        super.layout()
        guard bounds != lastLayoutBounds else { return }
        lastLayoutBounds = bounds
        animateSurface(at: CACurrentMediaTime())
    }

    func update(_ next: RailSurfaceState, at time: TimeInterval = CACurrentMediaTime()) {
        guard next != state else { return }
        let old = state
        state = next
        reconcileViews(previous: old, next: next)
        expansion.retarget(
            next.preview == .mini ? 0 : 1,
            at: time,
            curve: .spring(RailMotion.unfoldSpring),
            directly: old == nil || next.reducesMotion,
        )
        retargetRows(next, initial: old == nil, at: time)
        retargetDetail(next, previous: old, at: time)
        retargetOrb(next, initial: old == nil, at: time)
        animateSurface(at: time)
    }

    func setSettingsHovered(_ hovered: Bool, at time: TimeInterval = CACurrentMediaTime()) {
        let hovered = hovered && state?.preview != .mini
        guard requestedSettingsHover != hovered else { return }
        requestedSettingsHover = hovered
        settingsHover.retarget(
            hovered ? 1 : 0,
            at: time,
            curve: .spring(RailMotion.settingsSpring),
            directly: state?.reducesMotion == true,
        )
        animateSurface(at: time)
    }

    func isAnimating(at time: TimeInterval) -> Bool {
        [expansion, detailCenter, detailHeight, detailPresence, orbPresence, settingsHover]
            .contains { $0.isActive(at: time) } || rowTracks.values
            .contains { $0.isActive(at: time) }
            || contentTracks.values.contains { $0.isActive(at: time) }
    }

    func render(at time: TimeInterval, publishesGeometry: Bool = true) {
        guard let state, !bounds.isEmpty else { return }
        lastFrameTime = time
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [shell, railMask, detailShell, detailMask, orbArc, orbDisc, highlight] {
            layer.frame = bounds
        }
        rowsContainer.frame = bounds
        detailContainer.frame = bounds
        layoutContent(at: time, state: state)
        apply(sampleLayers(at: time))
        CATransaction.commit()
        if publishesGeometry {
            synchronizeBridge(at: time)
        }
    }

    func transformed(_ path: CGPath) -> CGPath {
        let left = state?.edge == .left
        var transform = CGAffineTransform(
            a: left ? -1 : 1,
            b: 0,
            c: 0,
            d: -1,
            tx: left ? bounds.width : 0,
            ty: bounds.height,
        )
        return path.copy(using: &transform) ?? path
    }

    func viewRect(_ authored: CGRect) -> CGRect {
        CGRect(
            x: state?.edge == .left ? bounds.width - authored.maxX : authored.minX,
            y: bounds.height - authored.maxY,
            width: authored.width,
            height: authored.height,
        )
    }
}

private final class RailDisplayLinkTarget: NSObject {
    weak var owner: RailSurfaceView?
    init(owner: RailSurfaceView) {
        self.owner = owner
    }

    @objc func tick(_ link: CADisplayLink) {
        owner?.synchronizeBridge(at: link.targetTimestamp)
    }
}

struct RailSettingsGlyph: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape").font(.system(size: 21)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Pace settings")
    }
}

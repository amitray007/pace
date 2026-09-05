import AppKit
import PaceCore
import SwiftUI

extension RailSurfaceView {
    func reconcileViews(previous: RailSurfaceState?, next: RailSurfaceState) {
        let ids = Set(next.rows.map(\.id))
        for id in rowViews.keys where !ids.contains(id) {
            rowViews.removeValue(forKey: id)?.removeFromSuperview()
            detailViews.removeValue(forKey: id)?.removeFromSuperview()
            rowTracks.removeValue(forKey: id)
            contentTracks.removeValue(forKey: id)
        }
        for row in next.rows {
            if previous?.rows.first(where: { $0.id == row.id }) != row || rowViews[row.id] == nil {
                let content = EdgeProviderRow(
                    providerID: row.id,
                    usage: row.usage,
                    status: row.status,
                    increasedContrast: row.increasedContrast,
                    action: { [weak self] in self?.selectProvider(row.id) },
                )
                if let host = rowViews[row.id] {
                    host.rootView = content
                } else {
                    let host = NSHostingView(rootView: content)
                    host.wantsLayer = true
                    rowsContainer.addSubview(host)
                    rowViews[row.id] = host
                }
            }
        }
        reconcileDetailViews(previous: previous, next: next)
    }

    private func reconcileDetailViews(previous: RailSurfaceState?, next: RailSurfaceState) {
        for content in next.contents {
            let oldContent = previous?.contents.first { $0.providerID == content.providerID }
            let active = next.preview.detailProviderID == content.providerID
            let host = detailViews[content.providerID]
            let needsUpdate = oldContent != content || host == nil || host?.rootView
                .isActive != active
            if needsUpdate {
                let host: NSHostingView<EdgeDetailPanel>
                if let existing = detailViews[content.providerID] {
                    host = existing
                    host.rootView = EdgeDetailPanel(content: content, isActive: active)
                } else {
                    host = NSHostingView(rootView: EdgeDetailPanel(
                        content: content,
                        isActive: active,
                    ))
                    host.wantsLayer = true
                    detailContainer.addSubview(host)
                    detailViews[content.providerID] = host
                }
                // Natural content size stays fixed while the surrounding card glides.
                host.frame = CGRect(
                    x: 0,
                    y: 0,
                    width: EdgeRailGeometry.detailWidth,
                    height: ceil(host.fittingSize.height),
                )
                host.layoutSubtreeIfNeeded()
            }
        }
    }

    func layoutContent(at time: TimeInterval, state: RailSurfaceState) {
        for (index, row) in state.rows.enumerated() {
            guard let host = rowViews[row.id] else { continue }
            let progress = rowTracks[row.id]?.sample(at: time).value ?? 0
            let rect = CGRect(
                x: EdgeRailGeometry.railOriginX,
                y: EdgeRailGeometry.providerTopY(count: state.rows.count)[index],
                width: EdgeRailGeometry.railWidth,
                height: EdgeRailGeometry.providerRowHeight,
            )
            host.frame = viewRect(rect)
            host.isHidden = progress <= 0 && rowTracks[row.id]?.isActive(at: time) != true
            host.setAccessibilityHidden(state.preview == .mini)
        }
        let rect = detailRect(at: time)
        detailContainer.isHidden = detailPresence.sample(at: time).value == 0 && !detailPresence
            .isActive(at: time)
        for (id, host) in detailViews {
            host.frame = viewRect(CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: host.bounds.height,
            ))
            let alpha = contentTracks[id]?.sample(at: time).value ?? 0
            host.isHidden = alpha == 0 && contentTracks[id]?.isActive(at: time) != true
            host.setAccessibilityHidden(id != state.preview.detailProviderID)
        }
        settingsGlyph
            .frame = viewRect(RailShellMetrics
                .settingsCircleRect(providerRowCount: state.rows.count))
        settingsGlyph.wantsLayer = true
        settingsGlyph.isHidden = orbPresence.sample(at: time).value == 0 && !orbPresence
            .isActive(at: time)
        settingsGlyph.setAccessibilityHidden(state.preview == .mini)
    }

    func scrollDetail(with event: NSEvent) {
        guard let id = state?.preview.detailProviderID, let host = detailViews[id] else { return }
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView {
                return scroll
            }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        scrollView(in: host)?.scrollWheel(with: event)
    }
}

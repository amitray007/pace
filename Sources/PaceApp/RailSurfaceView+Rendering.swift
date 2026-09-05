import AppKit
import QuartzCore

extension RailSurfaceView {
    func detailRect(at time: TimeInterval) -> CGRect {
        let center = detailCenter.sample(at: time).value
        let height = max(1, detailHeight.sample(at: time).value)
        let presence = min(max(detailPresence.sample(at: time).value, 0), 1)
        let slide = state?.reducesMotion == true ? 0 : (1 - presence) * 24 * 44 / 117
        return CGRect(
            x: slide,
            y: EdgeRailGeometry.detailPanelY(centerY: center, height: height),
            width: EdgeRailGeometry.detailWidth,
            height: height,
        )
    }

    func sampleLayers(
        at time: TimeInterval,
        animatedSince start: TimeInterval? = nil,
    ) -> [CALayer: RailLayerSample] {
        guard let state else { return [:] }
        var result: [CALayer: RailLayerSample] = [:]
        if start == nil || expansion.isActive(at: start ?? time) {
            let progress = expansion.sample(at: time).value
            let path = transformed(RailShellPaths.reveal(
                progress: progress,
                providerRowCount: state.rows.count,
            ))
            result[shell] = RailLayerSample(path: path)
            result[railMask] = RailLayerSample(path: path)
            result[highlight] = RailLayerSample(
                path: transformed(RailShellPaths
                    .handleHighlight(providerRowCount: state.rows.count)),
                opacity: Float(max(0, 1 - progress)),
            )
        }
        for row in state.rows {
            guard let layer = rowViews[row.id]?.layer else { continue }
            if let start, rowTracks[row.id]?.isActive(at: start) != true {
                continue
            }
            let value = rowTracks[row.id]?.sample(at: time).value ?? 0
            let offset = state
                .reducesMotion ? 0 : (1 - value) * (28 * 44 / 117) *
                (state.edge == .right ? 1.0 : -1.0)
            result[layer] = RailLayerSample(
                opacity: Float(min(max(value, 0), 1)),
                transform: CATransform3DMakeTranslation(offset, 0, 0),
            )
        }
        sampleDetail(at: time, animatedSince: start, into: &result)
        let settingsMove = orbPresence.isActive(at: start ?? time) || settingsHover
            .isActive(at: start ?? time)
        if start == nil || settingsMove {
            sampleSettings(at: time, state: state, into: &result)
        }
        return result
    }

    private func sampleDetail(
        at time: TimeInterval,
        animatedSince start: TimeInterval?,
        into result: inout [CALayer: RailLayerSample],
    ) {
        let fade = start == nil || detailPresence.isActive(at: start ?? time)
        let moves = fade || detailCenter.isActive(at: start ?? time) || detailHeight
            .isActive(at: start ?? time)
        let rect = detailRect(at: time)
        let presence = Float(min(max(detailPresence.sample(at: time).value, 0), 1))
        var shellSample = RailLayerSample(opacity: fade ? presence : nil)
        if moves {
            var slide = CGAffineTransform(translationX: rect.minX, y: 0)
            let path = RailShellPaths.detail(
                centerY: detailCenter.sample(at: time).value,
                panelHeight: rect.height,
            )
            shellSample.path = transformed(path.copy(using: &slide) ?? path)
            result[detailMask] = RailLayerSample(path: transformed(CGPath(
                roundedRect: rect,
                cornerWidth: 16,
                cornerHeight: 16,
                transform: nil,
            )))
        }
        if fade || moves {
            result[detailShell] = shellSample
        }
        if fade {
            if let layer = detailContainer.layer {
                result[layer] = RailLayerSample(opacity: presence)
            }
        }
        for (id, host) in detailViews {
            guard let layer = host.layer else { continue }
            let crossfades = start == nil || contentTracks[id]?.isActive(at: start ?? time) == true
            guard moves || crossfades else { continue }
            let frame = viewRect(CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: host.bounds.height,
            ))
            let alpha = min(max(contentTracks[id]?.sample(at: time).value ?? 0, 0), 1)
            result[layer] = RailLayerSample(
                opacity: crossfades ? Float(alpha) : nil,
                position: moves ? CGPoint(
                    x: frame.minX + frame.width * layer.anchorPoint.x,
                    y: frame.minY + frame.height * layer.anchorPoint.y,
                ) : nil,
            )
        }
    }

    private func sampleSettings(
        at time: TimeInterval,
        state: RailSurfaceState,
        into result: inout [CALayer: RailLayerSample],
    ) {
        let presence = min(max(orbPresence.sample(at: time).value, 0), 1)
        let hover = settingsHover.sample(at: time).value
        let alpha = min(max(hover, 0), 1)
        let center = RailShellMetrics.settingsArcCenter(providerRowCount: state.rows.count)
        let mergeScale = (RailShellMetrics.contourHeight + RailShellMetrics.settingsArcStroke)
            / RailShellMetrics.settingsArcRadius
        let arcScale = state
            .reducesMotion ? 1 : 1 + (mergeScale - 1) * (1 - presence) - 0.14 * hover
        result[orbArc] = RailLayerSample(path: transformed(scaled(
            RailShellPaths.settings(showsCircle: false, providerRowCount: state.rows.count),
            around: center, by: arcScale,
        )), opacity: Float(presence * (1 - alpha)))
        let discScale = state.reducesMotion ? 1 : 1.1 - 0.1 * hover
        result[orbDisc] = RailLayerSample(path: transformed(scaled(
            RailShellPaths.settings(showsCircle: true, providerRowCount: state.rows.count),
            around: center, by: discScale,
        )), opacity: Float(presence * alpha))
        if let layer = settingsGlyph.layer {
            let scale = state.reducesMotion ? 1 : 0.5 + 0.5 * hover
            let angle = state.reducesMotion ? 0 : (1 - hover) * -.pi / 3
            let pivot = CGPoint(
                x: settingsGlyph.bounds.width * (0.5 - layer.anchorPoint.x),
                y: settingsGlyph.bounds.height * (0.5 - layer.anchorPoint.y),
            )
            let transform = CGAffineTransform(translationX: pivot.x, y: pivot.y)
                .rotated(by: angle).scaledBy(x: scale, y: scale)
                .translatedBy(x: -pivot.x, y: -pivot.y)
            result[layer] = RailLayerSample(
                opacity: Float(presence * alpha),
                transform: CATransform3DMakeAffineTransform(transform),
            )
        }
    }

    private func scaled(_ path: CGPath, around center: CGPoint, by scale: CGFloat) -> CGPath {
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scale, y: scale).translatedBy(x: -center.x, y: -center.y)
        return path.copy(using: &transform) ?? path
    }
}

import AppKit
import QuartzCore

struct RailLayerSample {
    var path: CGPath?
    var opacity: Float?
    var position: CGPoint?
    var transform: CATransform3D?
}

extension RailSurfaceView {
    /// All animated values are sampled together, then run on the compositor.
    /// SwiftUI hosts keep their natural bounds throughout the transition.
    func animateSurface(at time: TimeInterval) {
        completionWork?.cancel()
        for layer in sampleLayers(at: time).keys {
            for key in layer.animationKeys() ?? [] where key.hasPrefix("pace.surface.") {
                layer.removeAnimation(forKey: key)
            }
        }
        var times = [time]
        while let last = times.last, isAnimating(at: last), last < time + 4 {
            times.append(last + 1.0 / 120)
        }
        guard let end = times.last, times.count > 1 else {
            render(at: time)
            return
        }
        let frames = times.map { sampleLayers(at: $0, animatedSince: time) }
        let duration = end - time
        render(at: end, publishesGeometry: false)
        prepareAnimatedVisibility(at: time)
        installKeyframes(frames, times: times, duration: duration, at: time)
        let work = DispatchWorkItem { [weak self] in
            self?.render(at: CACurrentMediaTime())
        }
        completionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        synchronizeBridge(at: time)
        displayLink?.isPaused = bridge?.geometryDidChange == nil
    }

    private func prepareAnimatedVisibility(at time: TimeInterval) {
        rowsContainer.isHidden = false
        detailContainer.isHidden = false
        settingsGlyph.isHidden = false
        for host in rowViews.values {
            host.isHidden = false
        }
        for (id, host) in detailViews {
            host.isHidden = contentTracks[id]?.sample(at: time).value == 0
                && contentTracks[id]?.isActive(at: time) != true
        }
    }

    private func installKeyframes(
        _ frames: [[CALayer: RailLayerSample]],
        times: [TimeInterval],
        duration: TimeInterval,
        at time: TimeInterval,
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, final) in frames[frames.count - 1] {
            let samples = frames.compactMap { $0[layer] }
            let keyTimes = times.map { NSNumber(value: ($0 - time) / duration) }
            func add(_ key: String, values: [Any]) {
                guard values.count == times.count else { return }
                let animation = CAKeyframeAnimation(keyPath: key)
                animation.values = values
                animation.keyTimes = keyTimes
                animation.duration = duration
                animation.beginTime = layer.convertTime(time, from: nil)
                animation.calculationMode = .linear
                animation.preferredFrameRateRange = RailMotion.preferredFrameRateRange
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                layer.add(animation, forKey: "pace.surface.\(key)")
            }
            if final.path != nil {
                add("path", values: samples.compactMap(\.path))
            }
            if final.opacity != nil {
                add("opacity", values: samples.compactMap(\.opacity))
            }
            if final.position != nil {
                add("position", values: samples.compactMap(\.position).map { NSValue(point: $0) })
            }
            if final.transform != nil {
                add(
                    "transform",
                    values: samples.compactMap(\.transform).map { NSValue(caTransform3D: $0) },
                )
            }
        }
        CATransaction.commit()
    }

    func synchronizeBridge(at time: TimeInterval) {
        let presence = detailPresence.sample(at: time).value
        let rect = detailRect(at: time)
        renderedDetailRect = rect
        bridge?.update(
            detailRect: presence > 0 ? rect : nil,
            centerY: presence > 0 ? detailCenter.sample(at: time).value : nil,
        )
        if !isAnimating(at: time) {
            displayLink?.isPaused = true
        }
    }

    func apply(_ samples: [CALayer: RailLayerSample]) {
        for (layer, sample) in samples {
            if let path = sample.path {
                (layer as? CAShapeLayer)?.path = path
            }
            if let opacity = sample.opacity {
                layer.opacity = opacity
            }
            if let position = sample.position {
                layer.position = position
            }
            if let transform = sample.transform {
                layer.transform = transform
            }
        }
    }
}

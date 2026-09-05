import AppKit
import SwiftUI

struct ProgressRingLayerRepresentable: NSViewRepresentable {
    let fraction: Double
    let color: NSColor
    let increasedContrast: Bool
    /// Defaults to false so existing callers retain the reading animation.
    let reducesMotion: Bool

    init(
        fraction: Double,
        color: NSColor,
        increasedContrast: Bool,
        reducesMotion: Bool = false,
    ) {
        self.fraction = fraction
        self.color = color
        self.increasedContrast = increasedContrast
        self.reducesMotion = reducesMotion
    }

    func makeNSView(context _: Context) -> ProgressRingLayerView {
        ProgressRingLayerView()
    }

    func updateNSView(_ view: ProgressRingLayerView, context _: Context) {
        view.update(
            fraction: fraction,
            color: color,
            increasedContrast: increasedContrast,
            reducesMotion: reducesMotion,
        )
    }
}

final class ProgressRingLayerView: NSView {
    private let progressLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()
    private var hasReceivedReading = false
    private var readingTrack = RailMotion.Track(0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for item in [trackLayer, progressLayer] {
            item.fillColor = nil
            item.lineCap = .round
            item.actions = ["strokeEnd": NSNull(), "path": NSNull(), "lineWidth": NSNull()]
            layer?.addSublayer(item)
        }
        // The reference has a broad, quiet track under a thinner bright
        // reading. Keeping the two widths separate preserves that depth.
        trackLayer.lineCap = .butt
        trackLayer.strokeColor = UsageLevelPalette.track.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        // The source weights are measured from a 117 px ring. Insetting by
        // the wider track keeps the 44 pt reference ring inside its bounds.
        let trackWidth = max(bounds.width * Self.trackStrokeRatio, 1)
        let progressWidth = max(bounds.width * Self.progressStrokeRatio, 1)
        trackLayer.lineWidth = trackWidth
        progressLayer.lineWidth = progressWidth
        // Both strokes share the outer circle. The wider track determines the
        // inset so neither stroke escapes the reference ring boundary.
        let rect = bounds.insetBy(dx: trackWidth / 2, dy: trackWidth / 2)
        let trackPath = CGPath(ellipseIn: rect, transform: nil)
        let progressPath = CGMutablePath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        // Core Animation's unflipped path coordinates put pi/2 at the visual
        // top. An explicit clockwise arc avoids the ellipse transform whose
        // apparent start landed at the bottom in the native capture.
        progressPath.addArc(
            center: center,
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi / 2 - 2 * .pi,
            clockwise: true,
        )
        trackLayer.frame = bounds
        trackLayer.path = trackPath
        progressLayer.frame = bounds
        progressLayer.path = progressPath
        progressLayer.transform = CATransform3DIdentity
    }

    func update(
        fraction: Double,
        color: NSColor,
        increasedContrast: Bool,
        reducesMotion: Bool,
    ) {
        let target = CGFloat(min(max(fraction, 0), 1))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.strokeColor = UsageLevelPalette
            .trackColor(increasedContrast: increasedContrast).cgColor
        progressLayer.strokeColor = color.cgColor
        progressLayer.strokeEnd = target
        CATransaction.commit()

        guard hasReceivedReading, !reducesMotion else {
            if !hasReceivedReading || reducesMotion {
                progressLayer.removeAnimation(forKey: Self.readingAnimationKey)
                readingTrack = RailMotion.Track(Double(target))
            }
            hasReceivedReading = true
            return
        }

        guard readingTrack.target != Double(target) else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        readingTrack.retarget(
            Double(target),
            at: now,
            curve: .spring(Self.readingSpring),
        )
        let reading = CAKeyframeAnimation(keyPath: "strokeEnd")
        let samples = sampledReading(from: now)
        reading.values = samples.map(NSNumber.init(value:))
        reading.keyTimes = samples.indices.map {
            NSNumber(value: Double($0) / Double(samples.count - 1))
        }
        reading.duration = Double(samples.count - 1) / Self.readingFrameRate
        reading.calculationMode = .linear
        reading.timingFunction = CAMediaTimingFunction(name: .linear)
        reading.preferredFrameRateRange = RailMotion.preferredFrameRateRange
        progressLayer.add(reading, forKey: Self.readingAnimationKey)
        hasReceivedReading = true
    }

    /// Samples the shared native-spring track at the display cadence. Sampling
    /// the track, rather than starting a fresh CA spring, carries its sampled
    /// velocity across quick provider refreshes.
    private func sampledReading(from start: TimeInterval) -> [Double] {
        var samples = [readingTrack.sample(at: start).value]
        var time = start + 1 / Self.readingFrameRate
        while readingTrack.isActive(at: time) {
            samples.append(readingTrack.sample(at: time).value)
            time += 1 / Self.readingFrameRate
        }
        samples.append(readingTrack.sample(at: time).value)
        return samples
    }

    /// Source ring weights measured against its 117 px diameter, then kept as
    /// ratios so the 44 pt Pace ring has the same hierarchy.
    private static let trackStrokeRatio: CGFloat = 15.5 / 117
    private static let progressStrokeRatio: CGFloat = 8 / 117
    private static let readingAnimationKey = "pace.reading"
    private static let readingFrameRate = 120.0
    private static let readingSpring = RailMotion.ScalarSpring(response: 0.9, dampingRatio: 0.9)
}

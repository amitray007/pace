import AppKit
import QuartzCore

/// Preview-only, view-local frame capture. It records the rail layer itself,
/// never the desktop or any other application's window.
@MainActor
final class RailMotionCapture: NSObject {
    private struct Frame: Codable {
        var index: Int
        var timestamp: TimeInterval
        var elapsed: TimeInterval
        var captureDuration: TimeInterval
    }

    private struct Metadata: Codable {
        var startedAt: TimeInterval
        var duration: TimeInterval
        var frameRate: Double
        var frames: [Frame]
    }

    private weak var view: NSView?
    private let outputDirectory: URL
    private let duration: TimeInterval
    private var displayLink: CADisplayLink?
    private var startedAt: TimeInterval?
    private var frames: [Frame] = []

    /// Creates a local diagnostic capture. Callers must gate this behind both
    /// `PACE_REFERENCE_PREVIEW` and `PACE_CAPTURE_MOTION`.
    init(view: NSView, outputDirectory: URL, duration: TimeInterval = 10) {
        self.view = view
        self.outputDirectory = outputDirectory
        self.duration = duration
        super.init()

        try? FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true,
        )
        let displayLink = view.displayLink(target: self, selector: #selector(captureFrame(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 60,
            preferred: 60,
        )
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        startedAt = ProcessInfo.processInfo.systemUptime
        displayLink.isPaused = false
    }

    isolated deinit {
        displayLink?.invalidate()
    }

    @objc private func captureFrame(_: CADisplayLink) {
        guard let view, let layer = view.layer else {
            stop()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard let startedAt else {
            stop()
            return
        }
        guard now - startedAt < duration else {
            stop()
            return
        }

        let captureStartedAt = ProcessInfo.processInfo.systemUptime
        writePNG(from: layer.presentation() ?? layer, bounds: view.bounds, index: frames.count)
        frames.append(
            Frame(
                index: frames.count,
                timestamp: now,
                elapsed: now - startedAt,
                captureDuration: ProcessInfo.processInfo.systemUptime - captureStartedAt,
            ),
        )
    }

    private func writePNG(from layer: CALayer, bounds: CGRect, index: Int) {
        let scale = 2.0
        let width = max(Int((bounds.width * scale).rounded(.up)), 1)
        let height = max(Int((bounds.height * scale).rounded(.up)), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue,
        ) else {
            return
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        layer.render(in: context)
        guard let image = context.makeImage() else {
            return
        }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            return
        }
        let name = String(format: "frame-%05d.png", index)
        try? data.write(to: outputDirectory.appending(path: name), options: .atomic)
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        guard let startedAt else {
            return
        }
        let metadata = Metadata(
            startedAt: startedAt,
            duration: duration,
            frameRate: 60,
            frames: frames,
        )
        guard let data = try? JSONEncoder().encode(metadata) else {
            return
        }
        try? data.write(to: outputDirectory.appending(path: "metadata.json"), options: .atomic)
        self.startedAt = nil
    }
}

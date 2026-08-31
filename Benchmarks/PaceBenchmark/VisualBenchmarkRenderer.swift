import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func writeReviewImages(
    reference: [Bool],
    capture: [Bool],
    width: Int,
    height: Int,
    directoryURL: URL,
) throws {
    try writePNG(
        pixels: maskPixels(reference),
        width: width,
        height: height,
        url: directoryURL.appendingPathComponent("reference-mask.png"),
    )
    try writePNG(
        pixels: maskPixels(capture),
        width: width,
        height: height,
        url: directoryURL.appendingPathComponent("capture-mask.png"),
    )
    try writePNG(
        pixels: comparisonPixels(reference: reference, capture: capture, differencesOnly: false),
        width: width,
        height: height,
        url: directoryURL.appendingPathComponent("overlay.png"),
    )
    try writePNG(
        pixels: comparisonPixels(reference: reference, capture: capture, differencesOnly: true),
        width: width,
        height: height,
        url: directoryURL.appendingPathComponent("difference.png"),
    )
}

private func maskPixels(_ mask: [Bool]) -> [UInt8] {
    mask.flatMap { foreground in
        foreground ? [0, 0, 0, 255] : [255, 255, 255, 255]
    }
}

private func comparisonPixels(
    reference: [Bool],
    capture: [Bool],
    differencesOnly: Bool,
) -> [UInt8] {
    var pixels: [UInt8] = []
    pixels.reserveCapacity(reference.count * 4)
    for index in reference.indices {
        let color: [UInt8] = switch (reference[index], capture[index]) {
        case (true, true):
            differencesOnly ? [30, 30, 30, 255] : [245, 245, 245, 255]
        case (true, false):
            [255, 70, 100, 255]
        case (false, true):
            [40, 220, 255, 255]
        case (false, false):
            [12, 12, 14, 255]
        }
        pixels.append(contentsOf: color)
    }
    return pixels
}

private func writePNG(pixels: [UInt8], width: Int, height: Int, url: URL) throws {
    guard
        let provider = CGDataProvider(data: Data(pixels) as CFData),
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent,
        ),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil,
        )
    else {
        throw VisualBenchmarkError.cannotWriteImage(url.path)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw VisualBenchmarkError.cannotWriteImage(url.path)
    }
}

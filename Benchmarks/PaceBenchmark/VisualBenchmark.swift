import CoreGraphics
import Foundation
import ImageIO

private struct VisualConfiguration {
    let referenceURL: URL
    let captureURL: URL
    let outputDirectoryURL: URL
    let threshold: UInt8
    let referenceRegionStart: Double
    let referenceRegionStartY: Double
    let referenceRegionEndY: Double

    init(arguments: ArraySlice<String>) throws {
        var values: [String: String] = [:]
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let option = arguments[index]
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw BenchmarkError.missingValue(option)
            }
            guard [
                "--reference",
                "--capture",
                "--output-dir",
                "--threshold",
                "--reference-region-start",
                "--reference-region-start-y",
                "--reference-region-end-y",
            ].contains(option) else {
                throw BenchmarkError.unknownOption(option)
            }
            values[option] = arguments[valueIndex]
            index = arguments.index(after: valueIndex)
        }

        referenceURL = try Self.fileURL("--reference", values: values)
        captureURL = try Self.fileURL("--capture", values: values)
        guard let outputPath = values["--output-dir"] else {
            throw BenchmarkError.missingValue("--output-dir")
        }
        outputDirectoryURL = URL(fileURLWithPath: outputPath)

        let thresholdValue = values["--threshold"].flatMap(Int.init) ?? 32
        guard (0 ... 255).contains(thresholdValue) else {
            throw BenchmarkError.invalidValue(
                option: "--threshold",
                value: values["--threshold"] ?? "",
            )
        }
        threshold = UInt8(thresholdValue)

        referenceRegionStart = values["--reference-region-start"].flatMap(Double.init) ?? 0.55
        guard (0 ..< 1).contains(referenceRegionStart) else {
            throw BenchmarkError.invalidValue(
                option: "--reference-region-start",
                value: values["--reference-region-start"] ?? "",
            )
        }
        let verticalRegion = try Self.verticalRegion(values: values)
        referenceRegionStartY = verticalRegion.start
        referenceRegionEndY = verticalRegion.end
    }

    private static func fileURL(
        _ option: String,
        values: [String: String],
    ) throws -> URL {
        guard let path = values[option] else {
            throw BenchmarkError.missingValue(option)
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VisualBenchmarkError.fileNotFound(url.path)
        }
        return url
    }

    private static func verticalRegion(
        values: [String: String],
    ) throws -> (start: Double, end: Double) {
        let start = values["--reference-region-start-y"].flatMap(Double.init) ?? 0
        let end = values["--reference-region-end-y"].flatMap(Double.init) ?? 1
        guard (0 ..< 1).contains(start), (0 ... 1).contains(end), start < end else {
            throw BenchmarkError.invalidValue(
                option: "--reference-region-start-y/--reference-region-end-y",
                value: "\(start)/\(end)",
            )
        }
        return (start, end)
    }
}

private struct PixelImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(url: URL) throws {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw VisualBenchmarkError.cannotDecodeImage(url.path)
        }

        let decodedWidth = image.width
        let decodedHeight = image.height
        var decodedPixels = [UInt8](
            repeating: 0,
            count: decodedWidth * decodedHeight * 4,
        )
        let rendered = decodedPixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: decodedWidth,
                height: decodedHeight,
                bitsPerComponent: 8,
                bytesPerRow: decodedWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else {
                return false
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: decodedWidth, height: decodedHeight),
            )
            return true
        }
        guard rendered else {
            throw VisualBenchmarkError.cannotCreateImageContext(url.path)
        }
        width = decodedWidth
        height = decodedHeight
        pixels = decodedPixels
    }

    func mask(
        threshold: UInt8,
        regionStartX: Double,
        regionStartY: Double,
        regionEndY: Double,
        path: String,
    ) throws -> PixelMask {
        let startX = Int(Double(width) * regionStartX)
        let startY = Int(Double(height) * regionStartY)
        let endY = min(height, Int(ceil(Double(height) * regionEndY)))
        var values = [Bool](repeating: false, count: width * height)
        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1

        for pixelY in startY ..< endY {
            for pixelX in startX ..< width {
                let pixelIndex = (pixelY * width + pixelX) * 4
                let isForeground = pixels[pixelIndex] <= threshold &&
                    pixels[pixelIndex + 1] <= threshold &&
                    pixels[pixelIndex + 2] <= threshold &&
                    pixels[pixelIndex + 3] > 0
                guard isForeground else {
                    continue
                }
                values[pixelY * width + pixelX] = true
                minimumX = min(minimumX, pixelX)
                minimumY = min(minimumY, pixelY)
                maximumX = max(maximumX, pixelX)
                maximumY = max(maximumY, pixelY)
            }
        }

        guard maximumX >= minimumX, maximumY >= minimumY else {
            throw VisualBenchmarkError.noForeground(path)
        }
        return PixelMask(
            width: width,
            height: height,
            values: values,
            bounds: PixelBounds(
                originX: minimumX,
                originY: minimumY,
                width: maximumX - minimumX + 1,
                height: maximumY - minimumY + 1,
            ),
        )
    }
}

private struct PixelMask {
    let width: Int
    let height: Int
    let values: [Bool]
    let bounds: PixelBounds

    func normalized(width targetWidth: Int, height targetHeight: Int) -> [Bool] {
        let scale = min(
            Double(targetWidth) / Double(bounds.width),
            Double(targetHeight) / Double(bounds.height),
        )
        let scaledWidth = max(1, Int((Double(bounds.width) * scale).rounded()))
        let scaledHeight = max(1, Int((Double(bounds.height) * scale).rounded()))
        let offsetX = targetWidth - scaledWidth
        let offsetY = (targetHeight - scaledHeight) / 2
        var result = [Bool](repeating: false, count: targetWidth * targetHeight)

        for targetY in 0 ..< scaledHeight {
            let sourceY = min(
                bounds.originY + Int(Double(targetY) / scale),
                bounds.originY + bounds.height - 1,
            )
            for targetX in 0 ..< scaledWidth {
                let sourceX = min(
                    bounds.originX + Int(Double(targetX) / scale),
                    bounds.originX + bounds.width - 1,
                )
                result[(targetY + offsetY) * targetWidth + targetX + offsetX] =
                    values[sourceY * width + sourceX]
            }
        }
        return result
    }
}

private struct VisualMasks {
    let reference: PixelMask
    let capture: PixelMask
    let normalizedReference: [Bool]
    let normalizedCapture: [Bool]
    let width: Int
    let height: Int
}

func runVisualBenchmark(arguments: ArraySlice<String>) throws -> some Encodable {
    let configuration = try VisualConfiguration(arguments: arguments)
    let masks = try loadVisualMasks(configuration: configuration)
    try FileManager.default.createDirectory(
        at: configuration.outputDirectoryURL,
        withIntermediateDirectories: true,
    )
    try writeReviewImages(
        reference: masks.normalizedReference,
        capture: masks.normalizedCapture,
        width: masks.width,
        height: masks.height,
        directoryURL: configuration.outputDirectoryURL,
    )

    let report = visualReport(configuration: configuration, masks: masks)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let reportData = try encoder.encode(report)
    try reportData.write(
        to: configuration.outputDirectoryURL.appendingPathComponent("metrics.json"),
        options: .atomic,
    )
    return report
}

private func loadVisualMasks(configuration: VisualConfiguration) throws -> VisualMasks {
    let referenceImage = try PixelImage(url: configuration.referenceURL)
    let captureImage = try PixelImage(url: configuration.captureURL)
    let referenceMask = try referenceImage.mask(
        threshold: configuration.threshold,
        regionStartX: configuration.referenceRegionStart,
        regionStartY: configuration.referenceRegionStartY,
        regionEndY: configuration.referenceRegionEndY,
        path: configuration.referenceURL.path,
    )
    let captureMask = try captureImage.mask(
        threshold: configuration.threshold,
        regionStartX: 0,
        regionStartY: 0,
        regionEndY: 1,
        path: configuration.captureURL.path,
    )

    let normalizedWidth = captureImage.width
    let normalizedHeight = captureImage.height
    let normalizedReference = solidSilhouette(
        referenceMask.normalized(width: normalizedWidth, height: normalizedHeight),
        width: normalizedWidth,
        height: normalizedHeight,
    )
    let normalizedCapture = solidSilhouette(
        captureMask.normalized(width: normalizedWidth, height: normalizedHeight),
        width: normalizedWidth,
        height: normalizedHeight,
    )
    return VisualMasks(
        reference: referenceMask,
        capture: captureMask,
        normalizedReference: normalizedReference,
        normalizedCapture: normalizedCapture,
        width: normalizedWidth,
        height: normalizedHeight,
    )
}

private func visualReport(
    configuration: VisualConfiguration,
    masks: VisualMasks,
) -> VisualBenchmarkReport {
    let metrics = compare(
        reference: masks.normalizedReference,
        capture: masks.normalizedCapture,
    )
    let referenceCoverage = coverage(masks.normalizedReference)
    let captureCoverage = coverage(masks.normalizedCapture)
    return VisualBenchmarkReport(
        referencePath: configuration.referenceURL.path,
        capturePath: configuration.captureURL.path,
        threshold: configuration.threshold,
        referenceRegionStart: configuration.referenceRegionStart,
        referenceRegionStartY: configuration.referenceRegionStartY,
        referenceRegionEndY: configuration.referenceRegionEndY,
        normalizedWidth: masks.width,
        normalizedHeight: masks.height,
        referenceBounds: masks.reference.bounds,
        captureBounds: masks.capture.bounds,
        referenceAspectRatio: masks.reference.bounds.aspectRatio,
        captureAspectRatio: masks.capture.bounds.aspectRatio,
        aspectRatioDeltaPercent: percentDelta(
            masks.reference.bounds.aspectRatio,
            masks.capture.bounds.aspectRatio,
        ),
        silhouetteIntersectionOverUnion: metrics.intersectionOverUnion,
        symmetricDifferenceOverUnion: metrics.symmetricDifferenceOverUnion,
        referenceForegroundCoverage: referenceCoverage,
        captureForegroundCoverage: captureCoverage,
        foregroundCoverageDeltaPercent: percentDelta(referenceCoverage, captureCoverage),
        outputDirectory: configuration.outputDirectoryURL.path,
    )
}

private func solidSilhouette(_ mask: [Bool], width: Int, height: Int) -> [Bool] {
    var exterior = [Bool](repeating: false, count: mask.count)
    var queue: [Int] = []
    queue.reserveCapacity(mask.count)

    func enqueue(_ index: Int) {
        guard !mask[index], !exterior[index] else {
            return
        }
        exterior[index] = true
        queue.append(index)
    }

    for pixelX in 0 ..< width {
        enqueue(pixelX)
        enqueue((height - 1) * width + pixelX)
    }
    for pixelY in 0 ..< height {
        enqueue(pixelY * width)
        enqueue(pixelY * width + width - 1)
    }

    var cursor = 0
    while cursor < queue.count {
        let index = queue[cursor]
        cursor += 1
        let pixelX = index % width
        let pixelY = index / width
        if pixelX > 0 {
            enqueue(index - 1)
        }
        if pixelX + 1 < width {
            enqueue(index + 1)
        }
        if pixelY > 0 {
            enqueue(index - width)
        }
        if pixelY + 1 < height {
            enqueue(index + width)
        }
    }

    return mask.indices.map { mask[$0] || !exterior[$0] }
}

private func compare(reference: [Bool], capture: [Bool]) -> (
    intersectionOverUnion: Double,
    symmetricDifferenceOverUnion: Double,
) {
    var intersection = 0
    var union = 0
    var difference = 0
    for index in reference.indices {
        if reference[index] || capture[index] {
            union += 1
        }
        if reference[index], capture[index] {
            intersection += 1
        } else if reference[index] != capture[index] {
            difference += 1
        }
    }
    return (
        Double(intersection) / Double(union),
        Double(difference) / Double(union),
    )
}

private func coverage(_ mask: [Bool]) -> Double {
    Double(mask.count(where: { $0 })) / Double(mask.count)
}

private func percentDelta(_ reference: Double, _ capture: Double) -> Double {
    abs(capture - reference) / reference * 100
}

import Foundation

struct PixelBounds: Encodable {
    let originX: Int
    let originY: Int
    let width: Int
    let height: Int

    var aspectRatio: Double {
        Double(width) / Double(height)
    }
}

struct VisualBenchmarkReport: Encodable {
    let schemaVersion = 1
    let benchmark = "normalized-black-silhouette"
    let referencePath: String
    let capturePath: String
    let threshold: UInt8
    let referenceRegionStart: Double
    let referenceRegionStartY: Double
    let referenceRegionEndY: Double
    let normalizedWidth: Int
    let normalizedHeight: Int
    let referenceBounds: PixelBounds
    let captureBounds: PixelBounds
    let referenceAspectRatio: Double
    let captureAspectRatio: Double
    let aspectRatioDeltaPercent: Double
    let silhouetteIntersectionOverUnion: Double
    let symmetricDifferenceOverUnion: Double
    let referenceForegroundCoverage: Double
    let captureForegroundCoverage: Double
    let foregroundCoverageDeltaPercent: Double
    let outputDirectory: String
}

enum VisualBenchmarkError: Error, CustomStringConvertible {
    case cannotCreateImageContext(String)
    case cannotDecodeImage(String)
    case cannotWriteImage(String)
    case fileNotFound(String)
    case noForeground(String)

    var description: String {
        switch self {
        case let .cannotCreateImageContext(path):
            "Cannot create an image context for \(path)"
        case let .cannotDecodeImage(path):
            "Cannot decode image: \(path)"
        case let .cannotWriteImage(path):
            "Cannot write image: \(path)"
        case let .fileNotFound(path):
            "Image file not found: \(path)"
        case let .noForeground(path):
            "No black silhouette found in image: \(path)"
        }
    }
}

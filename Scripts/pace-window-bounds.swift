// Print the union bounds of the on-screen Pace windows as
// "x y width height scale" in screen points plus the main display's backing
// scale factor. Used by Scripts/capture-surfaces.sh to crop review frames to
// the application's own surfaces.

import AppKit
import CoreGraphics
import Foundation

let entries = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID,
) as? [[String: Any]] ?? []

var minX = Double.greatestFiniteMagnitude
var minY = Double.greatestFiniteMagnitude
var maxX = -Double.greatestFiniteMagnitude
var maxY = -Double.greatestFiniteMagnitude
var found = false

for entry in entries {
    guard let owner = entry[kCGWindowOwnerName as String] as? String, owner == "Pace" else {
        continue
    }
    let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
    guard alpha > 0.9 else {
        continue
    }
    guard
        let bounds = entry[kCGWindowBounds as String] as? [String: Any],
        let x = bounds["X"] as? Double,
        let y = bounds["Y"] as? Double,
        let width = bounds["Width"] as? Double,
        let height = bounds["Height"] as? Double,
        width > 0, height > 0
    else {
        continue
    }
    found = true
    minX = min(minX, x)
    minY = min(minY, y)
    maxX = max(maxX, x + width)
    maxY = max(maxY, y + height)
}

guard found else {
    FileHandle.standardError.write(Data("no on-screen Pace window\n".utf8))
    exit(1)
}

let scale = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.backingScaleFactor
    ?? NSScreen.main?.backingScaleFactor
    ?? 1

print(Int(minX), Int(minY), Int(maxX - minX), Int(maxY - minY), scale)

import AppKit
import CoreGraphics

enum PaceFullScreenDetector {
    static func frontmostApplicationCovers(_ screen: NSScreen) -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
              as? CGDirectDisplayID,
              let windowList = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID,
              ) as? [[String: Any]]
        else {
            return false
        }
        let displayBounds = CGDisplayBounds(displayID)
        return windowList.contains { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == application.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(
                      dictionaryRepresentation: boundsDictionary as CFDictionary,
                  )
            else {
                return false
            }
            return covers(bounds, displayBounds: displayBounds)
        }
    }

    static func covers(
        _ windowBounds: CGRect,
        displayBounds: CGRect,
        tolerance: CGFloat = 2,
    ) -> Bool {
        abs(windowBounds.minX - displayBounds.minX) <= tolerance &&
            abs(windowBounds.minY - displayBounds.minY) <= tolerance &&
            abs(windowBounds.width - displayBounds.width) <= tolerance &&
            abs(windowBounds.height - displayBounds.height) <= tolerance
    }
}

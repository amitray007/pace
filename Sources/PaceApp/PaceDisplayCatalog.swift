import AppKit
import CoreGraphics
import Foundation

struct PaceDisplayDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
}

enum PaceDisplayCatalog {
    static var availableDisplays: [PaceDisplayDescriptor] {
        NSScreen.screens.map { screen in
            PaceDisplayDescriptor(
                id: identifier(for: screen),
                name: screen.localizedName,
            )
        }
    }

    static func selectedScreen(identifier: String?) -> NSScreen? {
        if let identifier {
            let selectedScreen = NSScreen.screens.first {
                Self.identifier(for: $0) == identifier
            }
            if let selectedScreen {
                return selectedScreen
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func identifier(for screen: NSScreen) -> String {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber,
              let displayUUID = CGDisplayCreateUUIDFromDisplayID(screenNumber.uint32Value)
        else {
            return screen.localizedName
        }
        return CFUUIDCreateString(nil, displayUUID.takeRetainedValue()) as String
    }
}

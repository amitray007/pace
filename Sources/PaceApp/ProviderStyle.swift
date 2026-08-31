import AppKit
import PaceCore
import SwiftUI

struct ProviderStyle {
    let id: ProviderID
    let name: String
    let accent: Color
    let accentColor: NSColor
    let markResourceName: String?

    static func resolve(_ providerID: ProviderID) -> Self {
        switch providerID {
        case .claude:
            Self(
                id: providerID,
                name: "Claude",
                accent: Color(red: 0.97, green: 0.36, blue: 0.20),
                accentColor: NSColor(red: 0.97, green: 0.36, blue: 0.20, alpha: 1),
                markResourceName: "claude",
            )
        case .codex:
            Self(
                id: providerID,
                name: "Codex",
                accent: Color(red: 0.17, green: 0.94, blue: 0.62),
                accentColor: NSColor(red: 0.17, green: 0.94, blue: 0.62, alpha: 1),
                markResourceName: "codex",
            )
        case .cursor:
            Self(
                id: providerID,
                name: "Cursor",
                accent: Color(red: 0.78, green: 1.00, blue: 0.10),
                accentColor: NSColor(red: 0.78, green: 1.00, blue: 0.10, alpha: 1),
                markResourceName: "cursor",
            )
        case .grok:
            Self(
                id: providerID,
                name: "Grok",
                accent: Color(red: 0.56, green: 0.67, blue: 1.00),
                accentColor: NSColor(red: 0.56, green: 0.67, blue: 1.00, alpha: 1),
                markResourceName: "grok",
            )
        case .githubCopilot:
            Self(
                id: providerID,
                name: "Copilot",
                accent: Color(red: 0.62, green: 0.68, blue: 1.00),
                accentColor: NSColor(red: 0.62, green: 0.68, blue: 1.00, alpha: 1),
                markResourceName: "copilot",
            )
        default:
            Self(
                id: providerID,
                name: providerID.rawValue.capitalized,
                accent: .white,
                accentColor: .white,
                markResourceName: nil,
            )
        }
    }
}

struct ProviderMark: View {
    let providerID: ProviderID
    let color: Color
    let size: CGFloat

    var body: some View {
        Group {
            if let mark = ProviderMarkResources.image(for: providerID) {
                Image(nsImage: mark)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: "circle.dotted")
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private enum ProviderMarkResources {
    private static var images: [String: NSImage] = [:]

    static func image(for providerID: ProviderID) -> NSImage? {
        guard let resourceName = ProviderStyle.resolve(providerID).markResourceName else {
            return nil
        }
        if let cached = images[resourceName] {
            return cached
        }

        let resourceURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: "svg",
            subdirectory: "ProviderMarks",
        ) ?? Bundle.main.url(forResource: resourceName, withExtension: "svg")
        guard let resourceURL, let image = NSImage(contentsOf: resourceURL) else {
            return nil
        }
        image.isTemplate = true
        images[resourceName] = image
        return image
    }
}

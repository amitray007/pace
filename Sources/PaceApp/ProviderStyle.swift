import AppKit
import PaceCore
import SwiftUI

struct ProviderStyle {
    let id: ProviderID
    let name: String
    let accent: Color
    let accentColor: NSColor
    let markResourceName: String?

    /// Brand colors for each provider.
    ///
    /// Claude's is taken from the provider mark Pace ships, which carries
    /// #D97757. OpenAI, Cursor, and xAI publish monochrome marks, so their
    /// accents come from the surface each brand actually presents rather than
    /// from an invented hue: near-white, which stays legible on the rail's
    /// black shell. GitHub Copilot uses GitHub's own accent blue, lightened so
    /// it holds up on black.
    ///
    /// These identify a provider. They do not report usage: the rail's arcs and
    /// the menu panel's quota bars stay on the usage-level palette, so an
    /// exhausted quota still reads as urgent whichever provider it belongs to.
    private static let brandColors: [ProviderID: (name: String, color: NSColor)] = [
        .claude: ("Claude", NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)),
        .codex: ("Codex", NSColor(white: 0.94, alpha: 1)),
        .cursor: ("Cursor", NSColor(white: 0.82, alpha: 1)),
        // A cooler white keeps xAI distinguishable from OpenAI at ring size.
        .grok: ("Grok", NSColor(srgbRed: 0.83, green: 0.86, blue: 0.90, alpha: 1)),
        .githubCopilot: (
            "Copilot",
            NSColor(srgbRed: 0.427, green: 0.635, blue: 1, alpha: 1)
        ),
    ]

    private static let markResourceNames: [ProviderID: String] = [
        .claude: "claude",
        .codex: "codex",
        .cursor: "cursor",
        .grok: "grok",
        .githubCopilot: "copilot",
    ]

    static func resolve(_ providerID: ProviderID) -> Self {
        let brand = brandColors[providerID]
        let color = brand?.color ?? .white
        return Self(
            id: providerID,
            name: brand?.name ?? providerID.rawValue.capitalized,
            accent: Color(nsColor: color),
            accentColor: color,
            markResourceName: markResourceNames[providerID],
        )
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

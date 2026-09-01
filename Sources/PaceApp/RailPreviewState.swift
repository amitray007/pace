import PaceCore

enum RailPreviewState: String, CaseIterable, Identifiable {
    case claude
    case codex
    case cursor
    case githubCopilot
    case grok
    case mini
    case rail

    var id: Self {
        self
    }

    var detailProviderID: ProviderID? {
        switch self {
        case .claude:
            .claude
        case .codex:
            .codex
        case .cursor:
            .cursor
        case .githubCopilot:
            .githubCopilot
        case .grok:
            .grok
        case .mini, .rail:
            nil
        }
    }
}

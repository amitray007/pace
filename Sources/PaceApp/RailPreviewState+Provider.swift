import PaceCore

extension RailPreviewState {
    init?(providerID: ProviderID) {
        switch providerID {
        case .claude:
            self = .claude
        case .codex:
            self = .codex
        case .cursor:
            self = .cursor
        case .githubCopilot:
            self = .githubCopilot
        case .grok:
            self = .grok
        default:
            return nil
        }
    }
}

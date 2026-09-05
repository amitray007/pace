import Foundation
import PaceCore
import PaceProviders

/// The one explicit retry that may ask macOS to release an existing provider
/// credential. Every other onboarding failure stays a normal error.
enum ProfileKeychainAuthorization: Equatable, Sendable {
    case claude(ClaudeProfile)
    case cursor(CursorProfile)

    var providerID: ProviderID {
        switch self {
        case .claude:
            .claude
        case .cursor:
            .cursor
        }
    }

    init?(
        error: any Error,
        providerID: ProviderID,
        directory: URL,
        claudeProfile: ClaudeProfile? = nil,
        cursorProfile: CursorProfile? = nil,
    ) {
        guard case let .unavailable(code) = error as? ProviderFailure else {
            return nil
        }
        switch (providerID, code) {
        case (.claude, "claude-credential-needs-authorization"):
            self = .claude(claudeProfile ?? ClaudeProfile(
                directory: directory,
                ownership: .existing,
            ))
        case (.cursor, "cursor-credential-needs-authorization"):
            self = .cursor(cursorProfile ?? CursorProfile.isolated(homeDirectory: directory))
        default:
            return nil
        }
    }
}

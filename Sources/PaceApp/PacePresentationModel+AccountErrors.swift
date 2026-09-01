import PaceCore
import PaceProviders

extension PacePresentationModel {
    static func accountErrorMessage(
        _ error: any Error,
        providerID: ProviderID? = nil,
    ) -> String {
        if let failure = error as? ProviderFailure {
            return providerFailureMessage(failure, providerID: providerID)
        }
        if let actionError = error as? ProviderProfileAccountOnboardingError {
            return actionError.message(providerID: providerID)
        }
        if let mutationError = error as? AccountMutationError {
            return accountMutationErrorMessage(mutationError)
        }
        return "The account change could not be completed."
    }

    static func providerFailureMessage(
        _ failure: ProviderFailure,
        providerID: ProviderID?,
    ) -> String {
        let name = providerName(providerID)
        return switch failure {
        case .signedOut:
            signedOutMessage(providerID: providerID, providerName: name)
        case .identityMismatch:
            identityMismatchMessage(providerID: providerID, providerName: name)
        case .rateLimited:
            "\(name) is temporarily rate limited. Try again later."
        case .failed:
            "\(name) could not verify this profile."
        case let .unavailable(code):
            unavailableMessage(code: code, providerName: name)
        }
    }

    static func providerName(_ providerID: ProviderID?) -> String {
        switch providerID {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        case .cursor:
            "Cursor"
        case .grok:
            "Grok"
        case .githubCopilot:
            "GitHub Copilot"
        default:
            "Provider"
        }
    }

    static func formattedProviderList(_ names: [String]) -> String {
        guard let last = names.last else {
            return "provider accounts"
        }
        guard names.count > 1 else {
            return last
        }
        return names.dropLast().joined(separator: ", ") + " and \(last)"
    }

    private static func signedOutMessage(
        providerID: ProviderID?,
        providerName: String,
    ) -> String {
        if providerID == .githubCopilot {
            "This GitHub CLI account is signed out. Run gh auth login, then try again."
        } else {
            "\(providerName) is signed out in this profile. Sign in with \(providerName), "
                + "then try again."
        }
    }

    private static func identityMismatchMessage(
        providerID: ProviderID?,
        providerName: String,
    ) -> String {
        if providerID == .githubCopilot {
            "This GitHub CLI login now resolves to a different GitHub account."
        } else {
            "This profile now belongs to a different \(providerName) account."
        }
    }

    private static func unavailableMessage(
        code: String,
        providerName: String,
    ) -> String {
        let messages = [
            "codex-executable-unavailable":
                "Install the Codex CLI before adding this account.",
            "github-cli-unavailable":
                "Install GitHub CLI before adding a GitHub Copilot account.",
            "github-cli-failed":
                "GitHub CLI could not read this account. Check gh auth status, then try again.",
            "github-copilot-not-entitled":
                "This GitHub account does not have an available Copilot entitlement.",
            "github-copilot-quota-unavailable":
                "GitHub Copilot did not return quota details for this account.",
            "grok-credential-unsupported":
                "This Grok profile uses an API key or custom issuer. "
                + "Pace only reads first-party Grok sessions.",
            "claude-profile-scope-missing":
                "This Claude login cannot read subscription usage. Sign in again with Claude Code.",
            "claude-credential-changed":
                "The Claude login changed during refresh. Try again.",
            "cursor-credential-changed":
                "The Cursor Agent login changed during refresh. Try again.",
            "cursor-credential-unavailable":
                "Cursor Agent credentials could not be read. Sign in again, then try again.",
        ]
        if let message = messages[code] {
            return message
        }
        return "\(providerName) is unavailable for this profile."
    }

    private static func accountMutationErrorMessage(_ error: AccountMutationError) -> String {
        switch error {
        case .emptyDisplayName:
            "Account names cannot be empty."
        case .duplicateDisplayName:
            "Choose a different account name for this provider."
        case .duplicateCredentialBinding:
            "This provider account source is already registered."
        default:
            "The account change could not be saved."
        }
    }
}

private extension ProviderProfileAccountOnboardingError {
    func message(providerID: ProviderID?) -> String {
        if providerID == .githubCopilot {
            return gitHubMessage
        }
        let providerName = switch providerID {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .grok: "Grok"
        default: "provider"
        }
        return switch self {
        case .identityAlreadyRegistered:
            "This \(providerName) identity is already registered from another profile folder."
        case .profileIdentityChanged:
            "This profile folder now belongs to a different \(providerName) identity. "
                + "Remove the old account before adding it again."
        case .profileNotDiscovered:
            "\(providerName) did not return an account for the selected profile folder."
        }
    }

    var gitHubMessage: String {
        switch self {
        case .identityAlreadyRegistered:
            "This GitHub identity is already registered from another GitHub CLI account."
        case .profileIdentityChanged:
            "This GitHub CLI login now belongs to a different GitHub identity. "
                + "Remove the old account before adding it again."
        case .profileNotDiscovered:
            "GitHub CLI did not return the selected GitHub account."
        }
    }
}

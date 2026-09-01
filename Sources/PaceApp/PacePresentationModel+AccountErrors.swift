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
        case .codex:
            "Codex"
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
        if code == "codex-executable-unavailable" {
            "Install the Codex CLI before adding this account."
        } else if code == "github-cli-unavailable" {
            "Install GitHub CLI before adding a GitHub Copilot account."
        } else if code == "github-cli-failed" {
            "GitHub CLI could not read this account. Check gh auth status, then try again."
        } else if code == "github-copilot-not-entitled" {
            "This GitHub account does not have an available Copilot entitlement."
        } else if code == "github-copilot-quota-unavailable" {
            "GitHub Copilot did not return quota details for this account."
        } else if code == "grok-credential-unsupported" {
            "This Grok profile uses an API key or custom issuer. Pace only reads first-party "
                + "Grok sessions."
        } else {
            "\(providerName) is unavailable for this profile."
        }
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
        let providerName = switch providerID {
        case .codex: "Codex"
        case .grok: "Grok"
        case .githubCopilot: "GitHub Copilot"
        default: "provider"
        }
        return switch self {
        case .identityAlreadyRegistered:
            if providerID == .githubCopilot {
                "This GitHub identity is already registered from another GitHub CLI account."
            } else {
                "This \(providerName) identity is already registered from another profile folder."
            }
        case .profileIdentityChanged:
            if providerID == .githubCopilot {
                "This GitHub CLI login now belongs to a different GitHub identity. "
                    + "Remove the old account before adding it again."
            } else {
                "This profile folder now belongs to a different \(providerName) identity. "
                    + "Remove the old account before adding it again."
            }
        case .profileNotDiscovered:
            if providerID == .githubCopilot {
                "GitHub CLI did not return the selected GitHub account."
            } else {
                "\(providerName) did not return an account for the selected profile folder."
            }
        }
    }
}

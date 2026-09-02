import Foundation
import PaceCore
import PaceProviders

/// The one path through which Pace lets macOS ask for keychain access.
///
/// Every other read runs under `KeychainInteractionPolicy` with prompts
/// disabled, so an account whose credential macOS will not release without
/// asking reports "keychain access needed" instead of raising the dialog.
/// This action re-reads that account with prompts allowed. The user sees the
/// dialogs once, together, when they chose to, and "Always Allow" then holds
/// for the installed build.
extension PacePresentationModel {
    /// Whether this account is waiting on a keychain approval.
    func needsKeychainAuthorization(_ account: ProviderAccount) -> Bool {
        KeychainInteractionPolicy.needsAuthorization(usageStatus(for: account).connectionIssue)
    }

    /// The selected account for the active provider, when it is waiting on a
    /// keychain approval.
    var selectedAccountAwaitingKeychain: ProviderAccount? {
        guard let selectedAccount, needsKeychainAuthorization(selectedAccount) else {
            return nil
        }
        return selectedAccount
    }

    /// Reads the account's credential with the macOS keychain dialog allowed,
    /// then refreshes it.
    ///
    /// Runs as an account operation so a refresh cannot start under the same
    /// window. The window is process-wide while it is open, which is
    /// acceptable here: the user asked for the dialogs.
    func authorizeKeychainAccess(for accountID: AccountID) async {
        guard !isProviderRuntimeBusy, !isManagingAccounts, !isRefreshing else {
            return
        }
        isManagingAccounts = true
        defer { isManagingAccounts = false }
        accountActionError = nil
        do {
            try await KeychainInteractionPolicy.allowingPrompts {
                try await self.refreshAccountIfAvailable(accountID)
            }
        } catch {
            accountActionError = Self.accountErrorMessage(error)
        }
    }
}

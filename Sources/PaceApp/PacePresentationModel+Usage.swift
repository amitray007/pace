import Foundation
import PaceCore

extension PacePresentationModel {
    var selectedAccount: ProviderAccount? {
        selectedAccount(for: activeProviderID)
    }

    var selectedSnapshots: [LimitSnapshot] {
        guard let selectedAccount else {
            return []
        }
        return snapshots(for: selectedAccount.id)
    }

    var selectedUsageStatus: AccountUsageStatus? {
        guard let selectedAccount else {
            return nil
        }
        return usageStatus(for: selectedAccount)
    }

    func accounts(for providerID: ProviderID) -> [ProviderAccount] {
        let providerAccounts = state.accounts.filter {
            $0.providerID == providerID && $0.isEnabled
        }
        if !isReferencePreview {
            return providerAccounts
                .filter { !$0.credentialBinding.isSimulated }
                .sorted { $0.order < $1.order }
        }
        let hasLiveAccount = providerAccounts.contains {
            !$0.credentialBinding.isSimulated
        }
        return providerAccounts
            .filter { !hasLiveAccount || !$0.credentialBinding.isSimulated }
            .sorted { $0.order < $1.order }
    }

    func selectedAccount(for providerID: ProviderID) -> ProviderAccount? {
        let selection = state.selections.first { $0.providerID == providerID }
        let availableAccounts = accounts(for: providerID)
        return availableAccounts.first { $0.id == selection?.accountID }
            ?? availableAccounts.first
    }

    /// The moment reset countdowns and freshness are measured from.
    ///
    /// Live surfaces measure from now. Reference previews measure from the
    /// simulated scenario's fixed date so captured frames stay identical
    /// between runs; using it on live data made every countdown drift by
    /// however long ago that date was.
    var presentationReferenceDate: Date {
        isReferencePreview ? SimulatedScenarios.referenceDate : Date()
    }

    func snapshots(for accountID: AccountID) -> [LimitSnapshot] {
        state.snapshots
            .filter { $0.id.accountID == accountID }
    }

    func usageStatus(for account: ProviderAccount) -> AccountUsageStatus {
        AccountUsageStatus(account: account, snapshots: snapshots(for: account.id))
    }

    func headlineUsage(for providerID: ProviderID) -> Double? {
        guard let account = selectedAccount(for: providerID) else {
            return nil
        }
        let snapshots = snapshots(for: account.id)
        let preferredBucketID: String? = switch providerID {
        case .claude:
            "current-session"
        case .codex:
            "monthly-limit"
        case .cursor:
            "included-usage"
        case .grok:
            "included-weekly"
        case .githubCopilot:
            "credits"
        default:
            nil
        }
        return snapshots.first { $0.id.bucketID.rawValue == preferredBucketID }?.usedFraction
            ?? snapshots.map(\.usedFraction).max()
    }
}

extension Date {
    /// Rounded down to a whole multiple of `interval` seconds.
    ///
    /// Used where a value feeds view state that is compared for equality: the
    /// displayed wording only changes by the minute, so a second-by-second date
    /// would report a change on every pass without altering anything shown.
    func rounded(toNearest interval: TimeInterval) -> Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 / interval).rounded(.down) * interval)
    }
}

import Foundation
import PaceCore

public enum ProductionProviderCatalog {
    public static func adapters(
        for accounts: [ProviderAccount],
    ) -> [any ProviderAdapter] {
        let codexProfiles = codexProfiles(for: accounts)
        guard !codexProfiles.isEmpty else {
            return []
        }
        return [CodexProviderAdapter(profiles: codexProfiles)]
    }

    public static func codexProfiles(for accounts: [ProviderAccount]) -> [CodexProfile] {
        var seenDirectories: Set<String> = []
        return accounts
            .filter { $0.providerID == .codex }
            .sorted(by: accountPrecedes)
            .compactMap { account in
                guard case let .providerProfile(directory, ownership) = account.credentialBinding
                else {
                    return nil
                }
                let canonicalPath = directory.standardizedFileURL.resolvingSymlinksInPath().path
                guard seenDirectories.insert(canonicalPath).inserted else {
                    return nil
                }
                return CodexProfile(
                    directory: directory,
                    ownership: ownership,
                    displayName: account.displayName,
                )
            }
    }

    private static func accountPrecedes(_ lhs: ProviderAccount, _ rhs: ProviderAccount) -> Bool {
        if lhs.order == rhs.order {
            return lhs.addedAt < rhs.addedAt
        }
        return lhs.order < rhs.order
    }
}

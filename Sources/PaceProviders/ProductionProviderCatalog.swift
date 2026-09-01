import Foundation
import PaceCore

public enum ProductionProviderCatalog {
    public static func adapters(
        for accounts: [ProviderAccount],
    ) -> [any ProviderAdapter] {
        var adapters: [any ProviderAdapter] = []
        let codexProfiles = codexProfiles(for: accounts)
        if !codexProfiles.isEmpty {
            adapters.append(CodexProviderAdapter(profiles: codexProfiles))
        }
        let grokProfiles = grokProfiles(for: accounts)
        if !grokProfiles.isEmpty {
            adapters.append(GrokProviderAdapter(profiles: grokProfiles))
        }
        return adapters
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

    public static func grokProfiles(for accounts: [ProviderAccount]) -> [GrokProfile] {
        var seenDirectories: Set<String> = []
        return accounts
            .filter { $0.providerID == .grok }
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
                return GrokProfile(
                    directory: directory,
                    ownership: ownership,
                    displayName: account.displayName,
                    expectedIdentity: account.identity,
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

import Foundation
import PaceCore

public enum ProductionProviderCatalog {
    public static func adapters(
        for accounts: [ProviderAccount],
    ) -> [any ProviderAdapter] {
        var adapters: [any ProviderAdapter] = []
        let claudeProfiles = claudeProfiles(for: accounts)
        if !claudeProfiles.isEmpty {
            adapters.append(ClaudeProviderAdapter(profiles: claudeProfiles))
        }
        let codexProfiles = codexProfiles(for: accounts)
        if !codexProfiles.isEmpty {
            adapters.append(CodexProviderAdapter(profiles: codexProfiles))
        }
        let cursorProfiles = cursorProfiles(for: accounts)
        if !cursorProfiles.isEmpty {
            adapters.append(CursorProviderAdapter(profiles: cursorProfiles))
        }
        let grokProfiles = grokProfiles(for: accounts)
        if !grokProfiles.isEmpty {
            adapters.append(GrokProviderAdapter(profiles: grokProfiles))
        }
        let githubCopilotProfiles = githubCopilotProfiles(for: accounts)
        if !githubCopilotProfiles.isEmpty {
            adapters.append(GitHubCopilotProviderAdapter(profiles: githubCopilotProfiles))
        }
        return adapters
    }

    public static func claudeProfiles(for accounts: [ProviderAccount]) -> [ClaudeProfile] {
        var seenDirectories: Set<String> = []
        return accounts
            .filter { $0.providerID == .claude }
            .sorted(by: accountPrecedes)
            .compactMap { account in
                let profile: ClaudeProfile
                switch account.credentialBinding {
                case let .claudeProfile(binding):
                    profile = ClaudeProfile(
                        directory: binding.configurationDirectory,
                        ownership: binding.ownership,
                        displayName: account.displayName,
                        expectedIdentity: account.identity,
                        secureStorageDirectory: binding.secureStorageDirectory,
                        keychainService: binding.keychainService,
                        keychainAccount: binding.keychainAccount,
                    )
                case let .providerProfile(directory, ownership):
                    let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
                        .appending(path: ".claude", directoryHint: .isDirectory)
                    let isScoped = directory.path != defaultDirectory.path
                    profile = ClaudeProfile(
                        directory: directory,
                        ownership: ownership,
                        displayName: account.displayName,
                        expectedIdentity: account.identity,
                        usesScopedSecureStorage: isScoped,
                    )
                default:
                    return nil
                }
                let sourceKey = [
                    profile.directory.path,
                    profile.secureStorageDirectory.path,
                    profile.keychainService,
                    profile.keychainAccount,
                ].joined(separator: "\u{0}")
                guard seenDirectories.insert(sourceKey).inserted else {
                    return nil
                }
                return profile
            }
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

    public static func cursorProfiles(for accounts: [ProviderAccount]) -> [CursorProfile] {
        let currentHome = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var seenSources: Set<CursorProfileSourceKey> = []
        return accounts
            .filter { $0.providerID == .cursor }
            .sorted(by: accountPrecedes)
            .compactMap { account in
                let directory: URL
                let credentialSource: CursorCredentialSource
                let ownership: ProfileOwnership
                switch account.credentialBinding {
                case let .cursorProfile(binding):
                    directory = binding.homeDirectory
                    credentialSource = binding.credentialSource
                    ownership = binding.ownership
                case let .providerProfile(legacyDirectory, legacyOwnership):
                    directory = legacyDirectory
                    ownership = legacyOwnership
                    let canonicalLegacyDirectory = legacyDirectory.standardizedFileURL
                        .resolvingSymlinksInPath()
                    credentialSource = canonicalLegacyDirectory == currentHome
                        ? .defaultKeychain
                        : .isolatedFile
                default:
                    return nil
                }
                let canonicalDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
                let sourceKey = CursorProfileSourceKey(
                    path: canonicalDirectory.path,
                    credentialSource: credentialSource,
                )
                guard seenSources.insert(sourceKey).inserted else {
                    return nil
                }
                return CursorProfile(
                    homeDirectory: canonicalDirectory,
                    credentialSource: credentialSource,
                    ownership: ownership,
                    displayName: account.displayName,
                    expectedIdentity: account.identity,
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

    public static func githubCopilotProfiles(
        for accounts: [ProviderAccount],
    ) -> [GitHubCopilotProfile] {
        var seenBindings: Set<GitHubCopilotBindingKey> = []
        return accounts
            .filter { $0.providerID == .githubCopilot }
            .sorted(by: accountPrecedes)
            .compactMap { account in
                guard case let .commandLineAccount(tool, login, configurationDirectory) =
                    account.credentialBinding,
                    tool.caseInsensitiveCompare(GitHubCopilotProfile.credentialTool) == .orderedSame
                else {
                    return nil
                }
                let canonicalDirectory = configurationDirectory?
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                let key = GitHubCopilotBindingKey(
                    login: login.lowercased(),
                    configurationPath: canonicalDirectory?.path,
                )
                guard seenBindings.insert(key).inserted else {
                    return nil
                }
                return GitHubCopilotProfile(
                    githubLogin: login,
                    configurationDirectory: canonicalDirectory,
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

private struct CursorProfileSourceKey: Hashable {
    let path: String
    let credentialSource: CursorCredentialSource
}

private struct GitHubCopilotBindingKey: Hashable {
    let login: String
    let configurationPath: String?
}

import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Production provider catalog")
struct ProductionProviderCatalogTests {
    @Test
    func `builds one Claude adapter from every registered real profile`() {
        var work = profileAccount(
            id: "10000000-0000-0000-0000-000000000002",
            providerID: .claude,
            path: "/profiles/claude/work",
            name: "Work",
        )
        work.isEnabled = false
        let personal = profileAccount(
            id: "10000000-0000-0000-0000-000000000001",
            providerID: .claude,
            path: "/profiles/claude/personal",
            name: "Personal",
        )

        let profiles = ProductionProviderCatalog.claudeProfiles(for: [work, personal])
        let adapters = ProductionProviderCatalog.adapters(for: [work, personal])

        #expect(profiles.map(\.directory.path) == [
            "/profiles/claude/work",
            "/profiles/claude/personal",
        ])
        #expect(profiles.map(\.expectedIdentity) == [work.identity, personal.identity])
        #expect(adapters.map(\.providerID) == [.claude])
    }

    @Test
    func `builds one Codex adapter from every registered real profile`() {
        var work = profileAccount(
            id: "20000000-0000-0000-0000-000000000002",
            providerID: .codex,
            path: "/profiles/codex/work",
            name: "Work",
        )
        work.isEnabled = false
        var personal = profileAccount(
            id: "20000000-0000-0000-0000-000000000001",
            providerID: .codex,
            path: "/profiles/codex/personal",
            name: "Personal",
        )
        personal.order = 1
        let cursor = profileAccount(
            id: "20000000-0000-0000-0000-000000000003",
            providerID: .cursor,
            path: "/profiles/cursor/personal",
            name: "Cursor",
        )

        let profiles = ProductionProviderCatalog.codexProfiles(
            for: [personal, cursor, work],
        )
        let adapters = ProductionProviderCatalog.adapters(
            for: [personal, cursor, work],
        )

        #expect(profiles.map(\.directory.path) == [
            "/profiles/codex/work",
            "/profiles/codex/personal",
        ])
        #expect(profiles.map(\.displayName) == ["Work", "Personal"])
        #expect(adapters.map(\.providerID) == [.codex])
    }

    @Test
    func `builds one Grok adapter from every registered real profile`() {
        var work = profileAccount(
            id: "30000000-0000-0000-0000-000000000002",
            providerID: .grok,
            path: "/profiles/grok/work",
            name: "Work",
        )
        work.isEnabled = false
        let personal = profileAccount(
            id: "30000000-0000-0000-0000-000000000001",
            providerID: .grok,
            path: "/profiles/grok/personal",
            name: "Personal",
        )

        let profiles = ProductionProviderCatalog.grokProfiles(for: [personal, work])
        let adapters = ProductionProviderCatalog.adapters(for: [personal, work])

        #expect(profiles.map(\.directory.path) == [
            "/profiles/grok/personal",
            "/profiles/grok/work",
        ])
        #expect(profiles.map(\.expectedIdentity) == [personal.identity, work.identity])
        #expect(adapters.map(\.providerID) == [.grok])
    }

    @Test
    func `orders production adapters deterministically`() {
        let claude = profileAccount(
            id: "10000000-0000-0000-0000-000000000008",
            providerID: .claude,
            path: "/profiles/claude/personal",
            name: "Claude",
        )
        let grok = profileAccount(
            id: "30000000-0000-0000-0000-000000000003",
            providerID: .grok,
            path: "/profiles/grok/personal",
            name: "Grok",
        )
        let codex = profileAccount(
            id: "20000000-0000-0000-0000-000000000008",
            providerID: .codex,
            path: "/profiles/codex/personal",
            name: "Codex",
        )

        let copilot = account(
            id: "40000000-0000-0000-0000-000000000009",
            providerID: .githubCopilot,
            binding: .commandLineAccount(
                tool: GitHubCopilotProfile.credentialTool,
                account: "personal",
                configurationDirectory: nil,
            ),
            name: "Copilot",
        )

        #expect(
            ProductionProviderCatalog.adapters(for: [copilot, grok, codex, claude])
                .map(\.providerID) == [
                    .claude,
                    .codex,
                    .grok,
                    .githubCopilot,
                ],
        )
    }

    @Test
    func `builds GitHub Copilot profiles from explicit CLI account bindings`() {
        let work = account(
            id: "40000000-0000-0000-0000-000000000002",
            providerID: .githubCopilot,
            binding: .commandLineAccount(
                tool: GitHubCopilotProfile.credentialTool,
                account: "work",
                configurationDirectory: URL(filePath: "/profiles/gh", directoryHint: .isDirectory),
            ),
            name: "Work",
        )
        let personal = account(
            id: "40000000-0000-0000-0000-000000000001",
            providerID: .githubCopilot,
            binding: .commandLineAccount(
                tool: GitHubCopilotProfile.credentialTool,
                account: "personal",
                configurationDirectory: nil,
            ),
            name: "Personal",
        )

        let profiles = ProductionProviderCatalog.githubCopilotProfiles(for: [work, personal])

        #expect(profiles.map(\.githubLogin) == ["work", "personal"])
        #expect(profiles.map(\.displayName) == ["Work", "Personal"])
        #expect(profiles.map(\.expectedIdentity) == [work.identity, personal.identity])
    }

    @Test
    func `ignores simulated and unsupported Codex credential bindings`() {
        let simulated = account(
            id: "20000000-0000-0000-0000-000000000004",
            providerID: .codex,
            binding: .simulated,
            name: "Fixture",
        )
        let keychain = account(
            id: "20000000-0000-0000-0000-000000000005",
            providerID: .codex,
            binding: .keychain(service: "codex", account: "unsupported"),
            name: "Keychain",
        )

        #expect(ProductionProviderCatalog.adapters(for: [simulated, keychain]).isEmpty)
    }

    @Test
    func `deduplicates profile paths that resolve through a symbolic link`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "pace-profile-catalog-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = directory.appending(path: "profile", directoryHint: .isDirectory)
        let alias = directory.appending(path: "alias", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: profile)

        let profiles = ProductionProviderCatalog.codexProfiles(for: [
            profileAccount(
                id: "20000000-0000-0000-0000-000000000006",
                providerID: .codex,
                path: profile.path,
                name: "Profile",
            ),
            profileAccount(
                id: "20000000-0000-0000-0000-000000000007",
                providerID: .codex,
                path: alias.path,
                name: "Alias",
            ),
        ])

        #expect(profiles.count == 1)
        #expect(profiles[0].directory.resolvingSymlinksInPath() == profile)
    }

    private func profileAccount(
        id: String,
        providerID: ProviderID,
        path: String,
        name: String,
    ) -> ProviderAccount {
        account(
            id: id,
            providerID: providerID,
            binding: .providerProfile(
                directory: URL(filePath: path, directoryHint: .isDirectory),
                ownership: .existing,
            ),
            name: name,
        )
    }

    private func account(
        id: String,
        providerID: ProviderID,
        binding: CredentialBinding,
        name: String,
    ) -> ProviderAccount {
        guard let uuid = UUID(uuidString: id) else {
            preconditionFailure("Invalid test UUID")
        }
        return ProviderAccount(
            id: AccountID(rawValue: uuid),
            providerID: providerID,
            identity: ProviderIdentity(subjectID: id),
            credentialBinding: binding,
            addedAt: Date(timeIntervalSince1970: 1_788_134_400),
            displayName: name,
            planName: nil,
            isEnabled: true,
            order: 0,
            connectionState: .needsAuthentication,
        )
    }
}

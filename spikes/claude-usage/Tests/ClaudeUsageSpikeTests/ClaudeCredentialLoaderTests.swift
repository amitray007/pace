@testable import ClaudeUsageSpikeCore
import Foundation
import Testing

@Suite("Claude credential loader")
struct ClaudeCredentialLoaderTests {
    @Test
    func `uses isolated keychain service for each custom profile`() {
        let defaultService = ClaudeCredentialLoader.keychainService(
            for: ClaudeProfileBinding.defaultProfile.configDirectory,
        )
        let first = ClaudeCredentialLoader.keychainService(
            for: URL(filePath: "/profiles/first", directoryHint: .isDirectory),
        )
        let second = ClaudeCredentialLoader.keychainService(
            for: URL(filePath: "/profiles/second", directoryHint: .isDirectory),
        )

        #expect(defaultService == "Claude Code-credentials")
        #expect(first.hasPrefix("Claude Code-credentials-"))
        #expect(first != second)
    }

    @Test
    func `prefers keychain and removes identical file candidate`() throws {
        let directory = try temporaryProfile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = credentialData(accessToken: "same")
        try data.write(to: directory.appending(path: ".credentials.json"))
        let loader = ClaudeCredentialLoader(keychain: StubKeychain(result: .success(data)))

        let candidates = try loader.load(
            for: ClaudeProfileBinding(configDirectory: directory),
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.source == .keychain)
    }

    @Test
    func `uses profile file when noninteractive keychain read fails`() throws {
        let directory = try temporaryProfile()
        defer { try? FileManager.default.removeItem(at: directory) }
        try credentialData(accessToken: "file-token")
            .write(to: directory.appending(path: ".credentials.json"))
        let loader = ClaudeCredentialLoader(
            keychain: StubKeychain(result: .failure(.credentialReadFailed)),
        )

        let candidates = try loader.load(
            for: ClaudeProfileBinding(configDirectory: directory),
        )

        #expect(candidates.map(\.source) == [.file])
    }

    @Test
    func `reports inaccessible keychain when no safe fallback exists`() throws {
        let directory = try temporaryProfile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = ClaudeCredentialLoader(
            keychain: StubKeychain(result: .failure(.credentialReadFailed)),
        )

        #expect(throws: ClaudeSpikeError.credentialReadFailed) {
            try loader.load(for: ClaudeProfileBinding(configDirectory: directory))
        }
    }

    @Test
    func `parses hex encoded keychain value without exposing token`() throws {
        let source = credentialData(accessToken: "hex-token")
        let hex = source.map { String(format: "%02x", $0) }.joined()

        let credential = try ClaudeCredentialLoader.parseCredential(Data(hex.utf8))

        #expect(credential.canReadUsage)
        #expect(credential.subscriptionType == "max")
    }

    @Test
    func `distinguishes malformed credential from signed out`() throws {
        let directory = try temporaryProfile()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-json".utf8).write(to: directory.appending(path: ".credentials.json"))
        let loader = ClaudeCredentialLoader(keychain: StubKeychain(result: .success(nil)))

        #expect(throws: ClaudeSpikeError.invalidCredential) {
            try loader.load(for: ClaudeProfileBinding(configDirectory: directory))
        }
    }

    private func temporaryProfile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pace-claude-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func credentialData(accessToken: String) -> Data {
        Data(
            """
            {
              "claudeAiOauth": {
                "accessToken": "\(accessToken)",
                "refreshToken": "refresh",
                "expiresAt": 4102444800000,
                "subscriptionType": "max",
                "rateLimitTier": "default_claude_max_20x",
                "scopes": ["user:profile", "user:inference"]
              }
            }
            """.utf8,
        )
    }
}

private struct StubKeychain: ClaudeKeychainReading {
    let result: Result<Data?, ClaudeSpikeError>

    func readGenericPassword(service _: String) throws -> Data? {
        try result.get()
    }
}

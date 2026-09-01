import Foundation
@testable import PaceProviders
import Testing

@Suite("Claude credential store")
struct ClaudeCredentialStoreTests {
    @Test
    func `uses a separate keychain service for each custom profile`() {
        let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)
        let defaultService = ClaudeProfile.current(
            environment: ["USER": "test-user"],
            homeDirectory: home,
        ).keychainService
        let first = ClaudeProfile.current(
            environment: ["CLAUDE_CONFIG_DIR": "/profiles/first", "USER": "test-user"],
            homeDirectory: home,
        ).keychainService
        let second = ClaudeProfile.current(
            environment: ["CLAUDE_CONFIG_DIR": "/profiles/second", "USER": "test-user"],
            homeDirectory: home,
        ).keychainService

        #expect(defaultService == "Claude Code-credentials")
        #expect(first == "Claude Code-credentials-fb79f343")
        #expect(first.hasPrefix("Claude Code-credentials-"))
        #expect(first != second)
    }

    @Test
    func `secure storage environment overrides config and preserves unscoped empty selector`() {
        let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)
        let custom = ClaudeProfile.current(
            environment: [
                "CLAUDE_CONFIG_DIR": "/config/custom",
                "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/secure/custom",
                "USER": "test-user",
            ],
            homeDirectory: home,
        )
        let unscoped = ClaudeProfile.current(
            environment: [
                "CLAUDE_CONFIG_DIR": "/config/custom",
                "CLAUDE_SECURESTORAGE_CONFIG_DIR": "",
                "USER": "not valid!",
            ],
            homeDirectory: home,
        )
        let emptyUser = ClaudeProfile.current(environment: ["USER": ""], homeDirectory: home)
        let relative = ClaudeProfile.current(
            environment: [
                "CLAUDE_CONFIG_DIR": "relative-profile",
                "USER": "test-user",
            ],
            homeDirectory: home,
        )
        let relativeSecureStorage = ClaudeProfile.current(
            environment: [
                "CLAUDE_CONFIG_DIR": "/config/custom",
                "CLAUDE_SECURESTORAGE_CONFIG_DIR": "relative-secure-storage",
                "USER": "test-user",
            ],
            homeDirectory: home,
        )

        #expect(custom.directory.path == "/config/custom")
        #expect(custom.secureStorageDirectory.path == "/secure/custom")
        #expect(custom.keychainService == "Claude Code-credentials-ca97ba87")
        #expect(custom.keychainAccount == "test-user")
        #expect(unscoped.secureStorageDirectory.path == "/Users/test/.claude")
        #expect(unscoped.keychainService == "Claude Code-credentials")
        #expect(unscoped.keychainAccount == "claude-code-user")
        #expect(emptyUser.keychainAccount == NSUserName())
        #expect(!relative.isCredentialBindingValid)
        #expect(!relativeSecureStorage.isCredentialBindingValid)
        #expect(throws: ClaudeProviderError.invalidProfile) {
            try ClaudeCredentialStore(keychain: ClaudeStubKeychain(records: [:])).load(
                for: relative,
            )
        }
    }

    @Test
    func `loads only the selected owner private profile`() throws {
        let directory = try temporaryProfile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = ClaudeProfile(directory: directory, ownership: .existing)
        let credentialURL = directory.appending(path: ".credentials.json")
        try ClaudeTestSupport.credentialDocument(
            ClaudeTestSupport.credential(accessToken: "selected"),
        ).write(to: credentialURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialURL.path,
        )
        let keychain = ClaudeStubKeychain(records: [:])

        let candidates = try ClaudeCredentialStore(keychain: keychain).load(for: profile)

        #expect(candidates.map(\.credential.accessToken) == ["selected"])
        #expect(keychain.readServices == [profile.keychainService])
    }

    @Test
    func `rejects group readable and symbolic link credential files`() throws {
        let directory = try temporaryProfile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = ClaudeProfile(directory: directory, ownership: .existing)
        let credentialURL = directory.appending(path: ".credentials.json")
        try ClaudeTestSupport.credentialDocument(ClaudeTestSupport.credential())
            .write(to: credentialURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o640],
            ofItemAtPath: credentialURL.path,
        )

        #expect(throws: ClaudeProviderError.insecureCredentialFile) {
            try ClaudeCredentialStore(keychain: ClaudeStubKeychain(records: [:])).load(for: profile)
        }

        try FileManager.default.removeItem(at: credentialURL)
        let target = directory.appending(path: "credential-target.json")
        try ClaudeTestSupport.credentialDocument(ClaudeTestSupport.credential()).write(to: target)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: target.path,
        )
        try FileManager.default.createSymbolicLink(at: credentialURL, withDestinationURL: target)

        #expect(throws: ClaudeProviderError.invalidCredential) {
            try ClaudeCredentialStore(keychain: ClaudeStubKeychain(records: [:])).load(for: profile)
        }
    }

    @Test
    func `updates provider owned file only when generation is unchanged`() throws {
        let directory = try temporaryProfile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = ClaudeProfile(directory: directory, ownership: .existing)
        let credentialURL = directory.appending(path: ".credentials.json")
        try ClaudeTestSupport.credentialDocument(
            ClaudeTestSupport.credential(accessToken: "old", refreshToken: "old-refresh"),
        ).write(to: credentialURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialURL.path,
        )
        let store = ClaudeCredentialStore(keychain: ClaudeStubKeychain(records: [:]))
        let candidates = try store.load(for: profile)
        var updated = try #require(candidates.first)
        updated.credential.accessToken = "new"
        updated.credential.refreshToken = "new-refresh"

        _ = try store.save(
            updated,
            ifUnchanged: ClaudeCredentialGeneration(candidates),
            for: profile,
        )

        let saved = try #require(store.load(for: profile).first)
        #expect(saved.credential.accessToken == "new")
        #expect(saved.credential.refreshToken == "new-refresh")
        let object = try #require(
            JSONSerialization.jsonObject(with: saved.originalDocument) as? [String: Any],
        )
        #expect((object["preserved"] as? [String: Bool])?["value"] == true)
        let attributes = try FileManager.default.attributesOfItem(atPath: credentialURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        let staleGeneration = ClaudeCredentialGeneration(candidates)
        #expect(throws: ClaudeProviderError.credentialChanged) {
            try store.save(updated, ifUnchanged: staleGeneration, for: profile)
        }
    }

    @Test
    func `waits for Claude storage lock before generation check and write`() async throws {
        let directory = try temporaryProfile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = ClaudeProfile(directory: directory, ownership: .existing)
        let credentialURL = directory.appending(path: ".credentials.json")
        try ClaudeTestSupport.credentialDocument(
            ClaudeTestSupport.credential(accessToken: "old"),
        ).write(to: credentialURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialURL.path,
        )
        let store = ClaudeCredentialStore(keychain: ClaudeStubKeychain(records: [:]))
        let candidates = try store.load(for: profile)
        var updated = try #require(candidates.first)
        updated.credential.accessToken = "new"
        let heldLock = try ClaudeCompatibleFileLock.acquire(
            at: directory.appending(path: ".storage-write.lock", directoryHint: .isDirectory),
            staleAfter: 15,
            retries: 0,
            minimumDelay: 0,
            maximumDelay: 0,
        )
        let save = Task.detached {
            try store.save(
                updated,
                ifUnchanged: ClaudeCredentialGeneration(candidates),
                for: profile,
            )
        }

        try await Task.sleep(for: .milliseconds(150))
        #expect(try store.load(for: profile).first?.credential.accessToken == "old")
        ClaudeCompatibleFileLock.release(heldLock)
        _ = try await save.value

        #expect(try store.load(for: profile).first?.credential.accessToken == "new")
    }

    @Test
    func `preserves hex keychain encoding during rotation`() throws {
        let directory = try temporaryProfile()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = ClaudeProfile(
            directory: directory,
            ownership: .existing,
            keychainAccount: "test-user",
        )
        let service = profile.keychainService
        let data = ClaudeTestSupport.credentialDocument(
            ClaudeTestSupport.credential(accessToken: "old"),
        )
        let hex = Data(data.map { String(format: "%02x", $0) }.joined().utf8)
        let keychain = ClaudeStubKeychain(records: [
            service: ClaudeKeychainRecord(account: "test-user", data: hex),
        ])
        let store = ClaudeCredentialStore(keychain: keychain)
        let candidates = try store.load(for: profile)
        var updated = try #require(candidates.first)
        updated.credential.accessToken = "new"

        _ = try store.save(
            updated,
            ifUnchanged: ClaudeCredentialGeneration(candidates),
            for: profile,
        )

        let write = try #require(keychain.writes.first)
        #expect(write.service == service)
        #expect(write.account == "test-user")
        #expect(String(data: write.data, encoding: .utf8)?.allSatisfy(\.isHexDigit) == true)
    }

    private func temporaryProfile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "pace-claude-store-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class ClaudeStubKeychain: ClaudeKeychainAccessing, @unchecked Sendable {
    struct Write: Equatable {
        let service: String
        let account: String
        let data: Data
    }

    private let lock = NSLock()
    private var records: [String: ClaudeKeychainRecord]
    private var mutableReadServices: [String] = []
    private var mutableWrites: [Write] = []

    init(records: [String: ClaudeKeychainRecord]) {
        self.records = records
    }

    func readGenericPassword(
        service: String,
        account: String,
    ) throws(ClaudeProviderError) -> ClaudeKeychainRecord? {
        lock.withLock {
            mutableReadServices.append(service)
            guard records[service]?.account == account else {
                return nil
            }
            return records[service]
        }
    }

    func updateGenericPassword(
        service: String,
        account: String,
        data: Data,
    ) throws(ClaudeProviderError) {
        lock.withLock {
            guard records[service]?.account == account else {
                return
            }
            records[service] = ClaudeKeychainRecord(account: account, data: data)
            mutableWrites.append(Write(service: service, account: account, data: data))
        }
    }

    var readServices: [String] {
        lock.withLock { mutableReadServices }
    }

    var writes: [Write] {
        lock.withLock { mutableWrites }
    }
}

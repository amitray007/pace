import Foundation
@testable import PaceProviders
import Testing

@Suite("Grok credential loading")
struct GrokCredentialLoaderTests {
    @Test
    func `loads only the selected owner private profile`() throws {
        let first = try makeProfile(name: "first", userID: "user-a")
        let second = try makeProfile(name: "second", userID: "user-b")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let loader = GrokCredentialLoader(now: { GrokTestSupport.observedAt })

        let credential = try loader.load(for: GrokProfile(
            directory: second,
            ownership: .existing,
        ))

        #expect(credential.accessToken == "token-user-b")
    }

    @Test
    func `rejects group readable and symbolic link credential files`() throws {
        let publicProfile = try makeProfile(
            name: "public",
            userID: "user-a",
            permissions: 0o640,
        )
        let linkedProfile = try makeProfile(name: "linked-source", userID: "user-b")
        let linkDirectory = FileManager.default.temporaryDirectory.appending(
            path: "pace-grok-tests-\(UUID().uuidString)-link",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(
            at: linkDirectory,
            withIntermediateDirectories: true,
        )
        try FileManager.default.createSymbolicLink(
            at: linkDirectory.appending(path: "auth.json"),
            withDestinationURL: linkedProfile.appending(path: "auth.json"),
        )
        defer {
            try? FileManager.default.removeItem(at: publicProfile)
            try? FileManager.default.removeItem(at: linkedProfile)
            try? FileManager.default.removeItem(at: linkDirectory)
        }

        #expect(throws: GrokProviderError.insecureCredentialFile) {
            try GrokCredentialLoader().load(for: GrokProfile(
                directory: publicProfile,
                ownership: .existing,
            ))
        }
        #expect(throws: GrokProviderError.invalidCredential) {
            try GrokCredentialLoader().load(for: GrokProfile(
                directory: linkDirectory,
                ownership: .existing,
            ))
        }
    }

    @Test
    func `rejects API keys and expired sessions before network use`() throws {
        let apiKey = try makeProfile(
            name: "api-key",
            document: #"{"xai::api_key":{"key":"xai-redacted","auth_mode":"api_key"}}"#,
        )
        let expired = try makeProfile(
            name: "expired",
            userID: "user-a",
            expiresAt: "2026-01-01T00:00:00Z",
        )
        defer {
            try? FileManager.default.removeItem(at: apiKey)
            try? FileManager.default.removeItem(at: expired)
        }

        #expect(throws: GrokProviderError.unsupportedCredential) {
            try GrokCredentialLoader().load(for: GrokProfile(
                directory: apiKey,
                ownership: .existing,
            ))
        }
        #expect(throws: GrokProviderError.invalidCredential) {
            try GrokCredentialLoader(now: { GrokTestSupport.observedAt }).load(for: GrokProfile(
                directory: expired,
                ownership: .existing,
            ))
        }
    }

    private func makeProfile(
        name: String,
        userID: String,
        permissions: Int = 0o600,
        expiresAt: String = "2027-01-01T00:00:00Z",
    ) throws -> URL {
        try makeProfile(
            name: name,
            document: """
            {
              "scope": {
                "key": "token-\(userID)",
                "auth_mode": "oidc",
                "user_id": "\(userID)",
                "expires_at": "\(expiresAt)",
                "oidc_issuer": "https://auth.x.ai"
              }
            }
            """,
            permissions: permissions,
        )
    }

    private func makeProfile(
        name: String,
        document: String,
        permissions: Int = 0o600,
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "pace-grok-tests-\(UUID().uuidString)-\(name)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let credential = directory.appending(path: "auth.json")
        try Data(document.utf8).write(to: credential)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: credential.path,
        )
        return directory
    }
}

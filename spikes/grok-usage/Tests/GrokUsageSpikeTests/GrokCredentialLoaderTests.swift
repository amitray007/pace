import Foundation
@testable import GrokUsageSpikeCore
import Testing

@Suite("Grok credential loading")
struct GrokCredentialLoaderTests {
    @Test
    func `loads only the selected private profile`() throws {
        let first = try makeProfile(name: "first", userID: "user-a")
        let second = try makeProfile(name: "second", userID: "user-b")
        let loader = GrokCredentialLoader(now: { GrokSpikeTestSupport.referenceDate })

        let credential = try loader.load(for: second.binding)

        #expect(credential.localIdentity.userID == "user-b")
        #expect(credential.accessToken == "token-user-b")
        #expect(first.binding.processEnvironment(inheriting: [:])["GROK_HOME"] == first.root.path)
    }

    @Test
    func `rejects group readable credential file`() throws {
        let profile = try makeProfile(name: "public", userID: "user-a", permissions: 0o640)

        #expect(throws: GrokSpikeError.insecureCredentialFile) {
            try GrokCredentialLoader().load(for: profile.binding)
        }
    }

    @Test
    func `rejects multiple usable credentials`() throws {
        let profile = try makeProfile(
            name: "ambiguous",
            document: """
            {
              "scope-a": \(credentialJSON(userID: "user-a")),
              "scope-b": \(credentialJSON(userID: "user-b"))
            }
            """,
        )

        #expect(throws: GrokSpikeError.ambiguousCredential) {
            try GrokCredentialLoader().load(for: profile.binding)
        }
    }

    @Test
    func `distinguishes API key from signed out session`() throws {
        let profile = try makeProfile(
            name: "api-key",
            document: """
            {"xai::api_key":{"key":"xai-redacted","auth_mode":"api_key"}}
            """,
        )

        #expect(throws: GrokSpikeError.unsupportedCredential) {
            try GrokCredentialLoader().load(for: profile.binding)
        }
    }

    @Test
    func `does not send a custom issuer credential to xAI`() throws {
        let profile = try makeProfile(
            name: "enterprise",
            document: """
            {"scope":\(credentialJSON(userID: "user-a", issuer: "https://id.example.com"))}
            """,
        )

        #expect(throws: GrokSpikeError.unsupportedCredential) {
            try GrokCredentialLoader().load(for: profile.binding)
        }
    }

    @Test
    func `rejects expired session before network use`() throws {
        let profile = try makeProfile(
            name: "expired",
            document: """
            {"scope":\(credentialJSON(
                userID: "user-a",
                expiresAt: "2026-01-01T00:00:00Z",
            ))}
            """,
        )

        #expect(throws: GrokSpikeError.invalidCredential) {
            try GrokCredentialLoader(now: { GrokSpikeTestSupport.referenceDate })
                .load(for: profile.binding)
        }
    }

    private func makeProfile(
        name: String,
        userID: String,
        permissions: Int = 0o600,
    ) throws -> TemporaryProfile {
        try makeProfile(
            name: name,
            document: "{\"scope\":\(credentialJSON(userID: userID))}",
            permissions: permissions,
        )
    }

    private func makeProfile(
        name: String,
        document: String,
        permissions: Int = 0o600,
    ) throws -> TemporaryProfile {
        let root = FileManager.default.temporaryDirectory
            .appending(
                path: "pace-grok-tests-\(UUID().uuidString)-\(name)",
                directoryHint: .isDirectory,
            )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "auth.json")
        try Data(document.utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: file.path,
        )
        return TemporaryProfile(root: root)
    }

    private func credentialJSON(
        userID: String,
        expiresAt: String = "2027-01-01T00:00:00Z",
        issuer: String = "https://auth.x.ai",
    ) -> String {
        """
        {
          "key": "token-\(userID)",
          "auth_mode": "oidc",
          "user_id": "\(userID)",
          "principal_id": "principal-\(userID)",
          "expires_at": "\(expiresAt)",
          "oidc_issuer": "\(issuer)"
        }
        """
    }
}

private struct TemporaryProfile {
    let root: URL

    var binding: GrokProfileBinding {
        GrokProfileBinding(grokHome: root)
    }
}

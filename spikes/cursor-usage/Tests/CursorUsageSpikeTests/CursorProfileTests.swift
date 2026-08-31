@testable import CursorUsageSpikeCore
import Foundation
import Testing

@Suite("Cursor profile and credentials")
struct CursorProfileTests {
    @Test
    func `isolated profile owns config data and file credentials`() {
        let profile = CursorSpikeTestSupport.profile("work")
        let environment = profile.processEnvironment(inheriting: ["PATH": "/bin"])

        #expect(environment["PATH"] == "/bin")
        #expect(environment["HOME"] == "/profiles/work")
        #expect(environment["CURSOR_CONFIG_DIR"] == "/profiles/work/.cursor")
        #expect(environment["CURSOR_DATA_DIR"] == "/profiles/work/.cursor")
        #expect(environment["AGENT_CLI_CREDENTIAL_STORE"] == "file")
        #expect(profile.credentialFile.path == "/profiles/work/.cursor/auth.json")
    }

    @Test
    func `default profile does not override inherited environment`() {
        let base = ["HOME": "/real-home", "PATH": "/bin"]
        #expect(CursorProfileBinding.defaultProfile.processEnvironment(inheriting: base) == base)
    }

    @Test
    func `parses only the required access token from file credentials`() throws {
        let token = CursorSpikeTestSupport.token()
        let data = Data(
            "{\"accessToken\":\"\(token)\",\"refreshToken\":\"must-not-escape\"}".utf8,
        )

        let credential = try CursorCredentialLoader.parseCredential(
            data,
            authID: "auth0|user-a",
            source: .isolatedFile,
        )

        #expect(credential == CursorCredential(
            accessToken: token,
            authID: "auth0|user-a",
            source: .isolatedFile,
        ))
    }

    @Test
    func `rejects malformed credential document`() {
        #expect(throws: CursorSpikeError.invalidCredential) {
            try CursorCredentialLoader.parseCredential(
                Data("{}".utf8),
                authID: "auth0|user-a",
                source: .isolatedFile,
            )
        }
    }

    @Test
    func `identity decoder accepts server identity with numeric identifiers`() throws {
        let remote = try CursorIdentityDecoder.decode(Data(
            """
            {
              "authId": "auth0|hidden",
              "email": "hidden@example.invalid",
              "userId": 42,
              "firstName": "Hidden",
              "lastName": "Person",
              "teamId": 7
            }
            """.utf8,
        ))

        #expect(remote.authID == "auth0|hidden")
        #expect(remote.identity.userID == "42")
        #expect(remote.identity.teamID == "7")
        #expect(remote.identity.displayName == "Hidden Person")
    }

    @Test
    func `identity decoder rejects missing stable identity`() {
        #expect(throws: CursorSpikeError.invalidResponse) {
            try CursorIdentityDecoder.decode(Data(#"{"authId":"auth0|hidden"}"#.utf8))
        }
    }
}

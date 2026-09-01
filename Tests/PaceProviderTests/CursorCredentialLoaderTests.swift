import Foundation
@testable import PaceProviders
import Testing

@Suite("Cursor credential loading")
struct CursorCredentialLoaderTests {
    @Test
    func `loads exact default keychain account with CLI identity binding`() throws {
        let home = try makeProfileHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeConfiguration(authenticationID: "auth0|default", home: home)
        let accessToken = CursorTestSupport.token(
            subject: "auth0|default",
            expiresAt: CursorTestSupport.observedAt.addingTimeInterval(3600),
        )
        let keychain = CursorStubKeychain(records: [
            CursorCredentialLoader.accessTokenService:
                .success(CursorKeychainRecord(data: Data(accessToken.utf8))),
            CursorCredentialLoader.refreshTokenService:
                .success(CursorKeychainRecord(data: Data("refresh-default".utf8))),
        ])

        let credential = try CursorCredentialLoader(keychain: keychain).load(
            for: .current(homeDirectory: home),
        )

        #expect(credential.accessToken == accessToken)
        #expect(credential.refreshToken == "refresh-default")
        #expect(credential.authenticationID == "auth0|default")
        #expect(credential.source == .defaultKeychain)
    }

    @Test
    func `loads only an owner private isolated credential file`() throws {
        let home = try makeProfileHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeConfiguration(authenticationID: "auth0|isolated", home: home)
        try writeCredential(
            accessToken: "access-isolated",
            refreshToken: "refresh-isolated",
            home: home,
            permissions: 0o600,
        )

        let credential = try CursorCredentialLoader().load(
            for: .isolated(homeDirectory: home),
        )

        #expect(credential.accessToken == "access-isolated")
        #expect(credential.refreshToken == "refresh-isolated")
        #expect(credential.authenticationID == "auth0|isolated")
        #expect(credential.source == .isolatedFile)
    }

    @Test
    func `rejects group readable and symbolic link credential files`() throws {
        let groupReadable = try makeProfileHome()
        let symbolic = try makeProfileHome()
        defer {
            try? FileManager.default.removeItem(at: groupReadable)
            try? FileManager.default.removeItem(at: symbolic)
        }
        try writeConfiguration(authenticationID: "auth0|group", home: groupReadable)
        try writeCredential(
            accessToken: "access",
            refreshToken: "refresh",
            home: groupReadable,
            permissions: 0o640,
        )

        #expect(throws: CursorProviderError.insecureCredentialFile) {
            try CursorCredentialLoader().load(for: .isolated(homeDirectory: groupReadable))
        }

        try writeConfiguration(authenticationID: "auth0|symbolic", home: symbolic)
        let target = symbolic.appending(path: "credential-target.json")
        try Data(#"{"accessToken":"access","refreshToken":"refresh"}"#.utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(
            at: symbolic.appending(path: ".cursor/auth.json"),
            withDestinationURL: target,
        )

        #expect(throws: CursorProviderError.insecureCredentialFile) {
            try CursorCredentialLoader().load(for: .isolated(homeDirectory: symbolic))
        }
    }

    @Test
    func `distinguishes signed out from inaccessible keychain`() throws {
        let home = try makeProfileHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeConfiguration(authenticationID: "auth0|default", home: home)

        #expect(throws: CursorProviderError.signedOut) {
            try CursorCredentialLoader(keychain: CursorStubKeychain(records: [:])).load(
                for: .current(homeDirectory: home),
            )
        }
        let inaccessible = CursorStubKeychain(records: [
            CursorCredentialLoader.accessTokenService: .failure(.credentialReadFailed),
        ])
        #expect(throws: CursorProviderError.credentialReadFailed) {
            try CursorCredentialLoader(keychain: inaccessible).load(
                for: .current(homeDirectory: home),
            )
        }
    }

    private func makeProfileHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "pace-cursor-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: home.appending(path: ".cursor", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        return home
    }

    private func writeConfiguration(authenticationID: String, home: URL) throws {
        let data = Data(#"{"authInfo":{"authId":"\#(authenticationID)"}}"#.utf8)
        try data.write(to: home.appending(path: ".cursor/cli-config.json"))
    }

    private func writeCredential(
        accessToken: String,
        refreshToken: String,
        home: URL,
        permissions: Int,
    ) throws {
        let data = Data(
            #"{"accessToken":"\#(accessToken)","refreshToken":"\#(refreshToken)"}"#.utf8,
        )
        let url = home.appending(path: ".cursor/auth.json")
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path,
        )
    }
}

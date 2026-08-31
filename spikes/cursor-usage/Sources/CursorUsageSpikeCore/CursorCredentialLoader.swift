import Foundation
import LocalAuthentication
import Security

public protocol CursorCredentialLoading: Sendable {
    func load(for profile: CursorProfileBinding) throws -> CursorCredential
}

public struct CursorCredentialLoader: CursorCredentialLoading {
    private static let maximumCredentialSize = 1_048_576
    private static let accessTokenService = "cursor-access-token"
    private static let keychainAccount = "cursor-user"

    public init() {}

    public func load(for profile: CursorProfileBinding) throws -> CursorCredential {
        let authID = try loadAuthID(at: profile.cliConfigFile)
        return switch profile.credentialStore {
        case .defaultKeychain:
            try loadKeychainCredential(authID: authID)
        case .isolatedFile:
            try loadFileCredential(at: profile.credentialFile, authID: authID)
        }
    }

    private func loadKeychainCredential(authID: String) throws -> CursorCredential {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.accessTokenService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw CursorSpikeError.invalidCredential
            }
            return try Self.parseCredential(
                data,
                authID: authID,
                source: .defaultKeychain,
            )
        case errSecItemNotFound:
            throw CursorSpikeError.signedOut
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw CursorSpikeError.credentialReadFailed
        default:
            throw CursorSpikeError.credentialReadFailed
        }
    }

    private func loadFileCredential(at url: URL, authID: String) throws -> CursorCredential {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
            ])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw CursorSpikeError.signedOut
        } catch {
            throw CursorSpikeError.credentialReadFailed
        }

        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= Self.maximumCredentialSize
        else {
            throw CursorSpikeError.invalidCredential
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw CursorSpikeError.credentialReadFailed
        }
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0
        else {
            throw CursorSpikeError.insecureCredentialFile
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw CursorSpikeError.credentialReadFailed
        }
        return try Self.parseCredential(
            data,
            authID: authID,
            source: .isolatedFile,
        )
    }

    private func loadAuthID(at url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw CursorSpikeError.signedOut
        } catch {
            throw CursorSpikeError.credentialReadFailed
        }
        guard data.count <= Self.maximumCredentialSize else {
            throw CursorSpikeError.invalidCredential
        }

        let config: CLIConfig
        do {
            config = try JSONDecoder().decode(CLIConfig.self, from: data)
        } catch {
            throw CursorSpikeError.invalidCredential
        }
        let authID = config.authInfo.authID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authID.isEmpty else {
            throw CursorSpikeError.invalidCredential
        }
        return authID
    }

    static func parseCredential(
        _ data: Data,
        authID: String,
        source: CursorCredentialStore,
    ) throws -> CursorCredential {
        guard data.count <= maximumCredentialSize else {
            throw CursorSpikeError.invalidCredential
        }

        let accessToken: String
        switch source {
        case .defaultKeychain:
            guard let value = String(data: data, encoding: .utf8) else {
                throw CursorSpikeError.invalidCredential
            }
            accessToken = value
        case .isolatedFile:
            let document: CredentialDocument
            do {
                document = try JSONDecoder().decode(CredentialDocument.self, from: data)
            } catch {
                throw CursorSpikeError.invalidCredential
            }
            accessToken = document.accessToken
        }

        let trimmed = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CursorSpikeError.invalidCredential
        }
        let trimmedAuthID = authID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthID.isEmpty else {
            throw CursorSpikeError.invalidCredential
        }
        return CursorCredential(
            accessToken: trimmed,
            authID: trimmedAuthID,
            source: source,
        )
    }
}

private struct CredentialDocument: Decodable {
    let accessToken: String
}

private struct CLIConfig: Decodable {
    let authInfo: AuthInfo
}

private struct AuthInfo: Decodable {
    let authID: String

    enum CodingKeys: String, CodingKey {
        case authID = "authId"
    }
}

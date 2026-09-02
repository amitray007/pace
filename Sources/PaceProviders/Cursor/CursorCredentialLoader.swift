import Darwin
import Foundation
import Security

protocol CursorCredentialLoading: Sendable {
    func load(for profile: CursorProfile) throws(CursorProviderError) -> CursorCredential
}

struct CursorKeychainRecord: Equatable, Sendable {
    let data: Data
}

protocol CursorKeychainReading: Sendable {
    func readGenericPassword(
        service: String,
        account: String,
    ) throws(CursorProviderError) -> CursorKeychainRecord?
}

struct CursorSecurityKeychainReader: CursorKeychainReading {
    func readGenericPassword(
        service: String,
        account: String,
    ) throws(CursorProviderError) -> CursorKeychainRecord? {
        // Whether this read may show the macOS keychain dialog is decided by
        // `KeychainInteractionPolicy`, not by the query. Cursor stores these
        // items in the login keychain, and that keychain ignores
        // `kSecUseAuthenticationUI`; it only honours the process-wide
        // `SecKeychainSetUserInteractionAllowed` setting. While prompts are
        // disabled a read Pace is not admitted to fails with
        // `errSecAuthFailed` or `errSecInteractionNotAllowed`, which is
        // reported as `credentialAccessDenied` so the user can be offered a
        // deliberate, prompted read instead of an interruption.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw .invalidCredential
            }
            return CursorKeychainRecord(data: data)
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw .credentialAccessDenied
        default:
            throw .credentialReadFailed
        }
    }
}

struct CursorCredentialLoader: CursorCredentialLoading {
    static let accessTokenService = "cursor-access-token"
    static let refreshTokenService = "cursor-refresh-token"
    static let keychainAccount = "cursor-user"
    private static let maximumFileSize = 1_048_576

    private let keychain: any CursorKeychainReading

    init(
        keychain: any CursorKeychainReading = CursorCachingKeychainReader(),
    ) {
        self.keychain = keychain
    }

    func load(for profile: CursorProfile) throws(CursorProviderError) -> CursorCredential {
        let authenticationID = try loadAuthenticationID(at: profile.configurationFile)
        let tokens = switch profile.credentialSource {
        case .defaultKeychain:
            try loadKeychainTokens()
        case .isolatedFile:
            try loadFileTokens(at: profile.credentialFile)
        }
        guard tokens.accessToken != nil || tokens.refreshToken != nil else {
            throw .signedOut
        }
        return CursorCredential(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            authenticationID: authenticationID,
            source: profile.credentialSource,
        )
    }

    private func loadKeychainTokens() throws(CursorProviderError) -> CursorTokens {
        let access = try keychain.readGenericPassword(
            service: Self.accessTokenService,
            account: Self.keychainAccount,
        )
        let refresh = try keychain.readGenericPassword(
            service: Self.refreshTokenService,
            account: Self.keychainAccount,
        )
        return try CursorTokens(
            accessToken: Self.token(from: access?.data),
            refreshToken: Self.token(from: refresh?.data),
        )
    }

    private func loadFileTokens(at url: URL) throws(CursorProviderError) -> CursorTokens {
        let data = try Self.readFile(at: url, requiresPrivatePermissions: true)
        let document: CursorCredentialDocument
        do {
            document = try JSONDecoder().decode(CursorCredentialDocument.self, from: data)
        } catch {
            throw .invalidCredential
        }
        let containsOnlyAPIKey = Self.normalized(document.apiKey) != nil
            && Self.normalized(document.accessToken) == nil
            && Self.normalized(document.refreshToken) == nil
        if containsOnlyAPIKey {
            throw .invalidCredential
        }
        return CursorTokens(
            accessToken: Self.normalized(document.accessToken),
            refreshToken: Self.normalized(document.refreshToken),
        )
    }

    private func loadAuthenticationID(at url: URL) throws(CursorProviderError) -> String {
        let data = try Self.readFile(at: url, requiresPrivatePermissions: false)
        let document: CursorConfigurationDocument
        do {
            document = try JSONDecoder().decode(CursorConfigurationDocument.self, from: data)
        } catch {
            throw .invalidCredential
        }
        guard let authenticationID = Self.normalized(document.authInfo.authID) else {
            throw .invalidCredential
        }
        return authenticationID
    }

    private static func token(from data: Data?) throws(CursorProviderError) -> String? {
        guard let data else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw .invalidCredential
        }
        return normalized(value)
    }

    private static func normalized(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private static func readFile(
        at url: URL,
        requiresPrivatePermissions: Bool,
    ) throws(CursorProviderError) -> Data {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ENOENT {
                throw .signedOut
            }
            if errno == ELOOP {
                throw .insecureCredentialFile
            }
            throw .credentialReadFailed
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        var information = stat()
        guard fstat(descriptor, &information) == 0 else {
            try? handle.close()
            throw .credentialReadFailed
        }
        guard (information.st_mode & S_IFMT) == S_IFREG,
              information.st_uid == geteuid(),
              information.st_size > 0,
              information.st_size <= Self.maximumFileSize
        else {
            try? handle.close()
            throw .invalidCredential
        }
        if requiresPrivatePermissions, information.st_mode & 0o077 != 0 {
            try? handle.close()
            throw .insecureCredentialFile
        }

        do {
            let data = try handle.readToEnd() ?? Data()
            try handle.close()
            guard !data.isEmpty, data.count <= Self.maximumFileSize else {
                throw CursorProviderError.invalidCredential
            }
            return data
        } catch let error as CursorProviderError {
            throw error
        } catch {
            throw .credentialReadFailed
        }
    }
}

private struct CursorTokens {
    let accessToken: String?
    let refreshToken: String?
}

private struct CursorCredentialDocument: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let apiKey: String?
}

private struct CursorConfigurationDocument: Decodable {
    let authInfo: CursorAuthInformation
}

private struct CursorAuthInformation: Decodable {
    let authID: String

    enum CodingKeys: String, CodingKey {
        case authID = "authId"
    }
}

import Foundation
import Security

protocol ClaudeKeychainAccessing: Sendable {
    func readGenericPassword(
        service: String,
        account: String,
    ) throws(ClaudeProviderError) -> ClaudeKeychainRecord?
    func updateGenericPassword(
        service: String,
        account: String,
        data: Data,
    ) throws(ClaudeProviderError)
}

struct ClaudeKeychainRecord: Equatable, Sendable {
    let account: String
    let data: Data
}

struct ClaudeSecurityKeychain: ClaudeKeychainAccessing {
    func readGenericPassword(
        service: String,
        account: String,
    ) throws(ClaudeProviderError) -> ClaudeKeychainRecord? {
        // `LAContext.interactionNotAllowed` only suppresses LocalAuthentication
        // UI, such as a Touch ID sheet. It does not suppress the classic
        // keychain authorization dialog that asks for the login password when
        // an item's access control does not already admit this application.
        // `kSecUseAuthenticationUIFail` is what suppresses that dialog, failing
        // with `errSecInteractionNotAllowed` instead of showing it.
        //
        // The two are not combined: supplying `kSecUseAuthenticationContext`
        // makes the context's policy win and the UI key is ignored, which is
        // what left the password dialog appearing.
        //
        // Pace reads a credential another application owns and has a fallback
        // for every failure, so it must never be the reason a dialog appears.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let values = result as? [String: Any],
                  let account = values[kSecAttrAccount as String] as? String,
                  let data = values[kSecValueData as String] as? Data
            else {
                throw .credentialReadFailed
            }
            return ClaudeKeychainRecord(account: account, data: data)
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecAuthFailed:
            // The item's access control does not admit Pace without asking the
            // user for a password. Treat that as "this source is unavailable"
            // so `load` moves on to the credential file, which is the same
            // credential written by the provider.
            throw .credentialUnavailable
        default:
            throw .credentialReadFailed
        }
    }

    func updateGenericPassword(
        service: String,
        account: String,
        data: Data,
    ) throws(ClaudeProviderError) {
        // See the note on reading: the same dialog can appear for a write, and
        // a rotation that cannot complete silently is reported rather than
        // escalated to the user mid-refresh.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let attributes = [kSecValueData as String: data]
        switch SecItemUpdate(query as CFDictionary, attributes as CFDictionary) {
        case errSecSuccess:
            return
        case errSecInteractionNotAllowed, errSecAuthFailed:
            throw .credentialUnavailable
        default:
            throw .credentialWriteFailed
        }
    }
}

protocol ClaudeCredentialStoring: Sendable {
    func load(for profile: ClaudeProfile) throws(ClaudeProviderError)
        -> [ClaudeCredentialCandidate]
    func save(
        _ candidate: ClaudeCredentialCandidate,
        ifUnchanged generation: ClaudeCredentialGeneration,
        for profile: ClaudeProfile,
    ) throws(ClaudeProviderError) -> ClaudeCredentialGeneration
}

struct ClaudeCredentialStore: ClaudeCredentialStoring {
    static let maximumCredentialSize = 1_048_576
    private let keychain: any ClaudeKeychainAccessing

    init(keychain: any ClaudeKeychainAccessing = ClaudeSecurityKeychain()) {
        self.keychain = keychain
    }

    func load(
        for profile: ClaudeProfile,
    ) throws(ClaudeProviderError) -> [ClaudeCredentialCandidate] {
        guard profile.isCredentialBindingValid else {
            throw .invalidProfile
        }
        var candidates: [ClaudeCredentialCandidate] = []
        var readFailure: ClaudeProviderError?

        do {
            if let record = try keychain.readGenericPassword(
                service: profile.keychainService,
                account: profile.keychainAccount,
            ) {
                try candidates.append(Self.candidate(
                    from: record.data,
                    location: .keychain(
                        service: profile.keychainService,
                        account: record.account,
                    ),
                ))
            }
        } catch {
            readFailure = error
        }

        let credentialURL = profile.secureStorageDirectory.appending(path: ".credentials.json")
        do {
            if let data = try Self.readCredentialFile(at: credentialURL) {
                let candidate = try Self.candidate(from: data, location: .file(credentialURL))
                if !candidates.contains(where: { $0.credential == candidate.credential }) {
                    candidates.append(candidate)
                }
            }
        } catch {
            readFailure = readFailure ?? error
        }

        if candidates.isEmpty, let readFailure {
            throw readFailure
        }
        return candidates
    }

    func save(
        _ candidate: ClaudeCredentialCandidate,
        ifUnchanged generation: ClaudeCredentialGeneration,
        for profile: ClaudeProfile,
    ) throws(ClaudeProviderError) -> ClaudeCredentialGeneration {
        try ClaudeCompatibleFileLock.withStorageWriteLock(
            in: profile.secureStorageDirectory,
        ) {
            let current = try load(for: profile)
            guard ClaudeCredentialGeneration(current) == generation,
                  let currentCandidate = current.first(where: {
                      $0.location == candidate.location
                  })
            else {
                throw ClaudeProviderError.credentialChanged
            }
            let document = try Self.updatedDocument(
                currentCandidate.originalDocument,
                credential: candidate.credential,
            )
            let encoded = switch currentCandidate.encoding {
            case .hex:
                Data(document.map { String(format: "%02x", $0) }.joined().utf8)
            case .json:
                document
            }
            guard encoded.count <= Self.maximumCredentialSize else {
                throw ClaudeProviderError.invalidCredential
            }

            switch currentCandidate.location {
            case let .file(url):
                try Self.replacePrivateFile(at: url, with: encoded)
            case let .keychain(service, account):
                try keychain.updateGenericPassword(
                    service: service,
                    account: account,
                    data: encoded,
                )
            }

            var updated = current
            guard let index = updated.firstIndex(where: {
                $0.location == candidate.location
            }) else {
                throw ClaudeProviderError.credentialChanged
            }
            updated[index] = ClaudeCredentialCandidate(
                credential: candidate.credential,
                location: candidate.location,
                encoding: candidate.encoding,
                originalDocument: document,
            )
            return ClaudeCredentialGeneration(updated)
        }
    }

    private static func candidate(
        from sourceData: Data,
        location: ClaudeCredentialLocation,
    ) throws(ClaudeProviderError) -> ClaudeCredentialCandidate {
        guard sourceData.count <= maximumCredentialSize else {
            throw .invalidCredential
        }
        let (data, encoding) = decodedData(sourceData)
        let document: CredentialDocument
        do {
            document = try JSONDecoder().decode(CredentialDocument.self, from: data)
        } catch {
            throw .invalidCredential
        }
        guard let oauth = document.claudeAiOauth,
              let accessToken = normalized(oauth.accessToken)
        else {
            throw .invalidCredential
        }
        return ClaudeCredentialCandidate(
            credential: ClaudeCredential(
                accessToken: accessToken,
                refreshToken: normalized(oauth.refreshToken),
                expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                subscriptionType: normalized(oauth.subscriptionType),
                rateLimitTier: normalized(oauth.rateLimitTier),
                scopes: oauth.scopes.map(Set.init),
            ),
            location: location,
            encoding: encoding,
            originalDocument: data,
        )
    }

    private static func readCredentialFile(
        at url: URL,
    ) throws(ClaudeProviderError) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
        } catch {
            throw .credentialReadFailed
        }
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= maximumCredentialSize
        else {
            throw .invalidCredential
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw .credentialReadFailed
        }
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0
        else {
            throw .insecureCredentialFile
        }
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw .credentialReadFailed
        }
    }

    private static func decodedData(_ data: Data) -> (Data, ClaudeCredentialEncoding) {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            text.count.isMultiple(of: 2),
            text.allSatisfy(\.isHexDigit)
        else {
            return (data, .json)
        }
        var decoded = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index ..< next], radix: 16) else {
                return (data, .json)
            }
            decoded.append(byte)
            index = next
        }
        return (decoded, .hex)
    }

    private static func updatedDocument(
        _ data: Data,
        credential: ClaudeCredential,
    ) throws(ClaudeProviderError) -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any]
        else {
            throw .invalidCredential
        }
        oauth["accessToken"] = credential.accessToken
        oauth["refreshToken"] = credential.refreshToken
        oauth["expiresAt"] = credential.expiresAt.map { $0.timeIntervalSince1970 * 1000 }
        root["claudeAiOauth"] = oauth
        do {
            return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        } catch {
            throw .invalidCredential
        }
    }

    private static func replacePrivateFile(
        at url: URL,
        with data: Data,
    ) throws(ClaudeProviderError) {
        let temporaryURL = url.deletingLastPathComponent()
            .appending(path: ".pace-claude-credentials-\(UUID().uuidString)")
        let created = FileManager.default.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600],
        )
        guard created else {
            throw .credentialWriteFailed
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw .credentialWriteFailed
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }
}

private struct CredentialDocument: Decodable {
    let claudeAiOauth: OAuth?

    struct OAuth: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresAt: Double?
        let subscriptionType: String?
        let rateLimitTier: String?
        let scopes: [String]?
    }
}

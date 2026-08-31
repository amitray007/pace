import CryptoKit
import Foundation
import LocalAuthentication
import Security

public protocol ClaudeCredentialLoading: Sendable {
    func load(for profile: ClaudeProfileBinding) throws -> [ClaudeCredentialCandidate]
}

public protocol ClaudeKeychainReading: Sendable {
    func readGenericPassword(service: String) throws -> Data?
}

public struct NonInteractiveKeychainReader: ClaudeKeychainReading {
    public init() {}

    public func readGenericPassword(service: String) throws -> Data? {
        let account = NSUserName()
        if let data = try read(service: service, account: account) {
            return data
        }
        return try read(service: service, account: nil)
    }

    private func read(service: String, account: String?) throws -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw ClaudeSpikeError.credentialReadFailed
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw ClaudeSpikeError.credentialReadFailed
        }
    }
}

public struct ClaudeCredentialLoader: ClaudeCredentialLoading {
    private static let maximumCredentialSize = 1_048_576
    private let keychain: any ClaudeKeychainReading

    public init(keychain: any ClaudeKeychainReading = NonInteractiveKeychainReader()) {
        self.keychain = keychain
    }

    public func load(for profile: ClaudeProfileBinding) throws -> [ClaudeCredentialCandidate] {
        var candidates: [ClaudeCredentialCandidate] = []
        var keychainFailed = false
        var invalidCredential = false

        do {
            if let data = try keychain.readGenericPassword(
                service: Self.keychainService(for: profile.configDirectory),
            ) {
                do {
                    let credential = try Self.parseCredential(data)
                    candidates.append(
                        ClaudeCredentialCandidate(credential: credential, source: .keychain),
                    )
                } catch {
                    invalidCredential = true
                }
            }
        } catch {
            keychainFailed = true
        }

        let credentialURL = profile.configDirectory.appending(path: ".credentials.json")
        do {
            if let credential = try Self.loadFileCredential(at: credentialURL) {
                if !candidates.contains(where: { $0.credential == credential }) {
                    candidates.append(
                        ClaudeCredentialCandidate(credential: credential, source: .file),
                    )
                }
            }
        } catch ClaudeSpikeError.invalidCredential {
            invalidCredential = true
        } catch {
            keychainFailed = true
        }

        if candidates.isEmpty, invalidCredential {
            throw ClaudeSpikeError.invalidCredential
        }
        if candidates.isEmpty, keychainFailed {
            throw ClaudeSpikeError.credentialReadFailed
        }
        return candidates
    }

    private static func loadFileCredential(at url: URL) throws -> ClaudeCredential? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= maximumCredentialSize else {
            throw ClaudeSpikeError.invalidCredential
        }
        let data = try Data(contentsOf: url)
        return try parseCredential(data)
    }

    public static func keychainService(for configDirectory: URL) -> String {
        let directory = configDirectory.standardizedFileURL
        let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude", directoryHint: .isDirectory)
            .standardizedFileURL
        guard directory != defaultDirectory else {
            return "Claude Code-credentials"
        }

        let normalizedPath = directory.path.precomposedStringWithCanonicalMapping
        let digest = SHA256.hash(data: Data(normalizedPath.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(suffix)"
    }

    static func parseCredential(_ sourceData: Data) throws -> ClaudeCredential {
        guard sourceData.count <= maximumCredentialSize else {
            throw ClaudeSpikeError.invalidCredential
        }
        let data = decodedData(sourceData)
        let document: CredentialDocument
        do {
            document = try JSONDecoder().decode(CredentialDocument.self, from: data)
        } catch {
            throw ClaudeSpikeError.invalidCredential
        }
        guard let oauth = document.claudeAiOauth else {
            throw ClaudeSpikeError.invalidCredential
        }
        let accessToken = oauth.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            throw ClaudeSpikeError.invalidCredential
        }
        return ClaudeCredential(
            accessToken: accessToken,
            refreshToken: oauth.refreshToken?.nilIfBlank,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            subscriptionType: oauth.subscriptionType?.nilIfBlank,
            rateLimitTier: oauth.rateLimitTier?.nilIfBlank,
            scopes: oauth.scopes.map(Set.init),
        )
    }

    private static func decodedData(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            text.count.isMultiple(of: 2),
            text.allSatisfy(\.isHexDigit)
        else {
            return data
        }

        var decoded = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index ..< next], radix: 16) else {
                return data
            }
            decoded.append(byte)
            index = next
        }
        return decoded
    }
}

private struct CredentialDocument: Decodable {
    let claudeAiOauth: OAuth?

    struct OAuth: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Double?
        let subscriptionType: String?
        let rateLimitTier: String?
        let scopes: [String]?
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

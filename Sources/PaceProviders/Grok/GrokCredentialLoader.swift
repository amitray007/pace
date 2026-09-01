import Foundation

protocol GrokCredentialLoading: Sendable {
    func load(for profile: GrokProfile) throws(GrokProviderError) -> GrokCredential
}

struct GrokCredentialLoader: GrokCredentialLoading {
    private static let maximumCredentialSize = 1_048_576
    private static let xAIIssuer = "https://auth.x.ai"
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func load(for profile: GrokProfile) throws(GrokProviderError) -> GrokCredential {
        let data = try readCredentialFile(at: profile.directory.appending(path: "auth.json"))
        let store: [String: CredentialDocument]
        do {
            store = try JSONDecoder().decode([String: CredentialDocument].self, from: data)
        } catch {
            throw .invalidCredential
        }

        var candidates: [GrokCredential] = []
        for document in store.values {
            if let credential = try Self.makeCredential(document) {
                candidates.append(credential)
            }
        }
        guard !candidates.isEmpty else {
            if store.values.contains(where: Self.isUnsupportedCredential) {
                throw .unsupportedCredential
            }
            throw .signedOut
        }
        guard candidates.count == 1, let credential = candidates.first else {
            throw .ambiguousCredential
        }
        if let expiresAt = credential.expiresAt, expiresAt <= now() {
            throw .invalidCredential
        }
        return credential
    }

    private func readCredentialFile(at url: URL) throws(GrokProviderError) -> Data {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw .signedOut
        } catch {
            throw .credentialReadFailed
        }
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= Self.maximumCredentialSize
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

    private static func makeCredential(
        _ document: CredentialDocument,
    ) throws(GrokProviderError) -> GrokCredential? {
        let mode = document.authMode.lowercased()
        guard mode == "oidc" || mode == "external" else {
            return nil
        }
        guard normalized(document.oidcIssuer) == xAIIssuer else {
            return nil
        }
        guard let token = normalized(document.key), normalized(document.userID) != nil else {
            throw .invalidCredential
        }
        let expiresAt = try document.expiresAt.map(parseDate)
        return GrokCredential(accessToken: token, expiresAt: expiresAt)
    }

    private static func isUnsupportedCredential(_ document: CredentialDocument) -> Bool {
        guard normalized(document.key) != nil else {
            return false
        }
        return document.authMode.caseInsensitiveCompare("api_key") == .orderedSame
            || normalized(document.oidcIssuer) != xAIIssuer
    }

    private static func normalized(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private static func parseDate(_ value: String) throws(GrokProviderError) -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        guard let date = standard.date(from: value) else {
            throw .invalidCredential
        }
        return date
    }
}

private struct CredentialDocument: Decodable {
    let key: String?
    let authMode: String
    let userID: String?
    let expiresAt: String?
    let oidcIssuer: String?

    enum CodingKeys: String, CodingKey {
        case key
        case authMode = "auth_mode"
        case userID = "user_id"
        case expiresAt = "expires_at"
        case oidcIssuer = "oidc_issuer"
    }
}

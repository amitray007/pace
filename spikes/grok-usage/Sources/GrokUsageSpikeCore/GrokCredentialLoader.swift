import Foundation

public protocol GrokCredentialLoading: Sendable {
    func load(for profile: GrokProfileBinding) throws -> GrokCredential
}

public struct GrokCredentialLoader: GrokCredentialLoading {
    private static let maximumCredentialSize = 1_048_576
    private static let xAIIssuer = "https://auth.x.ai"
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func load(for profile: GrokProfileBinding) throws -> GrokCredential {
        let data = try readCredentialFile(at: profile.credentialFile)
        let store: [String: CredentialDocument]
        do {
            store = try JSONDecoder().decode([String: CredentialDocument].self, from: data)
        } catch {
            throw GrokSpikeError.invalidCredential
        }

        let candidates = try store.values.compactMap(Self.makeCredential)
        guard !candidates.isEmpty else {
            if store.values.contains(where: Self.isAPIKeyCredential) {
                throw GrokSpikeError.unsupportedCredential
            }
            throw GrokSpikeError.signedOut
        }
        guard candidates.count == 1, let credential = candidates.first else {
            throw GrokSpikeError.ambiguousCredential
        }
        if let expiresAt = credential.expiresAt, expiresAt <= now() {
            throw GrokSpikeError.invalidCredential
        }
        return credential
    }

    private func readCredentialFile(at url: URL) throws -> Data {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw GrokSpikeError.signedOut
        } catch {
            throw GrokSpikeError.credentialReadFailed
        }
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize <= Self.maximumCredentialSize
        else {
            throw GrokSpikeError.invalidCredential
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw GrokSpikeError.credentialReadFailed
        }
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0
        else {
            throw GrokSpikeError.insecureCredentialFile
        }

        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw GrokSpikeError.credentialReadFailed
        }
    }

    private static func makeCredential(_ document: CredentialDocument) throws -> GrokCredential? {
        let mode = document.authMode.lowercased()
        guard mode == "oidc" || mode == "external" else {
            return nil
        }
        guard normalized(document.oidcIssuer) == xAIIssuer else {
            return nil
        }
        let token = normalized(document.key)
        let userID = normalized(document.userID)
        guard let token, let userID else {
            throw GrokSpikeError.invalidCredential
        }
        let expiresAt = try document.expiresAt.map(parseDate)
        return GrokCredential(
            accessToken: token,
            localIdentity: GrokIdentity(
                userID: userID,
                principalID: normalized(document.principalID),
                teamID: normalized(document.teamID),
                email: normalized(document.email),
                displayName: displayName(
                    firstName: document.firstName,
                    lastName: document.lastName,
                ),
            ),
            expiresAt: expiresAt,
        )
    }

    private static func isAPIKeyCredential(_ document: CredentialDocument) -> Bool {
        guard normalized(document.key) != nil else {
            return false
        }
        return document.authMode.caseInsensitiveCompare("api_key") == .orderedSame
            || normalized(document.oidcIssuer) != xAIIssuer
    }

    private static func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func displayName(firstName: String?, lastName: String?) -> String? {
        let values = [firstName, lastName].compactMap(normalized)
        return values.isEmpty ? nil : values.joined(separator: " ")
    }

    private static func parseDate(_ value: String) throws -> Date {
        if let date = iso8601Date(value) {
            return date
        }
        throw GrokSpikeError.invalidCredential
    }

    private static func iso8601Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

private struct CredentialDocument: Decodable {
    let key: String?
    let authMode: String
    let userID: String?
    let email: String?
    let firstName: String?
    let lastName: String?
    let principalID: String?
    let teamID: String?
    let expiresAt: String?
    let oidcIssuer: String?

    enum CodingKeys: String, CodingKey {
        case key
        case authMode = "auth_mode"
        case userID = "user_id"
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case principalID = "principal_id"
        case teamID = "team_id"
        case expiresAt = "expires_at"
        case oidcIssuer = "oidc_issuer"
    }
}

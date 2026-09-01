import Foundation
import PaceCore
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension ClaudeUsageReader {
    func profileRequest(_ accessToken: String) -> URLRequest {
        authenticatedRequest(url: Self.profileURL, accessToken: accessToken)
    }

    func usageRequest(_ accessToken: String) -> URLRequest {
        authenticatedRequest(url: Self.usageURL, accessToken: accessToken)
    }

    func authenticatedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.252", forHTTPHeaderField: "User-Agent")
        return request
    }

    func refreshRequest(_ refreshToken: String) -> URLRequest {
        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": Self.refreshScopes,
        ]
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    func send(_ request: URLRequest) async throws(ClaudeProviderError) -> ClaudeHTTPResponse {
        do {
            let response = try await transport.send(request)
            guard response.body.count <= ClaudeURLSessionTransport.maximumResponseSize else {
                throw ClaudeProviderError.invalidResponse
            }
            return response
        } catch let error as ClaudeProviderError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .transportFailed
        }
    }

    func requireSuccess(_ response: ClaudeHTTPResponse) throws(ClaudeProviderError) {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401, 403:
            throw .reauthenticationRequired
        case 429:
            throw .rateLimited(retryAfter: retryAfter(from: response))
        default:
            throw .requestFailed(statusCode: response.statusCode)
        }
    }

    func retryAfter(from response: ClaudeHTTPResponse) -> TimeInterval? {
        guard let value = response.header("retry-after")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now())) }
    }

    func decodeIdentity(_ data: Data) throws(ClaudeProviderError) -> ClaudeIdentity {
        let envelope: ClaudeProfileEnvelope
        do {
            envelope = try JSONDecoder().decode(ClaudeProfileEnvelope.self, from: data)
        } catch {
            throw .invalidResponse
        }
        let accountID = envelope.account.uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        let organizationID = envelope.organization.uuid
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountID.isEmpty, !organizationID.isEmpty else {
            throw .invalidResponse
        }
        return ClaudeIdentity(
            accountID: accountID,
            organizationID: organizationID,
            email: envelope.account.email,
            accountName: envelope.account.displayName ?? envelope.account.fullName,
            organizationName: envelope.organization.name,
        )
    }

    func verify(
        _ identity: ClaudeIdentity,
        expected: ProviderIdentity?,
    ) throws(ClaudeProviderError) {
        guard let expected else {
            return
        }
        guard identity.providerIdentity.subjectID == expected.subjectID else {
            throw .identityMismatch
        }
    }

    func needsRefresh(_ credential: ClaudeCredential) -> Bool {
        guard let expiresAt = credential.expiresAt else {
            return false
        }
        return expiresAt.timeIntervalSince(now()) <= 1200
    }

    func formatPlan(_ credential: ClaudeCredential) -> String? {
        guard let subscription = credential.subscriptionType?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !subscription.isEmpty
        else {
            return nil
        }
        let base = subscription.prefix(1).uppercased() + subscription.dropFirst().lowercased()
        guard let tier = credential.rateLimitTier,
              let range = tier.range(of: #"\d+x"#, options: .regularExpression)
        else {
            return base
        }
        return "\(base) \(tier[range])"
    }

    func refreshErrorCode(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["error"] as? String ?? object["error_description"] as? String
    }
}

extension ClaudeHTTPResponse {
    var isAuthenticationFailure: Bool {
        statusCode == 401 || statusCode == 403
    }
}

extension ClaudeProviderError {
    var allowsCredentialFallback: Bool {
        switch self {
        case .missingProfileScope, .reauthenticationRequired:
            true
        default:
            false
        }
    }
}

struct ClaudeProfileEnvelope: Decodable {
    let account: ClaudeProfileAccount
    let organization: ClaudeProfileOrganization
}

struct ClaudeProfileAccount: Decodable {
    let uuid: String
    let email: String?
    let displayName: String?
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case uuid
        case email
        case displayName = "display_name"
        case fullName = "full_name"
    }
}

struct ClaudeProfileOrganization: Decodable {
    let uuid: String
    let name: String?
}

struct RefreshEnvelope: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

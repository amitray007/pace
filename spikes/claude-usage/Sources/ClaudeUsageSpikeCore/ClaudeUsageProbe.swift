import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct ClaudeHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data) {
        self.statusCode = statusCode
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { key, value in
            (key.lowercased(), value)
        })
        self.body = body
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public protocol ClaudeHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> ClaudeHTTPResponse
}

public struct ClaudeURLSessionTransport: ClaudeHTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> ClaudeHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ClaudeSpikeError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { values, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else {
                return
            }
            values[key] = value
        }
        return ClaudeHTTPResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: data,
        )
    }
}

public struct ClaudeUsageProbe: Sendable {
    private let credentialLoader: any ClaudeCredentialLoading
    private let transport: any ClaudeHTTPTransport
    private let now: @Sendable () -> Date
    private let userAgent: String

    public init(
        credentialLoader: any ClaudeCredentialLoading = ClaudeCredentialLoader(),
        transport: any ClaudeHTTPTransport = ClaudeURLSessionTransport(),
        userAgent: String = "claude-code/2.1.251",
        now: @escaping @Sendable () -> Date = Date.init,
    ) {
        self.credentialLoader = credentialLoader
        self.transport = transport
        self.userAgent = userAgent
        self.now = now
    }

    public func probe(_ profile: ClaudeProfileBinding) async throws -> ClaudeProbeResult {
        let candidates = try credentialLoader.load(for: profile)
        guard !candidates.isEmpty else {
            throw ClaudeSpikeError.signedOut
        }

        var terminalError: ClaudeSpikeError?
        for candidate in candidates {
            guard candidate.credential.canReadUsage else {
                terminalError = .missingProfileScope
                continue
            }

            do {
                let identity = try await fetchIdentity(using: candidate.credential)
                guard identityMatches(identity, expected: profile.expectedIdentity) else {
                    terminalError = .identityMismatch
                    continue
                }
                let metrics = try await fetchUsage(using: candidate.credential)
                return ClaudeProbeResult(
                    identity: identity,
                    planName: formatPlan(
                        subscriptionType: candidate.credential.subscriptionType,
                        rateLimitTier: candidate.credential.rateLimitTier,
                    ),
                    metrics: metrics,
                    observedAt: now(),
                    credentialSource: candidate.source,
                )
            } catch let error as ClaudeSpikeError {
                switch error {
                case .requestFailed(statusCode: 401), .requestFailed(statusCode: 403):
                    terminalError = error
                    continue
                default:
                    throw error
                }
            } catch {
                throw ClaudeSpikeError.transportFailed
            }
        }

        throw terminalError ?? ClaudeSpikeError.signedOut
    }

    public func probeSequentially(
        _ profiles: [ClaudeProfileBinding],
    ) async throws -> [ClaudeProbeResult] {
        var results: [ClaudeProbeResult] = []
        var identities: Set<String> = []

        for profile in profiles {
            let result = try await probe(profile)
            guard identities.insert(result.identity.stableKey).inserted else {
                throw ClaudeSpikeError.duplicateIdentity
            }
            results.append(result)
        }
        return results
    }

    private func fetchIdentity(using credential: ClaudeCredential) async throws -> ClaudeIdentity {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/profile") else {
            throw ClaudeSpikeError.invalidResponse
        }
        let request = authenticatedRequest(
            url: url,
            credential: credential,
        )
        let response = try await send(request)
        try requireSuccess(response)

        let profile: ProfileEnvelope
        do {
            profile = try JSONDecoder().decode(ProfileEnvelope.self, from: response.body)
        } catch {
            throw ClaudeSpikeError.invalidResponse
        }
        guard !profile.account.uuid.isEmpty, !profile.organization.uuid.isEmpty else {
            throw ClaudeSpikeError.invalidResponse
        }
        return ClaudeIdentity(
            accountID: profile.account.uuid,
            organizationID: profile.organization.uuid,
            email: profile.account.email,
            accountName: profile.account.displayName ?? profile.account.fullName,
            organizationName: profile.organization.name,
        )
    }

    private func fetchUsage(using credential: ClaudeCredential) async throws -> [ClaudeMetric] {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw ClaudeSpikeError.invalidResponse
        }
        let request = authenticatedRequest(
            url: url,
            credential: credential,
        )
        let response = try await send(request)
        try requireSuccess(response)
        return try ClaudeUsageDecoder.decode(response.body)
    }

    private func authenticatedRequest(
        url: URL,
        credential: ClaudeCredential,
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func send(_ request: URLRequest) async throws -> ClaudeHTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as ClaudeSpikeError {
            throw error
        } catch {
            throw ClaudeSpikeError.transportFailed
        }
    }

    private func requireSuccess(_ response: ClaudeHTTPResponse) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 429:
            throw ClaudeSpikeError.rateLimited(retryAfter: retryAfter(from: response))
        default:
            throw ClaudeSpikeError.requestFailed(statusCode: response.statusCode)
        }
    }

    private func retryAfter(from response: ClaudeHTTPResponse) -> TimeInterval? {
        guard let value = response.header("retry-after")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        if let seconds = TimeInterval(value), seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now())) }
    }

    private func identityMatches(_ identity: ClaudeIdentity, expected: ClaudeIdentity?) -> Bool {
        guard let expected else {
            return true
        }
        return identity.accountID.caseInsensitiveCompare(expected.accountID) == .orderedSame &&
            identity.organizationID.caseInsensitiveCompare(expected.organizationID) == .orderedSame
    }

    private func formatPlan(subscriptionType: String?, rateLimitTier: String?) -> String? {
        guard let subscriptionType = subscriptionType?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !subscriptionType.isEmpty
        else {
            return nil
        }
        let base = subscriptionType.prefix(1).uppercased() + subscriptionType.dropFirst()
            .lowercased()
        guard let rateLimitTier,
              let match = rateLimitTier.range(of: #"\d+x"#, options: .regularExpression)
        else {
            return base
        }
        return "\(base) \(rateLimitTier[match])"
    }
}

private struct ProfileEnvelope: Decodable {
    let account: ProfileAccount
    let organization: ProfileOrganization
}

private struct ProfileAccount: Decodable {
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

private struct ProfileOrganization: Decodable {
    let uuid: String
    let name: String?
}

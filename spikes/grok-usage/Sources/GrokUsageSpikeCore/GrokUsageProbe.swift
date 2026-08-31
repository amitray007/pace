import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct GrokHTTPResponse: Sendable {
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

public protocol GrokHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GrokHTTPResponse
}

public struct GrokURLSessionTransport: GrokHTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> GrokHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GrokSpikeError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { values, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else {
                return
            }
            values[key] = value
        }
        return GrokHTTPResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: data,
        )
    }
}

public struct GrokUsageProbe: Sendable {
    private let credentialLoader: any GrokCredentialLoading
    private let transport: any GrokHTTPTransport
    private let baseURL: URL
    private let now: @Sendable () -> Date

    public init(
        credentialLoader: any GrokCredentialLoading = GrokCredentialLoader(),
        transport: any GrokHTTPTransport = GrokURLSessionTransport(),
        baseURL: URL = URL(string: "https://cli-chat-proxy.grok.com/v1")!,
        now: @escaping @Sendable () -> Date = Date.init,
    ) {
        self.credentialLoader = credentialLoader
        self.transport = transport
        self.baseURL = baseURL
        self.now = now
    }

    public func probe(_ profile: GrokProfileBinding) async throws -> GrokProbeResult {
        let credential = try credentialLoader.load(for: profile)
        let remote = try await fetchIdentity(accessToken: credential.accessToken)
        guard profile.expectedIdentity.map({ $0.stableKey == remote.identity.stableKey }) ?? true
        else {
            throw GrokSpikeError.identityMismatch
        }

        let billingURL = baseURL
            .appending(path: "billing")
            .appending(queryItems: [URLQueryItem(name: "format", value: "credits")])
        let response = try await send(authenticatedRequest(
            url: billingURL,
            accessToken: credential.accessToken,
            userID: remote.identity.userID,
        ))
        try requireSuccess(response)
        return try GrokProbeResult(
            identity: remote.identity,
            planName: remote.planName,
            metrics: GrokUsageDecoder.decodeUsage(response.body),
            observedAt: now(),
        )
    }

    public func probeSequentially(
        _ profiles: [GrokProfileBinding],
    ) async throws -> [GrokProbeResult] {
        var results: [GrokProbeResult] = []
        var identities: Set<String> = []
        for profile in profiles {
            let result = try await probe(profile)
            guard identities.insert(result.identity.stableKey).inserted else {
                throw GrokSpikeError.duplicateIdentity
            }
            results.append(result)
        }
        return results
    }

    private func fetchIdentity(accessToken: String) async throws -> GrokRemoteIdentity {
        let url = baseURL
            .appending(path: "user")
            .appending(queryItems: [URLQueryItem(name: "include", value: "subscription")])
        let response = try await send(authenticatedRequest(
            url: url,
            accessToken: accessToken,
            userID: nil,
        ))
        try requireSuccess(response)
        return try GrokUsageDecoder.decodeIdentity(response.body)
    }

    private func authenticatedRequest(
        url: URL,
        accessToken: String,
        userID: String?,
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Pace-Grok-Usage-Spike/1", forHTTPHeaderField: "User-Agent")
        if let userID {
            request.setValue(userID, forHTTPHeaderField: "x-userid")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> GrokHTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as GrokSpikeError {
            throw error
        } catch {
            throw GrokSpikeError.transportFailed
        }
    }

    private func requireSuccess(_ response: GrokHTTPResponse) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401, 403:
            throw GrokSpikeError.reauthenticationRequired
        case 429:
            throw GrokSpikeError.rateLimited(retryAfter: retryAfter(from: response))
        default:
            throw GrokSpikeError.requestFailed(statusCode: response.statusCode)
        }
    }

    private func retryAfter(from response: GrokHTTPResponse) -> TimeInterval? {
        guard let value = response.header("retry-after")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            let seconds = TimeInterval(value),
            seconds >= 0
        else {
            return nil
        }
        return seconds
    }
}

import Foundation

struct GrokHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    init(statusCode: Int, headers: [String: String] = [:], body: Data) {
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

protocol GrokHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GrokHTTPResponse
}

struct GrokURLSessionTransport: GrokHTTPTransport {
    func send(_ request: URLRequest) async throws -> GrokHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GrokProviderError.invalidResponse
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

protocol GrokUsageReading: Sendable {
    func read(
        profile: GrokProfile,
        includeUsage: Bool,
    ) async throws(GrokProviderError) -> GrokUsageResult
}

struct GrokUsageReader: GrokUsageReading {
    private let credentialLoader: any GrokCredentialLoading
    private let transport: any GrokHTTPTransport
    private let baseURL: URL
    private let now: @Sendable () -> Date
    private let timeout: TimeInterval

    init(
        credentialLoader: any GrokCredentialLoading = GrokCredentialLoader(),
        transport: any GrokHTTPTransport = GrokURLSessionTransport(),
        baseURL: URL = URL(string: "https://cli-chat-proxy.grok.com/v1")!,
        timeout: TimeInterval = 15,
        now: @escaping @Sendable () -> Date = Date.init,
    ) {
        self.credentialLoader = credentialLoader
        self.transport = transport
        self.baseURL = baseURL
        self.timeout = timeout
        self.now = now
    }

    func read(
        profile: GrokProfile,
        includeUsage: Bool,
    ) async throws(GrokProviderError) -> GrokUsageResult {
        let credential = try credentialLoader.load(for: profile)
        let remote = try await fetchIdentity(accessToken: credential.accessToken)
        guard profile.expectedIdentity.map({
            $0.subjectID == remote.identity.providerIdentity.subjectID
        }) ?? true else {
            throw .identityMismatch
        }

        let metrics: [GrokMetric] = if includeUsage {
            try await fetchUsage(
                accessToken: credential.accessToken,
                userID: remote.identity.userID,
            )
        } else {
            []
        }
        return GrokUsageResult(
            identity: remote.identity,
            planName: remote.planName,
            metrics: metrics,
            observedAt: now(),
        )
    }

    private func fetchIdentity(
        accessToken: String,
    ) async throws(GrokProviderError) -> GrokRemoteIdentity {
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

    private func fetchUsage(
        accessToken: String,
        userID: String,
    ) async throws(GrokProviderError) -> [GrokMetric] {
        let url = baseURL
            .appending(path: "billing")
            .appending(queryItems: [URLQueryItem(name: "format", value: "credits")])
        let response = try await send(authenticatedRequest(
            url: url,
            accessToken: accessToken,
            userID: userID,
        ))
        try requireSuccess(response)
        return try GrokUsageDecoder.decodeUsage(response.body)
    }

    private func authenticatedRequest(
        url: URL,
        accessToken: String,
        userID: String?,
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Pace/1", forHTTPHeaderField: "User-Agent")
        if let userID {
            request.setValue(userID, forHTTPHeaderField: "x-userid")
        }
        return request
    }

    private func send(
        _ request: URLRequest,
    ) async throws(GrokProviderError) -> GrokHTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as GrokProviderError {
            throw error
        } catch {
            throw .transportFailed
        }
    }

    private func requireSuccess(_ response: GrokHTTPResponse) throws(GrokProviderError) {
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

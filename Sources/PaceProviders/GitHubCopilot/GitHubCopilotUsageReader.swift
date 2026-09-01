import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct GitHubCopilotHTTPResponse: Sendable {
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

protocol GitHubCopilotHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GitHubCopilotHTTPResponse
}

struct GitHubCopilotURLSessionTransport: GitHubCopilotHTTPTransport {
    static let maximumResponseSize = 1_048_576

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(
            configuration: configuration,
            delegate: GitHubCopilotRedirectBlocker(),
            delegateQueue: nil,
        )
    }

    func send(_ request: URLRequest) async throws -> GitHubCopilotHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw GitHubCopilotProviderError.invalidResponse
        }
        let data: Data
        do {
            data = try await Self.boundedData(
                from: bytes,
                maximumSize: Self.maximumResponseSize,
            )
        } catch {
            bytes.task.cancel()
            throw error
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { values, entry in
            guard let key = entry.key as? String else {
                return
            }
            values[key] = String(describing: entry.value)
        }
        return GitHubCopilotHTTPResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: data,
        )
    }

    static func boundedData<Bytes: AsyncSequence>(
        from bytes: Bytes,
        maximumSize: Int,
    ) async throws -> Data where Bytes.Element == UInt8 {
        var data = Data()
        data.reserveCapacity(min(maximumSize, 65536))
        for try await byte in bytes {
            guard data.count < maximumSize else {
                throw GitHubCopilotProviderError.invalidResponse
            }
            data.append(byte)
        }
        return data
    }
}

private final class GitHubCopilotRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void,
    ) {
        completionHandler(nil)
    }
}

protocol GitHubCopilotUsageReading: Sendable {
    func read(
        profile: GitHubCopilotProfile,
        includeUsage: Bool,
    ) async throws -> GitHubCopilotUsageResult
}

struct GitHubCopilotUsageReader: GitHubCopilotUsageReading {
    private static let identityURL = URL(string: "https://api.github.com/user")!
    private static let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!
    private let credentialLoader: any GitHubCopilotCredentialLoading
    private let transport: any GitHubCopilotHTTPTransport
    private let now: @Sendable () -> Date
    private let timeout: TimeInterval

    init(
        credentialLoader: any GitHubCopilotCredentialLoading = GitHubCLICredentialLoader(),
        transport: any GitHubCopilotHTTPTransport = GitHubCopilotURLSessionTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
        timeout: TimeInterval = 15,
    ) {
        self.credentialLoader = credentialLoader
        self.transport = transport
        self.now = now
        self.timeout = timeout
    }

    func read(
        profile: GitHubCopilotProfile,
        includeUsage: Bool,
    ) async throws -> GitHubCopilotUsageResult {
        let credential = try await credentialLoader.load(for: profile)
        let identityResponse = try await send(identityRequest(token: credential.token))
        try requireSuccess(identityResponse)
        let identity = try GitHubCopilotUsageDecoder.decodeIdentity(identityResponse.body)
        if let expectedIdentity = profile.expectedIdentity {
            guard identity.providerIdentity.subjectID == expectedIdentity.subjectID else {
                throw GitHubCopilotProviderError.identityMismatch
            }
        } else {
            guard identity.login.caseInsensitiveCompare(profile.githubLogin) == .orderedSame else {
                throw GitHubCopilotProviderError.identityMismatch
            }
        }

        guard includeUsage else {
            return GitHubCopilotUsageResult(
                identity: identity,
                planName: nil,
                metrics: [],
                isOrganizationManaged: false,
                observedAt: now(),
            )
        }

        let usageResponse = try await send(usageRequest(token: credential.token))
        try requireSuccess(usageResponse)
        let usage = try GitHubCopilotUsageDecoder.decodeUsage(usageResponse.body)
        return GitHubCopilotUsageResult(
            identity: identity,
            planName: usage.planName,
            metrics: usage.metrics,
            isOrganizationManaged: usage.isOrganizationManaged,
            observedAt: now(),
        )
    }

    private func identityRequest(token: String) -> URLRequest {
        var request = URLRequest(url: Self.identityURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Pace/1", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func usageRequest(token: String) -> URLRequest {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        return request
    }

    private func send(_ request: URLRequest) async throws -> GitHubCopilotHTTPResponse {
        do {
            let response = try await transport.send(request)
            guard response.body.count <= GitHubCopilotURLSessionTransport.maximumResponseSize else {
                throw GitHubCopilotProviderError.invalidResponse
            }
            return response
        } catch let error as GitHubCopilotProviderError {
            throw error
        } catch {
            throw GitHubCopilotProviderError.transportFailed
        }
    }

    private func requireSuccess(_ response: GitHubCopilotHTTPResponse) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401:
            throw GitHubCopilotProviderError.reauthenticationRequired
        case 403 where isRateLimited(response):
            throw GitHubCopilotProviderError.rateLimited(retryAfter: retryAfter(from: response))
        case 403:
            throw GitHubCopilotProviderError.reauthenticationRequired
        case 429:
            throw GitHubCopilotProviderError.rateLimited(retryAfter: retryAfter(from: response))
        default:
            throw GitHubCopilotProviderError.requestFailed(statusCode: response.statusCode)
        }
    }

    private func isRateLimited(_ response: GitHubCopilotHTTPResponse) -> Bool {
        response.header("retry-after") != nil
            || response.header("x-ratelimit-remaining")?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "0"
    }

    private func retryAfter(from response: GitHubCopilotHTTPResponse) -> TimeInterval? {
        if let seconds = retryAfterSeconds(from: response) {
            return seconds
        }
        if let reset = rateLimitReset(from: response) {
            return max(0, reset - now().timeIntervalSince1970)
        }
        return nil
    }

    private func retryAfterSeconds(from response: GitHubCopilotHTTPResponse) -> TimeInterval? {
        guard let value = normalizedHeader("retry-after", from: response),
              let seconds = TimeInterval(value)
        else {
            return nil
        }
        return seconds >= 0 ? seconds : nil
    }

    private func rateLimitReset(from response: GitHubCopilotHTTPResponse) -> TimeInterval? {
        guard let value = normalizedHeader("x-ratelimit-reset", from: response),
              let reset = TimeInterval(value)
        else {
            return nil
        }
        return reset.isFinite ? reset : nil
    }

    private func normalizedHeader(
        _ name: String,
        from response: GitHubCopilotHTTPResponse,
    ) -> String? {
        response.header(name)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

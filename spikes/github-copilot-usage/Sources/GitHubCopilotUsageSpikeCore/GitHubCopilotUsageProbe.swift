import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct GitHubCopilotHTTPResponse: Sendable {
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

public protocol GitHubCopilotHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GitHubCopilotHTTPResponse
}

public struct GitHubCopilotURLSessionTransport: GitHubCopilotHTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> GitHubCopilotHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubCopilotSpikeError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { values, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else {
                return
            }
            values[key] = value
        }
        return GitHubCopilotHTTPResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: data,
        )
    }
}

public struct GitHubCopilotUsageProbe: Sendable {
    public typealias ProbeResult = GitHubCopilotProbeResult

    private static let identityURL = URL(string: "https://api.github.com/user")!
    private static let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!

    private let credentialLoader: any GitHubCopilotCredentialLoading
    private let transport: any GitHubCopilotHTTPTransport
    private let now: @Sendable () -> Date

    public init(
        credentialLoader: any GitHubCopilotCredentialLoading = GitHubCLICredentialLoader(),
        transport: any GitHubCopilotHTTPTransport = GitHubCopilotURLSessionTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
    ) {
        self.credentialLoader = credentialLoader
        self.transport = transport
        self.now = now
    }

    public func probe(_ profile: GitHubCopilotProfileBinding) async throws -> ProbeResult {
        let credential = try credentialLoader.load(for: profile)
        let identityResponse = try await send(identityRequest(token: credential.token))
        try requireSuccess(identityResponse)
        let identity = try GitHubCopilotUsageDecoder.decodeIdentity(identityResponse.body)
        if let expected = profile.expectedIdentity {
            guard identity.stableKey == expected.stableKey else {
                throw GitHubCopilotSpikeError.identityMismatch
            }
        } else {
            guard identity.login.caseInsensitiveCompare(profile.githubLogin) == .orderedSame else {
                throw GitHubCopilotSpikeError.identityMismatch
            }
        }

        let usageResponse = try await send(usageRequest(token: credential.token))
        try requireSuccess(usageResponse)
        let usage = try GitHubCopilotUsageDecoder.decodeUsage(usageResponse.body)
        return GitHubCopilotProbeResult(
            identity: identity,
            planName: usage.planName,
            metrics: usage.metrics,
            isOrganizationManaged: usage.isOrganizationManaged,
            observedAt: now(),
        )
    }

    public func probeSequentially(
        _ profiles: [GitHubCopilotProfileBinding],
    ) async throws -> [GitHubCopilotProbeResult] {
        var results: [GitHubCopilotProbeResult] = []
        var identities: Set<String> = []
        for profile in profiles {
            let result = try await probe(profile)
            guard identities.insert(result.identity.stableKey).inserted else {
                throw GitHubCopilotSpikeError.duplicateIdentity
            }
            results.append(result)
        }
        return results
    }

    private func identityRequest(token: String) -> URLRequest {
        var request = URLRequest(url: Self.identityURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Pace-GitHub-Copilot-Usage-Spike/1", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func usageRequest(token: String) -> URLRequest {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
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
            return try await transport.send(request)
        } catch let error as GitHubCopilotSpikeError {
            throw error
        } catch {
            throw GitHubCopilotSpikeError.transportFailed
        }
    }

    private func requireSuccess(_ response: GitHubCopilotHTTPResponse) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401, 403:
            throw GitHubCopilotSpikeError.reauthenticationRequired
        case 429:
            throw GitHubCopilotSpikeError.rateLimited(retryAfter: retryAfter(from: response))
        default:
            throw GitHubCopilotSpikeError.requestFailed(statusCode: response.statusCode)
        }
    }

    private func retryAfter(from response: GitHubCopilotHTTPResponse) -> TimeInterval? {
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

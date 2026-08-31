import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct CursorHTTPResponse: Sendable {
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

public protocol CursorHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> CursorHTTPResponse
}

public struct CursorURLSessionTransport: CursorHTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> CursorHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CursorSpikeError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { values, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else {
                return
            }
            values[key] = value
        }
        return CursorHTTPResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: data,
        )
    }
}

public struct CursorUsageProbe: Sendable {
    private static let usageURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
    )!
    private static let identityURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetMe",
    )!
    private static let planURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo",
    )!

    private let credentialLoader: any CursorCredentialLoading
    private let transport: any CursorHTTPTransport
    private let now: @Sendable () -> Date

    public init(
        credentialLoader: any CursorCredentialLoading = CursorCredentialLoader(),
        transport: any CursorHTTPTransport = CursorURLSessionTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
    ) {
        self.credentialLoader = credentialLoader
        self.transport = transport
        self.now = now
    }

    public func probe(_ profile: CursorProfileBinding) async throws -> CursorProbeResult {
        let credential = try credentialLoader.load(for: profile)
        guard credentialMatches(credential) else {
            throw CursorSpikeError.invalidCredential
        }

        let remoteIdentity = try await fetchIdentity(accessToken: credential.accessToken)
        guard remoteIdentity.authID.caseInsensitiveCompare(credential.authID) == .orderedSame else {
            throw CursorSpikeError.invalidCredential
        }
        guard identityMatches(remoteIdentity.identity, expected: profile.expectedIdentity) else {
            throw CursorSpikeError.identityMismatch
        }

        let usageResponse = try await send(authenticatedRequest(
            url: Self.usageURL,
            accessToken: credential.accessToken,
        ))
        try requireSuccess(usageResponse)
        let metrics = try CursorUsageDecoder.decode(usageResponse.body)

        let planName = await fetchPlan(accessToken: credential.accessToken)
        return CursorProbeResult(
            identity: remoteIdentity.identity,
            planName: planName,
            metrics: metrics,
            observedAt: now(),
            credentialSource: credential.source,
        )
    }

    private func fetchIdentity(accessToken: String) async throws -> CursorRemoteIdentity {
        let response = try await send(authenticatedRequest(
            url: Self.identityURL,
            accessToken: accessToken,
        ))
        try requireSuccess(response)
        return try CursorIdentityDecoder.decode(response.body)
    }

    public func probeSequentially(
        _ profiles: [CursorProfileBinding],
    ) async throws -> [CursorProbeResult] {
        var results: [CursorProbeResult] = []
        var identities: Set<String> = []

        for profile in profiles {
            let result = try await probe(profile)
            guard identities.insert(result.identity.stableKey).inserted else {
                throw CursorSpikeError.duplicateIdentity
            }
            results.append(result)
        }
        return results
    }

    private func fetchPlan(accessToken: String) async -> String? {
        do {
            let response = try await send(authenticatedRequest(
                url: Self.planURL,
                accessToken: accessToken,
            ))
            guard (200 ..< 300).contains(response.statusCode) else {
                return nil
            }
            return CursorUsageDecoder.decodePlan(response.body)
        } catch {
            return nil
        }
    }

    private func authenticatedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        return request
    }

    private func send(_ request: URLRequest) async throws -> CursorHTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as CursorSpikeError {
            throw error
        } catch {
            throw CursorSpikeError.transportFailed
        }
    }

    private func requireSuccess(_ response: CursorHTTPResponse) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 429:
            throw CursorSpikeError.rateLimited(retryAfter: retryAfter(from: response))
        default:
            throw CursorSpikeError.requestFailed(statusCode: response.statusCode)
        }
    }

    private func retryAfter(from response: CursorHTTPResponse) -> TimeInterval? {
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

    private func identityMatches(_ identity: CursorIdentity, expected: CursorIdentity?) -> Bool {
        guard let expected else {
            return true
        }
        return identity.stableKey == expected.stableKey
    }

    private func credentialMatches(_ credential: CursorCredential) -> Bool {
        guard let subject = Self.jwtSubject(credential.accessToken) else {
            return false
        }
        return subject.caseInsensitiveCompare(credential.authID) == .orderedSame
    }

    static func jwtSubject(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            return nil
        }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload.append(String(repeating: "=", count: (4 - payload.count % 4) % 4))
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = object["sub"] as? String
        else {
            return nil
        }
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

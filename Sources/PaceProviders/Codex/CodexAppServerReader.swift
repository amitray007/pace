import Foundation

protocol CodexProfileReading: Sendable {
    func read(
        profile: CodexProfile,
        includeRateLimits: Bool,
    ) async throws(CodexProviderError) -> CodexProfileSnapshot
}

protocol CodexProfileEventReading: Sendable {
    func events(for profile: CodexProfile) async throws(CodexProviderError)
        -> AsyncStream<CodexProfileEvent>
}

protocol CodexProfileSessionReading: CodexProfileEventReading, CodexProfileReading {}

struct CodexAppServerReader: CodexProfileSessionReading, Sendable {
    private let poolResolver: CodexConnectionPoolResolver

    init(
        executableURL: URL? = nil,
        timeout: TimeInterval = 10,
        reconnectDelays: [Duration] = [
            .milliseconds(250),
            .seconds(1),
            .seconds(5),
            .seconds(30),
        ],
    ) {
        poolResolver = CodexConnectionPoolResolver(
            executableURL: executableURL,
            requestTimeout: timeout,
            reconnectDelays: reconnectDelays,
        )
    }

    @concurrent
    func read(
        profile: CodexProfile,
        includeRateLimits: Bool,
    ) async throws(CodexProviderError) -> CodexProfileSnapshot {
        let connectionPool = try poolResolver.pool()
        let connection = try await connectionPool.connection(for: profile)
        let accountData = try await connection.request(
            method: "account/read",
            params: #"{"refreshToken":false}"#,
        )
        let decoder = JSONDecoder()
        let account: CodexAccountResponse = try decodeResponse(
            from: accountData,
            decoder: decoder,
        )
        guard account.account != nil else {
            throw .signedOut
        }
        let rateLimits: CodexRateLimitsResponse? = if includeRateLimits {
            try await decodeResponse(
                from: connection.request(method: "account/rateLimits/read"),
                decoder: decoder,
            )
        } else {
            nil
        }
        return CodexProfileSnapshot(account: account, rateLimits: rateLimits)
    }

    private func decodeResponse<Result: Decodable>(
        from data: Data,
        decoder: JSONDecoder,
    ) throws(CodexProviderError) -> Result {
        let envelope: CodexRPCEnvelope<Result>
        do {
            envelope = try decoder.decode(CodexRPCEnvelope<Result>.self, from: data)
        } catch {
            throw .invalidResponse
        }
        if let error = envelope.error {
            throw .protocolFailure(code: error.code)
        }
        guard let result = envelope.result else {
            throw .invalidResponse
        }
        return result
    }

    func events(
        for profile: CodexProfile,
    ) async throws(CodexProviderError) -> AsyncStream<CodexProfileEvent> {
        try await poolResolver.pool().events(for: profile)
    }
}

private struct CodexRPCEnvelope<Result: Decodable>: Decodable {
    let result: Result?
    let error: CodexRPCError?
}

private struct CodexRPCError: Decodable {
    let code: Int
}

enum CodexExecutableLocator {
    static func locate() throws(CodexProviderError) -> URL {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let configured = environment["PACE_CODEX_EXECUTABLE"] {
            candidates.append(configured)
        }
        candidates.append(contentsOf: (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/codex" })
        let home = fileManager.homeDirectoryForCurrentUser.path
        candidates.append(contentsOf: [
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ])
        guard let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
        else {
            throw .executableUnavailable
        }
        return URL(filePath: path)
    }
}

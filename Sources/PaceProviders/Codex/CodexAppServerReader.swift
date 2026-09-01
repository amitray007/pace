import Foundation

protocol CodexProfileReading: Sendable {
    func read(
        profile: CodexProfile,
        includeRateLimits: Bool,
    ) async throws(CodexProviderError) -> CodexProfileSnapshot
}

struct CodexAppServerReader: CodexProfileReading, Sendable {
    let executableURL: URL?
    let timeout: TimeInterval

    init(executableURL: URL? = nil, timeout: TimeInterval = 10) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    @concurrent
    func read(
        profile: CodexProfile,
        includeRateLimits: Bool,
    ) async throws(CodexProviderError) -> CodexProfileSnapshot {
        let executableURL: URL = if let configuredURL = self.executableURL {
            configuredURL
        } else {
            try CodexExecutableLocator.locate()
        }
        let responseData = try CodexAppServerProcess.exchange(
            executableURL: executableURL,
            profileDirectory: profile.directory,
            includeRateLimits: includeRateLimits,
            timeout: timeout,
        )
        let decoder = JSONDecoder()
        let account: CodexAccountResponse = try decodeResponse(
            id: 2,
            from: responseData,
            decoder: decoder,
        )
        guard account.account != nil else {
            throw .signedOut
        }
        let rateLimits: CodexRateLimitsResponse? = if includeRateLimits {
            try decodeResponse(id: 3, from: responseData, decoder: decoder)
        } else {
            nil
        }
        return CodexProfileSnapshot(account: account, rateLimits: rateLimits)
    }

    private func decodeResponse<Result: Decodable>(
        id: Int,
        from responseData: [Int: Data],
        decoder: JSONDecoder,
    ) throws(CodexProviderError) -> Result {
        guard let data = responseData[id] else {
            throw .invalidResponse
        }
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
}

private struct CodexRPCEnvelope<Result: Decodable>: Decodable {
    let result: Result?
    let error: CodexRPCError?
}

private struct CodexRPCError: Decodable {
    let code: Int
}

private enum CodexExecutableLocator {
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

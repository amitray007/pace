import Foundation
import PaceCore
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

protocol ClaudeUsageReading: Sendable {
    func read(
        profile: ClaudeProfile,
        includeUsage: Bool,
    ) async throws(ClaudeProviderError) -> ClaudeUsageResult
}

private struct ClaudeReadState {
    var candidate: ClaudeCredentialCandidate
    var generation: ClaudeCredentialGeneration
}

private struct ClaudeUsageReadResult {
    let state: ClaudeReadState
    let identity: ClaudeIdentity
    let metrics: [ClaudeMetric]
}

struct ClaudeUsageReader: ClaudeUsageReading {
    static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let refreshScopes = [
        "user:profile",
        "user:inference",
        "user:sessions:claude_code",
        "user:mcp_servers",
        "user:file_upload",
    ].joined(separator: " ")

    private let credentialStore: any ClaudeCredentialStoring
    let transport: any ClaudeHTTPTransport
    private let gate: ClaudeRequestGate
    private let refreshLock: any ClaudeOAuthRefreshLocking
    let now: @Sendable () -> Date
    let timeout: TimeInterval
    private let allowsCredentialRefresh: Bool

    init(
        credentialStore: any ClaudeCredentialStoring = ClaudeCredentialStore(),
        transport: any ClaudeHTTPTransport = ClaudeURLSessionTransport(),
        gate: ClaudeRequestGate = .shared,
        refreshLock: any ClaudeOAuthRefreshLocking = ClaudeOAuthRefreshFileLock(),
        now: @escaping @Sendable () -> Date = Date.init,
        timeout: TimeInterval = 15,
        allowsCredentialRefresh: Bool = true,
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        self.gate = gate
        self.refreshLock = refreshLock
        self.now = now
        self.timeout = timeout
        self.allowsCredentialRefresh = allowsCredentialRefresh
    }
}

extension ClaudeUsageReader {
    func read(
        profile: ClaudeProfile,
        includeUsage: Bool,
    ) async throws(ClaudeProviderError) -> ClaudeUsageResult {
        do {
            try await gate.acquire()
        } catch {
            throw .cancelled
        }
        do {
            let result = try await readExclusively(
                profile: profile,
                includeUsage: includeUsage,
                mayRestart: true,
            )
            await gate.release()
            return result
        } catch {
            await gate.release()
            throw error
        }
    }

    private func readExclusively(
        profile: ClaudeProfile,
        includeUsage: Bool,
        mayRestart: Bool,
    ) async throws(ClaudeProviderError) -> ClaudeUsageResult {
        let candidates = try credentialStore.load(for: profile)
        guard !candidates.isEmpty else {
            throw .signedOut
        }
        var terminalError: ClaudeProviderError?
        for candidate in candidates {
            guard candidate.credential.canReadUsage else {
                terminalError = .missingProfileScope
                continue
            }
            do {
                return try await read(
                    candidate: candidate,
                    generation: ClaudeCredentialGeneration(candidates),
                    profile: profile,
                    includeUsage: includeUsage,
                )
            } catch .credentialChanged where mayRestart {
                return try await readExclusively(
                    profile: profile,
                    includeUsage: includeUsage,
                    mayRestart: false,
                )
            } catch let error where error.allowsCredentialFallback {
                terminalError = error
            }
        }
        throw terminalError ?? .signedOut
    }

    private func read(
        candidate initialCandidate: ClaudeCredentialCandidate,
        generation initialGeneration: ClaudeCredentialGeneration,
        profile: ClaudeProfile,
        includeUsage: Bool,
    ) async throws(ClaudeProviderError) -> ClaudeUsageResult {
        var state = try await prepareCredentialState(
            ClaudeReadState(candidate: initialCandidate, generation: initialGeneration),
            profile: profile,
        )
        var identity: ClaudeIdentity
        (state, identity) = try await verifiedIdentity(using: state, profile: profile)
        var metrics: [ClaudeMetric] = []
        if includeUsage {
            let usageResult = try await usage(
                using: state,
                identity: identity,
                profile: profile,
            )
            state = usageResult.state
            identity = usageResult.identity
            metrics = usageResult.metrics
        }

        let current = try credentialStore.load(for: profile)
        guard ClaudeCredentialGeneration(current) == state.generation else {
            throw .credentialChanged
        }
        return ClaudeUsageResult(
            identity: identity,
            planName: formatPlan(state.candidate.credential),
            metrics: metrics,
            observedAt: now(),
        )
    }

    private func prepareCredentialState(
        _ state: ClaudeReadState,
        profile: ClaudeProfile,
    ) async throws(ClaudeProviderError) -> ClaudeReadState {
        guard needsRefresh(state.candidate.credential) else {
            return state
        }
        if profile.expectedIdentity != nil {
            let response = try await send(profileRequest(state.candidate.credential.accessToken))
            try requireSuccess(response)
            try verify(decodeIdentity(response.body), expected: profile.expectedIdentity)
        }
        let refreshed = try await refresh(state.candidate, profile: profile, force: false)
        return ClaudeReadState(candidate: refreshed.0, generation: refreshed.1)
    }

    private func verifiedIdentity(
        using initialState: ClaudeReadState,
        profile: ClaudeProfile,
    ) async throws(ClaudeProviderError) -> (ClaudeReadState, ClaudeIdentity) {
        var state = initialState
        var response = try await send(profileRequest(state.candidate.credential.accessToken))
        if response.isAuthenticationFailure {
            guard profile.expectedIdentity == nil else {
                throw .reauthenticationRequired
            }
            let refreshed = try await refresh(state.candidate, profile: profile, force: true)
            state = ClaudeReadState(candidate: refreshed.0, generation: refreshed.1)
            response = try await send(profileRequest(state.candidate.credential.accessToken))
        }
        try requireSuccess(response)
        let identity = try decodeIdentity(response.body)
        try verify(identity, expected: profile.expectedIdentity)
        return (state, identity)
    }

    private func usage(
        using initialState: ClaudeReadState,
        identity initialIdentity: ClaudeIdentity,
        profile: ClaudeProfile,
    ) async throws(ClaudeProviderError) -> ClaudeUsageReadResult {
        var state = initialState
        var identity = initialIdentity
        var response = try await send(usageRequest(state.candidate.credential.accessToken))
        if response.isAuthenticationFailure {
            let refreshed = try await refresh(state.candidate, profile: profile, force: true)
            state = ClaudeReadState(candidate: refreshed.0, generation: refreshed.1)
            let identityResult = try await verifiedIdentity(using: state, profile: profile)
            state = identityResult.0
            identity = identityResult.1
            response = try await send(usageRequest(state.candidate.credential.accessToken))
        }
        try requireSuccess(response)
        return try ClaudeUsageReadResult(
            state: state,
            identity: identity,
            metrics: ClaudeUsageDecoder.decode(response.body),
        )
    }

    private func refresh(
        _ candidate: ClaudeCredentialCandidate,
        profile: ClaudeProfile,
        force: Bool,
    ) async throws(ClaudeProviderError)
    -> (ClaudeCredentialCandidate, ClaudeCredentialGeneration) {
        guard allowsCredentialRefresh else {
            throw .reauthenticationRequired
        }
        guard let refreshToken = candidate.credential.refreshToken, !refreshToken.isEmpty else {
            throw .reauthenticationRequired
        }
        let refreshLease = try await refreshLock.acquire(for: profile)
        defer { refreshLease.release() }

        let lockedState = try lockedState(for: candidate, profile: profile)
        if shouldAdopt(
            lockedState,
            insteadOf: candidate,
            refreshToken: refreshToken,
            force: force,
        ) {
            return (lockedState.candidate, lockedState.generation)
        }
        let response = try await send(refreshRequest(refreshToken))
        let decoded = try decodeRefresh(response)
        let updated = try updatedCandidate(lockedState.candidate, from: decoded)
        let nextGeneration = try persist(updated, from: lockedState, profile: profile)
        return (updated, nextGeneration)
    }

    private func lockedState(
        for candidate: ClaudeCredentialCandidate,
        profile: ClaudeProfile,
    ) throws(ClaudeProviderError) -> ClaudeReadState {
        let candidates = try credentialStore.load(for: profile)
        guard let lockedCandidate = candidates.first(where: { $0.location == candidate.location })
        else {
            throw .credentialChanged
        }
        return ClaudeReadState(
            candidate: lockedCandidate,
            generation: ClaudeCredentialGeneration(candidates),
        )
    }

    private func shouldAdopt(
        _ lockedState: ClaudeReadState,
        insteadOf candidate: ClaudeCredentialCandidate,
        refreshToken: String,
        force: Bool,
    ) -> Bool {
        lockedState.candidate.credential.accessToken != candidate.credential.accessToken
            || lockedState.candidate.credential.refreshToken != refreshToken
            || (!force && !needsRefresh(lockedState.candidate.credential))
    }

    private func decodeRefresh(
        _ response: ClaudeHTTPResponse,
    ) throws(ClaudeProviderError) -> RefreshEnvelope {
        if response.statusCode == 400 || response.statusCode == 401 {
            if refreshErrorCode(response.body) == "invalid_grant" {
                throw .reauthenticationRequired
            }
            throw .requestFailed(statusCode: response.statusCode)
        }
        try requireSuccess(response)
        do {
            return try JSONDecoder().decode(RefreshEnvelope.self, from: response.body)
        } catch {
            throw .invalidResponse
        }
    }

    private func updatedCandidate(
        _ candidate: ClaudeCredentialCandidate,
        from decoded: RefreshEnvelope,
    ) throws(ClaudeProviderError) -> ClaudeCredentialCandidate {
        let accessToken = decoded.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty,
              decoded.expiresIn.map({ $0.isFinite && $0 > 0 }) ?? true
        else {
            throw .invalidResponse
        }
        var updated = candidate
        updated.credential.accessToken = accessToken
        let rotatedRefreshToken = decoded.refreshToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let rotatedRefreshToken, !rotatedRefreshToken.isEmpty {
            updated.credential.refreshToken = rotatedRefreshToken
        }
        if let expiresIn = decoded.expiresIn {
            updated.credential.expiresAt = now().addingTimeInterval(expiresIn)
        }
        return updated
    }

    private func persist(
        _ candidate: ClaudeCredentialCandidate,
        from lockedState: ClaudeReadState,
        profile: ClaudeProfile,
    ) throws(ClaudeProviderError) -> ClaudeCredentialGeneration {
        do {
            return try credentialStore.save(
                candidate,
                ifUnchanged: lockedState.generation,
                for: profile,
            )
        } catch .credentialChanged {
            throw .credentialChanged
        } catch {
            throw .reauthenticationRequired
        }
    }
}

import Foundation

protocol CursorUsageReading: Sendable {
    func read(
        profile: CursorProfile,
        includeUsage: Bool,
    ) async throws(CursorProviderError) -> CursorUsageResult
}

private struct CursorReadState {
    let credential: CursorCredential
    var accessToken: String
    var refreshedDuringRead: Bool
}

private struct CursorUsageRead {
    let state: CursorReadState
    let identity: CursorIdentity
    let metrics: [CursorMetric]
}

struct CursorUsageReader: CursorUsageReading {
    static let identityURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetMe",
    )!
    static let usageURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
    )!
    static let planURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo",
    )!
    static let refreshURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    private let credentialLoader: any CursorCredentialLoading
    let transport: any CursorHTTPTransport
    private let gatePool: CursorRequestGatePool
    private let tokenCache: CursorAccessTokenCache
    let now: @Sendable () -> Date
    let timeout: TimeInterval
    private let allowsCredentialRefresh: Bool

    init(
        credentialLoader: any CursorCredentialLoading = CursorCredentialLoader(),
        transport: any CursorHTTPTransport = CursorURLSessionTransport(),
        gatePool: CursorRequestGatePool = .shared,
        tokenCache: CursorAccessTokenCache = .shared,
        now: @escaping @Sendable () -> Date = Date.init,
        timeout: TimeInterval = 15,
        allowsCredentialRefresh: Bool = true,
    ) {
        self.credentialLoader = credentialLoader
        self.transport = transport
        self.gatePool = gatePool
        self.tokenCache = tokenCache
        self.now = now
        self.timeout = timeout
        self.allowsCredentialRefresh = allowsCredentialRefresh
    }

    func read(
        profile: CursorProfile,
        includeUsage: Bool,
    ) async throws(CursorProviderError) -> CursorUsageResult {
        let gate = await gatePool.gate(for: profile)
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
        profile: CursorProfile,
        includeUsage: Bool,
        mayRestart: Bool,
    ) async throws(CursorProviderError) -> CursorUsageResult {
        let credential = try credentialLoader.load(for: profile)
        do {
            let result = try await read(
                credential: credential,
                profile: profile,
                includeUsage: includeUsage,
            )
            guard try credentialLoader.load(for: profile) == credential else {
                throw CursorProviderError.credentialChanged
            }
            return result
        } catch let error as CursorProviderError {
            if error == .credentialChanged, mayRestart {
                return try await readExclusively(
                    profile: profile,
                    includeUsage: includeUsage,
                    mayRestart: false,
                )
            }
            throw error
        } catch {
            throw .transportFailed
        }
    }

    private func read(
        credential: CursorCredential,
        profile: CursorProfile,
        includeUsage: Bool,
    ) async throws(CursorProviderError) -> CursorUsageResult {
        var state = try await prepareState(credential: credential, profile: profile)
        var identity: CursorIdentity
        (state, identity) = try await verifiedIdentity(using: state, profile: profile)

        var metrics: [CursorMetric] = []
        if includeUsage {
            let usage = try await usage(using: state, identity: identity, profile: profile)
            state = usage.state
            identity = usage.identity
            metrics = usage.metrics
        }
        let planName = await fetchPlan(accessToken: state.accessToken)
        return CursorUsageResult(
            identity: identity,
            planName: planName,
            metrics: metrics,
            observedAt: now(),
        )
    }

    private func prepareState(
        credential: CursorCredential,
        profile: CursorProfile,
    ) async throws(CursorProviderError) -> CursorReadState {
        let cached = await tokenCache.accessToken(for: profile, credential: credential)
        if let cached {
            try validate(cached, authenticationID: credential.authenticationID)
            if !needsRefresh(cached) {
                return CursorReadState(
                    credential: credential,
                    accessToken: cached,
                    refreshedDuringRead: false,
                )
            }
        }
        do {
            return try await refreshedState(credential: credential, profile: profile)
        } catch {
            if let cached, !isExpired(cached), error != .reauthenticationRequired {
                return CursorReadState(
                    credential: credential,
                    accessToken: cached,
                    refreshedDuringRead: false,
                )
            }
            throw error
        }
    }

    private func verifiedIdentity(
        using initialState: CursorReadState,
        profile: CursorProfile,
    ) async throws(CursorProviderError) -> (CursorReadState, CursorIdentity) {
        var state = initialState
        var response = try await send(connectRequest(
            url: Self.identityURL,
            token: state.accessToken,
        ))
        if response.isAuthenticationFailure {
            state = try await refreshAfterAuthenticationFailure(state, profile: profile)
            response = try await send(connectRequest(
                url: Self.identityURL,
                token: state.accessToken,
            ))
        }
        try requireSuccess(response)
        let remote = try CursorIdentityDecoder.decode(response.body)
        try verify(remote, credential: state.credential, expected: profile.expectedIdentity)
        return (state, remote.identity)
    }

    private func usage(
        using initialState: CursorReadState,
        identity initialIdentity: CursorIdentity,
        profile: CursorProfile,
    ) async throws(CursorProviderError) -> CursorUsageRead {
        var state = initialState
        var identity = initialIdentity
        var response = try await send(connectRequest(url: Self.usageURL, token: state.accessToken))
        if response.isAuthenticationFailure {
            state = try await refreshAfterAuthenticationFailure(state, profile: profile)
            let verified = try await verifiedIdentity(using: state, profile: profile)
            state = verified.0
            identity = verified.1
            response = try await send(connectRequest(url: Self.usageURL, token: state.accessToken))
        }
        try requireSuccess(response)
        return try CursorUsageRead(
            state: state,
            identity: identity,
            metrics: CursorUsageDecoder.decode(response.body),
        )
    }

    private func refreshAfterAuthenticationFailure(
        _ state: CursorReadState,
        profile: CursorProfile,
    ) async throws(CursorProviderError) -> CursorReadState {
        guard !state.refreshedDuringRead else {
            throw .reauthenticationRequired
        }
        return try await refreshedState(credential: state.credential, profile: profile)
    }

    private func refreshedState(
        credential: CursorCredential,
        profile: CursorProfile,
    ) async throws(CursorProviderError) -> CursorReadState {
        guard allowsCredentialRefresh, let refreshToken = credential.refreshToken else {
            throw .reauthenticationRequired
        }
        let response = try await send(refreshRequest(refreshToken))
        if response.statusCode == 400 || response.isAuthenticationFailure {
            throw .reauthenticationRequired
        }
        try requireSuccess(response)
        let accessToken = try decodeRefreshedAccessToken(response.body)
        try validate(accessToken, authenticationID: credential.authenticationID)
        await tokenCache.store(accessToken, for: profile, credential: credential)
        return CursorReadState(
            credential: credential,
            accessToken: accessToken,
            refreshedDuringRead: true,
        )
    }

    private func fetchPlan(accessToken: String) async -> String? {
        do {
            let response = try await send(connectRequest(url: Self.planURL, token: accessToken))
            guard (200 ..< 300).contains(response.statusCode) else {
                return nil
            }
            return CursorUsageDecoder.decodePlan(response.body)
        } catch {
            return nil
        }
    }
}

private extension CursorHTTPResponse {
    var isAuthenticationFailure: Bool {
        statusCode == 401 || statusCode == 403
    }
}

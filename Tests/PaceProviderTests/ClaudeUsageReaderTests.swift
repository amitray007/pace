import Foundation
@testable import PaceProviders
import Testing

@Suite("Claude usage reader")
struct ClaudeUsageReaderTests {
    @Test
    func `verifies remote identity before requesting usage`() async throws {
        let profile = ClaudeTestSupport.profile()
        let store = ClaudeStubCredentialStore(
            profile: profile,
            candidates: [ClaudeTestSupport.candidate()],
        )
        let transport = ClaudeStubTransport { request in
            request.url?.path == "/api/oauth/profile"
                ? ClaudeTestSupport.profileResponse()
                : ClaudeTestSupport.usageResponse()
        }
        let reader = ClaudeUsageReader(
            credentialStore: store,
            transport: transport,
            refreshLock: ClaudeNoopOAuthRefreshLock(),
            now: { ClaudeTestSupport.observedAt },
        )

        let result = try await reader.read(profile: profile, includeUsage: true)

        #expect(await transport.requests.map(\.url?.path) == [
            "/api/oauth/profile",
            "/api/oauth/usage",
        ])
        #expect(result.identity.stableKey == ClaudeTestSupport.identity().stableKey)
        #expect(result.identity.email == ClaudeTestSupport.identity().email)
        #expect(result.metrics.count == 1)
    }

    @Test
    func `refreshes persists and reverifies an expiring credential`() async throws {
        let profile = ClaudeTestSupport.profile()
        let store = ClaudeStubCredentialStore(
            profile: profile,
            candidates: [
                ClaudeTestSupport.candidate(
                    accessToken: "old-access",
                    refreshToken: "old-refresh",
                    expiresAt: ClaudeTestSupport.observedAt.addingTimeInterval(60),
                ),
            ],
        )
        let transport = ClaudeStubTransport { request in
            switch request.url?.path {
            case "/v1/oauth/token":
                return ClaudeTestSupport.refreshResponse()
            case "/api/oauth/profile":
                #expect(request.claudeBearerToken == "new-access")
                return ClaudeTestSupport.profileResponse()
            case "/api/oauth/usage":
                #expect(request.claudeBearerToken == "new-access")
                return ClaudeTestSupport.usageResponse()
            default:
                return ClaudeHTTPResponse(statusCode: 404, body: Data())
            }
        }
        let reader = ClaudeUsageReader(
            credentialStore: store,
            transport: transport,
            refreshLock: ClaudeNoopOAuthRefreshLock(),
            now: { ClaudeTestSupport.observedAt },
        )

        _ = try await reader.read(profile: profile, includeUsage: true)

        #expect(await transport.requests.map(\.url?.path) == [
            "/v1/oauth/token",
            "/api/oauth/profile",
            "/api/oauth/usage",
        ])
        #expect(store.saves.map(\.credential.refreshToken) == ["new-refresh"])
    }

    @Test
    func `publishes the reverified identity after usage authentication rotates`() async throws {
        let profile = ClaudeTestSupport.profile()
        let store = ClaudeStubCredentialStore(
            profile: profile,
            candidates: [
                ClaudeTestSupport.candidate(
                    accessToken: "old-access",
                    refreshToken: "old-refresh",
                ),
            ],
        )
        let transport = ClaudeStubTransport { request in
            switch (request.url?.path, request.claudeBearerToken) {
            case ("/api/oauth/profile", "old-access"):
                ClaudeTestSupport.profileResponse()
            case ("/api/oauth/usage", "old-access"):
                ClaudeHTTPResponse(statusCode: 401, body: Data())
            case ("/v1/oauth/token", _):
                ClaudeTestSupport.refreshResponse()
            case ("/api/oauth/profile", "new-access"):
                ClaudeTestSupport.profileResponse(
                    accountID: "account-b",
                    organizationID: "organization-b",
                )
            case ("/api/oauth/usage", "new-access"):
                ClaudeTestSupport.usageResponse(percent: 75)
            default:
                ClaudeHTTPResponse(statusCode: 404, body: Data())
            }
        }
        let reader = ClaudeUsageReader(
            credentialStore: store,
            transport: transport,
            refreshLock: ClaudeNoopOAuthRefreshLock(),
            now: { ClaudeTestSupport.observedAt },
        )

        let result = try await reader.read(profile: profile, includeUsage: true)

        #expect(result.identity.accountID == "account-b")
        #expect(result.identity.organizationID == "organization-b")
    }

    @Test
    func `restarts when profile changes during usage instead of publishing stale data`(
    ) async throws {
        let profile = ClaudeTestSupport.profile()
        let accountA = ClaudeTestSupport.candidate(accessToken: "account-a")
        let accountB = ClaudeTestSupport.candidate(accessToken: "account-b")
        let store = ClaudeStubCredentialStore(profile: profile, candidates: [accountA])
        let transport = ClaudeStubTransport { request in
            if request.claudeBearerToken == "account-a", request.url?.path == "/api/oauth/usage" {
                store.replace(profile: profile, with: [accountB])
            }
            if request.url?.path == "/api/oauth/profile" {
                return request.claudeBearerToken == "account-a"
                    ? ClaudeTestSupport.profileResponse()
                    : ClaudeTestSupport.profileResponse(
                        accountID: "account-b",
                        organizationID: "organization-b",
                    )
            }
            return request.claudeBearerToken == "account-a"
                ? ClaudeTestSupport.usageResponse(percent: 25)
                : ClaudeTestSupport.usageResponse(percent: 75)
        }
        let reader = ClaudeUsageReader(
            credentialStore: store,
            transport: transport,
            now: { ClaudeTestSupport.observedAt },
        )

        let result = try await reader.read(profile: profile, includeUsage: true)

        #expect(result.identity.accountID == "account-b")
        let percentage = try #require(result.metrics
            .compactMap { metric -> ClaudePercentageMetric? in
                guard case let .percentage(value) = metric else { return nil }
                return value
            }.first)
        #expect(percentage.usedFraction == 0.75)
        #expect(await transport.requests.map(\.claudeBearerToken) == [
            "account-a", "account-a", "account-b", "account-b",
        ])
    }

    @Test
    func `falls back from stale keychain credential to profile file`() async throws {
        let profile = ClaudeTestSupport.profile()
        let keychain = ClaudeTestSupport.candidate(
            accessToken: "stale",
            refreshToken: nil,
            location: .keychain(service: "Claude Code-credentials", account: "user"),
        )
        let file = ClaudeTestSupport.candidate(accessToken: "fresh")
        let store = ClaudeStubCredentialStore(profile: profile, candidates: [keychain, file])
        let transport = ClaudeStubTransport { request in
            if request.claudeBearerToken == "stale" {
                return ClaudeHTTPResponse(statusCode: 401, body: Data())
            }
            return request.url?.path == "/api/oauth/profile"
                ? ClaudeTestSupport.profileResponse()
                : ClaudeTestSupport.usageResponse()
        }
        let reader = ClaudeUsageReader(
            credentialStore: store,
            transport: transport,
            now: { ClaudeTestSupport.observedAt },
        )

        let result = try await reader.read(profile: profile, includeUsage: true)

        #expect(result.identity.stableKey == ClaudeTestSupport.identity().stableKey)
        #expect(await transport.requests.map(\.claudeBearerToken) == ["stale", "fresh", "fresh"])
    }

    @Test
    func `does not contact Claude without profile scope`() async {
        let profile = ClaudeTestSupport.profile()
        for scopes: Set<String> in [["user:inference"], []] {
            let store = ClaudeStubCredentialStore(
                profile: profile,
                candidates: [ClaudeTestSupport.candidate(scopes: scopes)],
            )
            let transport = ClaudeStubTransport { _ in
                ClaudeHTTPResponse(statusCode: 500, body: Data())
            }
            let reader = ClaudeUsageReader(
                credentialStore: store,
                transport: transport,
                gate: ClaudeRequestGate(),
                now: { ClaudeTestSupport.observedAt },
            )

            await #expect(throws: ClaudeProviderError.missingProfileScope) {
                try await reader.read(profile: profile, includeUsage: true)
            }
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test
    func `preserves rate limit and does not try another credential`() async {
        let profile = ClaudeTestSupport.profile()
        let store = ClaudeStubCredentialStore(
            profile: profile,
            candidates: [
                ClaudeTestSupport.candidate(accessToken: "first"),
                ClaudeTestSupport.candidate(accessToken: "second"),
            ],
        )
        let transport = ClaudeStubTransport { request in
            request.url?.path == "/api/oauth/profile"
                ? ClaudeTestSupport.profileResponse()
                : ClaudeHTTPResponse(
                    statusCode: 429,
                    headers: ["Retry-After": "120"],
                    body: Data(),
                )
        }
        let reader = ClaudeUsageReader(
            credentialStore: store,
            transport: transport,
            now: { ClaudeTestSupport.observedAt },
        )

        await #expect(throws: ClaudeProviderError.rateLimited(retryAfter: 120)) {
            try await reader.read(profile: profile, includeUsage: true)
        }
        #expect(await transport.requests.map(\.claudeBearerToken) == ["first", "first"])
    }

    @Test
    func `serializes requests across independent profiles`() async throws {
        let first = ClaudeTestSupport.profile("first")
        let second = ClaudeTestSupport.profile("second")
        let store = ClaudeStubCredentialStore(candidatesByPath: [
            first.directory.path: [ClaudeTestSupport.candidate("first", accessToken: "first")],
            second.directory.path: [ClaudeTestSupport.candidate("second", accessToken: "second")],
        ])
        let concurrency = ClaudeTransportConcurrency()
        let transport = ClaudeStubTransport { request in
            await concurrency.begin()
            try await Task.sleep(for: .milliseconds(5))
            await concurrency.end()
            return request.url?.path == "/api/oauth/profile"
                ? ClaudeTestSupport.profileResponse(
                    accountID: request.claudeBearerToken ?? "unknown",
                    organizationID: request.claudeBearerToken ?? "unknown",
                )
                : ClaudeTestSupport.usageResponse()
        }
        let reader = ClaudeUsageReader(
            credentialStore: store,
            transport: transport,
            now: { ClaudeTestSupport.observedAt },
        )

        async let firstResult = reader.read(profile: first, includeUsage: true)
        async let secondResult = reader.read(profile: second, includeUsage: true)
        _ = try await [firstResult, secondResult]

        #expect(await concurrency.maximum == 1)
    }
}

extension ClaudeUsageReaderTests {
    @Test
    func `identity mismatch blocks proactive refresh and credential write`() async {
        let expected = ClaudeTestSupport.identity().providerIdentity
        let profile = ClaudeTestSupport.profile(expectedIdentity: expected)
        let store = ClaudeStubCredentialStore(
            profile: profile,
            candidates: [
                ClaudeTestSupport.candidate(
                    accessToken: "other-access",
                    expiresAt: ClaudeTestSupport.observedAt.addingTimeInterval(60),
                ),
            ],
        )
        let transport = ClaudeStubTransport { _ in
            ClaudeTestSupport.profileResponse(
                accountID: "other-account",
                organizationID: "other-organization",
            )
        }
        let reader = ClaudeUsageReader(
            credentialStore: store,
            transport: transport,
            refreshLock: ClaudeNoopOAuthRefreshLock(),
            now: { ClaudeTestSupport.observedAt },
        )

        await #expect(throws: ClaudeProviderError.identityMismatch) {
            try await reader.read(profile: profile, includeUsage: true)
        }

        #expect(await transport.requests.map(\.url?.path) == ["/api/oauth/profile"])
        #expect(store.saves.isEmpty)
    }

    @Test
    func `reverifies a rotated usage token before retrying usage`() async {
        let expected = ClaudeTestSupport.identity().providerIdentity
        let profile = ClaudeTestSupport.profile(expectedIdentity: expected)
        let store = ClaudeStubCredentialStore(
            profile: profile,
            candidates: [
                ClaudeTestSupport.candidate(
                    accessToken: "old-access",
                    refreshToken: "old-refresh",
                ),
            ],
        )
        let transport = ClaudeStubTransport { request in
            switch (request.url?.path, request.claudeBearerToken) {
            case ("/api/oauth/profile", "old-access"):
                ClaudeTestSupport.profileResponse()
            case ("/api/oauth/usage", "old-access"):
                ClaudeHTTPResponse(statusCode: 401, body: Data())
            case ("/v1/oauth/token", _):
                ClaudeTestSupport.refreshResponse()
            case ("/api/oauth/profile", "new-access"):
                ClaudeTestSupport.profileResponse(
                    accountID: "other-account",
                    organizationID: "other-organization",
                )
            default:
                ClaudeTestSupport.usageResponse()
            }
        }
        let reader = ClaudeUsageReader(
            credentialStore: store,
            transport: transport,
            refreshLock: ClaudeNoopOAuthRefreshLock(),
            now: { ClaudeTestSupport.observedAt },
        )

        await #expect(throws: ClaudeProviderError.identityMismatch) {
            try await reader.read(profile: profile, includeUsage: true)
        }

        #expect(await transport.requests.map(\.url?.path) == [
            "/api/oauth/profile",
            "/api/oauth/usage",
            "/v1/oauth/token",
            "/api/oauth/profile",
        ])
    }

    @Test
    func `rotated token write failure requires reauthentication`() async {
        let profile = ClaudeTestSupport.profile()
        let store = ClaudeStubCredentialStore(
            profile: profile,
            candidates: [
                ClaudeTestSupport.candidate(
                    expiresAt: ClaudeTestSupport.observedAt.addingTimeInterval(60),
                ),
            ],
            saveError: .credentialWriteFailed,
        )
        let transport = ClaudeStubTransport { _ in
            ClaudeTestSupport.refreshResponse()
        }
        let reader = ClaudeUsageReader(
            credentialStore: store,
            transport: transport,
            refreshLock: ClaudeNoopOAuthRefreshLock(),
            now: { ClaudeTestSupport.observedAt },
        )

        await #expect(throws: ClaudeProviderError.reauthenticationRequired) {
            try await reader.read(profile: profile, includeUsage: true)
        }
    }

    @Test
    func `cancelled queued gate waiter does not retain the lock`() async throws {
        let gate = ClaudeRequestGate()
        try await gate.acquire()
        let waiter = Task {
            try await gate.acquire()
        }
        try await Task.sleep(for: .milliseconds(10))
        waiter.cancel()
        await gate.release()

        var receivedCancellation = false
        do {
            try await waiter.value
        } catch is CancellationError {
            receivedCancellation = true
        } catch {}
        #expect(receivedCancellation)

        try await gate.acquire()
        await gate.release()
    }
}

private actor ClaudeTransportConcurrency {
    private var active = 0
    private(set) var maximum = 0

    func begin() {
        active += 1
        maximum = max(maximum, active)
    }

    func end() {
        active -= 1
    }
}

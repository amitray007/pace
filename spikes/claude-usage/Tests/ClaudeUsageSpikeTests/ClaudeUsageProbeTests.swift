@testable import ClaudeUsageSpikeCore
import Foundation
import Testing

@Suite("Claude usage probe")
struct ClaudeUsageProbeTests {
    @Test
    func `verifies identity before fetching usage`() async throws {
        let identity = ClaudeIdentity(accountID: "account-a", organizationID: "organization-a")
        let profile = ClaudeSpikeTestSupport.profile(expectedIdentity: identity)
        let transport = StubTransport { request in
            switch request.url?.path {
            case "/api/oauth/profile":
                ClaudeSpikeTestSupport.profileResponse()
            case "/api/oauth/usage":
                ClaudeSpikeTestSupport.usageResponse(percent: 42)
            default:
                ClaudeHTTPResponse(statusCode: 404, body: Data())
            }
        }
        let probe = ClaudeUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                candidates: [ClaudeSpikeTestSupport.candidate()],
            ),
            transport: transport,
            now: { ClaudeSpikeTestSupport.referenceDate },
        )

        let result = try await probe.probe(profile)
        let requests = await transport.requests()

        #expect(requests.map(\.url?.path) == ["/api/oauth/profile", "/api/oauth/usage"])
        #expect(result.identity.stableKey == identity.stableKey)
        #expect(result.planName == "Max 20x")
        #expect(result.metrics.count == 1)
    }

    @Test
    func `identity mismatch blocks the usage request`() async throws {
        let profile = ClaudeSpikeTestSupport.profile(
            expectedIdentity: ClaudeIdentity(
                accountID: "expected-account",
                organizationID: "expected-organization",
            ),
        )
        let transport = StubTransport { _ in
            ClaudeSpikeTestSupport.profileResponse(
                accountID: "other-account",
                organizationID: "other-organization",
            )
        }
        let probe = ClaudeUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                candidates: [ClaudeSpikeTestSupport.candidate()],
            ),
            transport: transport,
        )

        await #expect(throws: ClaudeSpikeError.identityMismatch) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().map(\.url?.path) == ["/api/oauth/profile"])
    }

    @Test
    func `falls back from stale keychain credential to profile file`() async throws {
        let profile = ClaudeSpikeTestSupport.profile()
        let transport = StubTransport { request in
            if request.bearerToken == "stale" {
                return ClaudeHTTPResponse(statusCode: 401, body: Data())
            }
            switch request.url?.path {
            case "/api/oauth/profile":
                return ClaudeSpikeTestSupport.profileResponse()
            case "/api/oauth/usage":
                return ClaudeSpikeTestSupport.usageResponse(percent: 55)
            default:
                return ClaudeHTTPResponse(statusCode: 404, body: Data())
            }
        }
        let probe = ClaudeUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                candidates: [
                    ClaudeSpikeTestSupport.candidate(accessToken: "stale", source: .keychain),
                    ClaudeSpikeTestSupport.candidate(accessToken: "fresh", source: .file),
                ],
            ),
            transport: transport,
        )

        let result = try await probe.probe(profile)
        let requests = await transport.requests()

        #expect(result.credentialSource == .file)
        #expect(requests.map(\.bearerToken) == ["stale", "fresh", "fresh"])
        #expect(requests.map(\.url?.path) == [
            "/api/oauth/profile",
            "/api/oauth/profile",
            "/api/oauth/usage",
        ])
    }

    @Test
    func `does not contact Claude for inference-only credential`() async throws {
        let profile = ClaudeSpikeTestSupport.profile()
        let transport = StubTransport { _ in
            ClaudeHTTPResponse(statusCode: 500, body: Data())
        }
        let probe = ClaudeUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                candidates: [
                    ClaudeSpikeTestSupport.candidate(scopes: ["user:inference"]),
                ],
            ),
            transport: transport,
        )

        await #expect(throws: ClaudeSpikeError.missingProfileScope) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test
    func `preserves server retry interval and does not try another credential`() async throws {
        let profile = ClaudeSpikeTestSupport.profile()
        let transport = StubTransport { request in
            if request.url?.path == "/api/oauth/profile" {
                return ClaudeSpikeTestSupport.profileResponse()
            }
            return ClaudeHTTPResponse(
                statusCode: 429,
                headers: ["Retry-After": "120"],
                body: Data(),
            )
        }
        let probe = ClaudeUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                candidates: [
                    ClaudeSpikeTestSupport.candidate(accessToken: "first", source: .keychain),
                    ClaudeSpikeTestSupport.candidate(accessToken: "second", source: .file),
                ],
            ),
            transport: transport,
        )

        await #expect(throws: ClaudeSpikeError.rateLimited(retryAfter: 120)) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().map(\.bearerToken) == ["first", "first"])
    }

    @Test
    func `rejects duplicate identity across explicit profiles`() async throws {
        let first = ClaudeSpikeTestSupport.profile("first")
        let second = ClaudeSpikeTestSupport.profile("second")
        let loader = StubCredentialLoader(candidatesByPath: [
            first.configDirectory.path: [ClaudeSpikeTestSupport.candidate(accessToken: "first")],
            second.configDirectory.path: [ClaudeSpikeTestSupport.candidate(accessToken: "second")],
        ])
        let transport = StubTransport { request in
            request.url?.path == "/api/oauth/profile"
                ? ClaudeSpikeTestSupport.profileResponse()
                : ClaudeSpikeTestSupport.usageResponse()
        }
        let probe = ClaudeUsageProbe(credentialLoader: loader, transport: transport)

        await #expect(throws: ClaudeSpikeError.duplicateIdentity) {
            try await probe.probeSequentially([first, second])
        }
    }

    @Test
    func `reports signed out profile without a request`() async throws {
        let profile = ClaudeSpikeTestSupport.profile()
        let transport = StubTransport { _ in
            ClaudeHTTPResponse(statusCode: 500, body: Data())
        }
        let probe = ClaudeUsageProbe(
            credentialLoader: StubCredentialLoader(profile: profile, candidates: []),
            transport: transport,
        )

        await #expect(throws: ClaudeSpikeError.signedOut) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test
    func `maps transport error without leaking its contents`() async throws {
        let profile = ClaudeSpikeTestSupport.profile()
        let transport = StubTransport { _ in
            throw URLError(.cannotConnectToHost)
        }
        let probe = ClaudeUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                candidates: [ClaudeSpikeTestSupport.candidate()],
            ),
            transport: transport,
        )

        await #expect(throws: ClaudeSpikeError.transportFailed) {
            try await probe.probe(profile)
        }
    }
}

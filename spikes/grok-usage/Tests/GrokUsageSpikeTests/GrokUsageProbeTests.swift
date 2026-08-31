import Foundation
@testable import GrokUsageSpikeCore
import Testing

@Suite("Grok usage probe")
struct GrokUsageProbeTests {
    @Test
    func `verifies remote identity before requesting billing`() async {
        let expected = GrokSpikeTestSupport.identity(userID: "expected", principalID: "expected")
        let profile = GrokSpikeTestSupport.profile("a", expectedIdentity: expected)
        let transport = StubTransport { _ in
            GrokSpikeTestSupport.identityResponse(userID: "other", principalID: "other")
        }
        let probe = makeProbe(profile: profile, transport: transport)

        await #expect(throws: GrokSpikeError.identityMismatch) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().count == 1)
    }

    @Test
    func `uses the verified server user for billing`() async throws {
        let profile = GrokSpikeTestSupport.profile("a")
        let token = "redacted-token"
        let transport = StubTransport { request in
            if request.url?.path.hasSuffix("/user") == true {
                return GrokSpikeTestSupport.identityResponse(userID: "canonical-user")
            }
            return GrokSpikeTestSupport.billingResponse()
        }
        let probe = try GrokUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                credential: GrokCredential(
                    accessToken: token,
                    localIdentity: GrokSpikeTestSupport.identity(userID: "stale-local"),
                ),
            ),
            transport: transport,
            baseURL: #require(URL(string: "https://example.invalid/v1")),
            now: { GrokSpikeTestSupport.referenceDate },
        )

        let result = try await probe.probe(profile)
        let requests = await transport.requests()

        #expect(result.identity.userID == "canonical-user")
        #expect(result.planName == "SuperGrok Heavy")
        #expect(result.metrics.count == 2)
        #expect(result.observedAt == GrokSpikeTestSupport.referenceDate)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.bearerToken == token })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "X-XAI-Token-Auth") == "xai-grok-cli"
        })
        #expect(requests[0].value(forHTTPHeaderField: "x-userid") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "x-userid") == "canonical-user")
    }

    @Test
    func `preserves rate limit interval and stops`() async {
        let profile = GrokSpikeTestSupport.profile("a")
        let transport = StubTransport { request in
            if request.url?.path.hasSuffix("/user") == true {
                return GrokSpikeTestSupport.identityResponse()
            }
            return GrokHTTPResponse(
                statusCode: 429,
                headers: ["Retry-After": "30"],
                body: Data(),
            )
        }
        let probe = makeProbe(profile: profile, transport: transport)

        await #expect(throws: GrokSpikeError.rateLimited(retryAfter: 30)) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().count == 2)
    }

    @Test
    func `maps authentication rejection to reauthentication`() async {
        let profile = GrokSpikeTestSupport.profile("a")
        let transport = StubTransport { _ in
            GrokHTTPResponse(statusCode: 401, body: Data())
        }
        let probe = makeProbe(profile: profile, transport: transport)

        await #expect(throws: GrokSpikeError.reauthenticationRequired) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().count == 1)
    }

    @Test
    func `rejects duplicate identity across explicit profiles`() async throws {
        let first = GrokSpikeTestSupport.profile("first")
        let second = GrokSpikeTestSupport.profile("second")
        let credential = GrokCredential(
            accessToken: "redacted-token",
            localIdentity: GrokSpikeTestSupport.identity(),
        )
        let probe = try GrokUsageProbe(
            credentialLoader: StubCredentialLoader(credentialsByPath: [
                first.grokHome.path: credential,
                second.grokHome.path: credential,
            ]),
            transport: StubTransport { request in
                if request.url?.path.hasSuffix("/user") == true {
                    return GrokSpikeTestSupport.identityResponse()
                }
                return GrokSpikeTestSupport.billingResponse()
            },
            baseURL: #require(URL(string: "https://example.invalid/v1")),
        )

        await #expect(throws: GrokSpikeError.duplicateIdentity) {
            try await probe.probeSequentially([first, second])
        }
    }

    private func makeProbe(
        profile: GrokProfileBinding,
        transport: StubTransport,
    ) -> GrokUsageProbe {
        GrokUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                credential: GrokCredential(
                    accessToken: "redacted-token",
                    localIdentity: GrokSpikeTestSupport.identity(),
                ),
            ),
            transport: transport,
            baseURL: URL(string: "https://example.invalid/v1")!,
        )
    }
}

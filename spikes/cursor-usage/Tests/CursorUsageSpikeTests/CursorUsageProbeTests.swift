@testable import CursorUsageSpikeCore
import Foundation
import Testing

@Suite("Cursor usage probe")
struct CursorUsageProbeTests {
    @Test
    func `verifies server identity before fetching usage`() async {
        let expected = CursorSpikeTestSupport.identity(userID: "expected")
        let profile = CursorSpikeTestSupport.profile("a", expectedIdentity: expected)
        let transport = StubTransport { _ in
            CursorSpikeTestSupport.identityResponse(userID: "other")
        }
        let probe = CursorUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                credential: CursorCredential(
                    accessToken: CursorSpikeTestSupport.token(),
                    authID: "auth0|user-a",
                    source: .isolatedFile,
                ),
            ),
            transport: transport,
        )

        await #expect(throws: CursorSpikeError.identityMismatch) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().count == 1)
    }

    @Test
    func `rejects credential whose JWT subject differs from verified user`() async {
        let profile = CursorSpikeTestSupport.profile("a")
        let transport = StubTransport { _ in CursorSpikeTestSupport.usageResponse() }
        let probe = CursorUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                credential: CursorCredential(
                    accessToken: CursorSpikeTestSupport.token(userID: "other"),
                    authID: "auth0|verified",
                    source: .isolatedFile,
                ),
            ),
            transport: transport,
        )

        await #expect(throws: CursorSpikeError.invalidCredential) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test
    func `fetches usage then optional plan with verified credential`() async throws {
        let profile = CursorSpikeTestSupport.profile("a")
        let token = CursorSpikeTestSupport.token()
        let transport = StubTransport { request in
            if request.url?.absoluteString.hasSuffix("/GetMe") == true {
                return CursorSpikeTestSupport.identityResponse()
            }
            if request.url?.absoluteString.contains("GetCurrentPeriodUsage") == true {
                return CursorSpikeTestSupport.usageResponse()
            }
            return CursorHTTPResponse(
                statusCode: 200,
                body: Data(#"{"planInfo":{"planName":"pro"}}"#.utf8),
            )
        }
        let probe = CursorUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                credential: CursorCredential(
                    accessToken: token,
                    authID: "auth0|user-a",
                    source: .isolatedFile,
                ),
            ),
            transport: transport,
            now: { CursorSpikeTestSupport.referenceDate },
        )

        let result = try await probe.probe(profile)
        let requests = await transport.requests()

        #expect(result.identity.stableKey == CursorSpikeTestSupport.identity().stableKey)
        #expect(result.planName == "Pro")
        #expect(result.metrics.count == 3)
        #expect(result.observedAt == CursorSpikeTestSupport.referenceDate)
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.bearerToken == token })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1"
        })
    }

    @Test
    func `optional plan failure preserves primary usage`() async throws {
        let profile = CursorSpikeTestSupport.profile("a")
        let transport = StubTransport { request in
            if request.url?.absoluteString.hasSuffix("/GetMe") == true {
                return CursorSpikeTestSupport.identityResponse()
            }
            if request.url?.absoluteString.contains("GetCurrentPeriodUsage") == true {
                return CursorSpikeTestSupport.usageResponse()
            }
            return CursorHTTPResponse(statusCode: 503, body: Data())
        }
        let probe = makeProbe(profile: profile, transport: transport)

        let result = try await probe.probe(profile)

        #expect(result.planName == nil)
        #expect(result.metrics.count == 3)
    }

    @Test
    func `preserves retry interval and does not request plan`() async {
        let profile = CursorSpikeTestSupport.profile("a")
        let transport = StubTransport { request in
            if request.url?.absoluteString.hasSuffix("/GetMe") == true {
                return CursorSpikeTestSupport.identityResponse()
            }
            return CursorHTTPResponse(
                statusCode: 429,
                headers: ["Retry-After": "45"],
                body: Data(),
            )
        }
        let probe = makeProbe(profile: profile, transport: transport)

        await #expect(throws: CursorSpikeError.rateLimited(retryAfter: 45)) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().count == 2)
    }

    @Test
    func `rejects duplicate identity across explicit profiles`() async {
        let first = CursorSpikeTestSupport.profile("first")
        let second = CursorSpikeTestSupport.profile("second")
        let token = CursorSpikeTestSupport.token()
        let probe = CursorUsageProbe(
            credentialLoader: StubCredentialLoader(credentialsByPath: [
                first.homeDirectory.path: CursorCredential(
                    accessToken: token,
                    authID: "auth0|user-a",
                    source: .isolatedFile,
                ),
                second.homeDirectory.path: CursorCredential(
                    accessToken: token,
                    authID: "auth0|user-a",
                    source: .isolatedFile,
                ),
            ]),
            transport: StubTransport { request in
                if request.url?.absoluteString.hasSuffix("/GetMe") == true {
                    return CursorSpikeTestSupport.identityResponse()
                }
                if request.url?.absoluteString.contains("GetCurrentPeriodUsage") == true {
                    return CursorSpikeTestSupport.usageResponse()
                }
                return CursorHTTPResponse(statusCode: 404, body: Data())
            },
        )

        await #expect(throws: CursorSpikeError.duplicateIdentity) {
            try await probe.probeSequentially([first, second])
        }
    }

    private func makeProbe(
        profile: CursorProfileBinding,
        transport: StubTransport,
    ) -> CursorUsageProbe {
        CursorUsageProbe(
            credentialLoader: StubCredentialLoader(
                profile: profile,
                credential: CursorCredential(
                    accessToken: CursorSpikeTestSupport.token(),
                    authID: "auth0|user-a",
                    source: .isolatedFile,
                ),
            ),
            transport: transport,
        )
    }
}

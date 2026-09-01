import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Grok usage reader")
struct GrokUsageReaderTests {
    @Test
    func `verifies remote identity before requesting billing`() async throws {
        let expected = GrokTestSupport.identity(userID: "expected").providerIdentity
        let profile = GrokTestSupport.profile("personal", expectedIdentity: expected)
        let transport = GrokStubTransport { _ in
            GrokTestSupport.identityResponse(userID: "other")
        }
        let reader = reader(profile: profile, transport: transport)

        await #expect(throws: GrokProviderError.identityMismatch) {
            try await reader.read(profile: profile, includeUsage: true)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `uses selected profile token and canonical server user for billing`() async throws {
        let profile = GrokTestSupport.profile()
        let transport = GrokStubTransport { request in
            if request.url?.path.hasSuffix("/user") == true {
                return GrokTestSupport.identityResponse(userID: "canonical-user")
            }
            return GrokTestSupport.billingResponse()
        }
        let reader = reader(profile: profile, token: "selected-token", transport: transport)

        let result = try await reader.read(profile: profile, includeUsage: true)
        let requests = await transport.requests

        #expect(result.identity.userID == "canonical-user")
        #expect(result.metrics.count == 2)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer selected-token"
        })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "X-XAI-Token-Auth") == "xai-grok-cli"
        })
        #expect(requests[0].value(forHTTPHeaderField: "x-userid") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "x-userid") == "canonical-user")
    }

    @Test
    func `preserves rate limit retry interval`() async throws {
        let profile = GrokTestSupport.profile()
        let transport = GrokStubTransport { request in
            if request.url?.path.hasSuffix("/user") == true {
                return GrokTestSupport.identityResponse()
            }
            return GrokHTTPResponse(
                statusCode: 429,
                headers: ["Retry-After": "45"],
                body: Data(),
            )
        }
        let reader = reader(profile: profile, transport: transport)

        await #expect(throws: GrokProviderError.rateLimited(retryAfter: 45)) {
            try await reader.read(profile: profile, includeUsage: true)
        }
    }

    @Test
    func `decodes legacy monthly amount in production`() throws {
        let metrics = try GrokUsageDecoder.decodeUsage(Data(
            """
            {
              "config": {
                "monthlyLimit": {"val": 10000},
                "used": {"val": 2500},
                "billingPeriodEnd": "2026-09-30T00:00:00Z"
              }
            }
            """.utf8,
        ))

        guard case let .amount(metric) = try #require(metrics.first) else {
            Issue.record("Expected the legacy monthly amount metric")
            return
        }
        #expect(metric.id == "included-monthly")
        #expect(metric.used == Decimal(25))
        #expect(metric.limit == Decimal(100))
        #expect(metric.resetsAt != nil)
    }

    @Test
    func `treats omitted current-period percentage as zero`() throws {
        let metrics = try GrokUsageDecoder.decodeUsage(Data(
            """
            {
              "config": {
                "currentPeriod": {
                  "type": "USAGE_PERIOD_TYPE_WEEKLY",
                  "start": "2026-08-24T00:00:00Z",
                  "end": "2026-08-31T00:00:00Z"
                }
              }
            }
            """.utf8,
        ))

        guard case let .percentage(metric) = try #require(metrics.first) else {
            Issue.record("Expected the current-period percentage metric")
            return
        }
        #expect(metric.id == "included-weekly")
        #expect(metric.usedFraction == 0)
    }

    @Test
    func `rejects malformed production period dates`() {
        #expect(throws: GrokProviderError.invalidResponse) {
            _ = try GrokUsageDecoder.decodeUsage(Data(
                """
                {
                  "config": {
                    "creditUsagePercent": 10,
                    "currentPeriod": {
                      "type": "USAGE_PERIOD_TYPE_WEEKLY",
                      "start": "not-a-date",
                      "end": "2026-08-31T00:00:00Z"
                    }
                  }
                }
                """.utf8,
            ))
        }
    }

    @Test
    func `rejects negative production usage`() {
        #expect(throws: GrokProviderError.invalidResponse) {
            _ = try GrokUsageDecoder.decodeUsage(Data(
                """
                {
                  "config": {
                    "monthlyLimit": {"val": 10000},
                    "used": {"val": -1}
                  }
                }
                """.utf8,
            ))
        }
        #expect(throws: GrokProviderError.invalidResponse) {
            _ = try GrokUsageDecoder.decodeUsage(Data(
                """
                {
                  "config": {
                    "creditUsagePercent": -1
                  }
                }
                """.utf8,
            ))
        }
    }

    private func reader(
        profile: GrokProfile,
        token: String = "redacted-token",
        transport: GrokStubTransport,
    ) -> GrokUsageReader {
        GrokUsageReader(
            credentialLoader: GrokStubCredentialLoader(credentials: [
                profile.directory.path: GrokCredential(accessToken: token, expiresAt: nil),
            ]),
            transport: transport,
            baseURL: URL(string: "https://example.invalid/v1")!,
            now: { GrokTestSupport.observedAt },
        )
    }
}

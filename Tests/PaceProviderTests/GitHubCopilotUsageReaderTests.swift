import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("GitHub Copilot usage reader")
struct GitHubCopilotUsageReaderTests {
    @Test
    func `verifies durable identity before requesting usage`() async throws {
        let expected = GitHubCopilotTestSupport.identity(userID: 999).providerIdentity
        let profile = GitHubCopilotTestSupport.profile("personal", expectedIdentity: expected)
        let transport = GitHubCopilotStubTransport { _ in
            GitHubCopilotTestSupport.identityResponse(userID: 101)
        }
        let reader = makeReader(transport: transport)

        await #expect(throws: GitHubCopilotProviderError.identityMismatch) {
            try await reader.read(profile: profile, includeUsage: true)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `rejects login mismatch during initial registration`() async {
        let profile = GitHubCopilotTestSupport.profile("selected")
        let transport = GitHubCopilotStubTransport { _ in
            GitHubCopilotTestSupport.identityResponse(login: "different")
        }

        await #expect(throws: GitHubCopilotProviderError.identityMismatch) {
            try await makeReader(transport: transport).read(
                profile: profile,
                includeUsage: false,
            )
        }
    }

    @Test
    func `uses official identity request then compatibility quota request`() async throws {
        let profile = GitHubCopilotTestSupport.profile()
        let transport = GitHubCopilotStubTransport { request in
            if request.url?.path == "/user" {
                return GitHubCopilotTestSupport.identityResponse()
            }
            return GitHubCopilotTestSupport.usageResponse()
        }

        let result = try await makeReader(
            token: "selected-token",
            transport: transport,
        ).read(profile: profile, includeUsage: true)
        let requests = await transport.requests

        #expect(result.planName == "Individual")
        #expect(result.metrics.count == 1)
        #expect(requests.map { $0.url?.path } == ["/user", "/copilot_internal/user"])
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer selected-token")
        #expect(requests[0].value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "token selected-token")
        #expect(requests[1].value(forHTTPHeaderField: "Editor-Version") == "vscode/1.96.2")
        #expect(requests[1].value(forHTTPHeaderField: "X-Github-Api-Version") == "2025-04-01")
    }

    @Test
    func `preserves rate limit reset as retry interval`() async {
        let transport = GitHubCopilotStubTransport { _ in
            GitHubCopilotHTTPResponse(
                statusCode: 403,
                headers: [
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": String(
                        Int(GitHubCopilotTestSupport.observedAt.timeIntervalSince1970 + 120),
                    ),
                ],
                body: Data(),
            )
        }

        await #expect(throws: GitHubCopilotProviderError.rateLimited(retryAfter: 120)) {
            try await makeReader(transport: transport).read(
                profile: GitHubCopilotTestSupport.profile(),
                includeUsage: false,
            )
        }
    }

    @Test
    func `maps ordinary forbidden response to reauthentication`() async {
        let transport = GitHubCopilotStubTransport { _ in
            GitHubCopilotHTTPResponse(statusCode: 403, body: Data())
        }

        await #expect(throws: GitHubCopilotProviderError.reauthenticationRequired) {
            try await makeReader(transport: transport).read(
                profile: GitHubCopilotTestSupport.profile(),
                includeUsage: false,
            )
        }
    }

    @Test
    func `transport rejects response while it exceeds the size bound`() async {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in Data("12345".utf8) {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        await #expect(throws: GitHubCopilotProviderError.invalidResponse) {
            _ = try await GitHubCopilotURLSessionTransport.boundedData(
                from: bytes,
                maximumSize: 4,
            )
        }
    }

    @Test
    func `transport accepts response at the exact size bound`() async throws {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in Data("1234".utf8) {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        let data = try await GitHubCopilotURLSessionTransport.boundedData(
            from: bytes,
            maximumSize: 4,
        )

        #expect(data == Data("1234".utf8))
    }

    @Test
    func `decodes legacy free quota and utc reset`() throws {
        let usage = try GitHubCopilotUsageDecoder.decodeUsage(Data(
            """
            {
              "copilot_plan": "free",
              "quota_reset_date_utc": "2026-10-01T00:00:00Z",
              "monthly_quotas": {"chat": 50, "completions": 2000},
              "limited_user_quotas": {"chat": 40, "completions": 1500}
            }
            """.utf8,
        ))

        #expect(usage.planName == "Free")
        #expect(usage.metrics.count == 2)
        guard case let .amount(chat) = usage.metrics[0] else {
            Issue.record("Expected legacy chat amount")
            return
        }
        #expect(chat.used == Decimal(10))
        #expect(chat.limit == Decimal(50))
        #expect(chat.resetsAt != nil)
    }

    @Test
    func `accepts organization managed response without quota buckets`() throws {
        let usage = try GitHubCopilotUsageDecoder.decodeUsage(Data(
            """
            {"copilot_plan":"business","token_based_billing":true,"quota_snapshots":{}}
            """.utf8,
        ))

        #expect(usage.planName == "Business")
        #expect(usage.isOrganizationManaged)
        #expect(usage.metrics.isEmpty)
    }

    @Test
    func `does not invent percentage from organization credit counter`() throws {
        let usage = try GitHubCopilotUsageDecoder.decodeUsage(Data(
            """
            {"token_based_billing":true,"quota_snapshots":{"premium_interactions":{
              "credits_used":18
            }}}
            """.utf8,
        ))

        #expect(usage.isOrganizationManaged)
        #expect(usage.metrics.isEmpty)
    }

    @Test
    func `rejects boolean quota numbers and malformed reset`() {
        #expect(throws: GitHubCopilotProviderError.quotaUnavailable) {
            _ = try GitHubCopilotUsageDecoder.decodeUsage(Data(
                """
                {"quota_snapshots":{"premium_interactions":{
                  "entitlement":true,"percent_remaining":true
                }}}
                """.utf8,
            ))
        }
        #expect(throws: GitHubCopilotProviderError.invalidResponse) {
            _ = try GitHubCopilotUsageDecoder.decodeUsage(Data(
                """
                {"quota_reset_date":"not-a-date","quota_snapshots":{
                  "premium_interactions":{"entitlement":300,"percent_remaining":50}
                }}
                """.utf8,
            ))
        }
    }

    private func makeReader(
        token: String = "redacted-token",
        transport: GitHubCopilotStubTransport,
    ) -> GitHubCopilotUsageReader {
        GitHubCopilotUsageReader(
            credentialLoader: GitHubCopilotStubCredentialLoader(token: token),
            transport: transport,
            now: { GitHubCopilotTestSupport.observedAt },
        )
    }
}

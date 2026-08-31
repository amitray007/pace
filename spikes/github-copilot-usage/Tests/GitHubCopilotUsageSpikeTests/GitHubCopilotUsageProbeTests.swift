import Foundation
@testable import GitHubCopilotUsageSpikeCore
import Testing

@Suite("GitHub Copilot usage probe")
struct GitHubCopilotUsageProbeTests {
    @Test
    func `verifies official GitHub identity before requesting Copilot usage`() async {
        let profile = GitHubCopilotTestSupport.profile(
            expectedIdentity: GitHubCopilotTestSupport.identity(id: 42),
        )
        let transport = StubHTTPTransport { _ in
            GitHubCopilotTestSupport.identityResponse(id: 99)
        }
        let probe = makeProbe(profile: profile, transport: transport)

        await #expect(throws: GitHubCopilotSpikeError.identityMismatch) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().count == 1)
    }

    @Test
    func `requires login match during first registration`() async {
        let profile = GitHubCopilotTestSupport.profile(login: "expected")
        let transport = StubHTTPTransport { _ in
            GitHubCopilotTestSupport.identityResponse(login: "other")
        }
        let probe = makeProbe(profile: profile, transport: transport)

        await #expect(throws: GitHubCopilotSpikeError.identityMismatch) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().count == 1)
    }

    @Test
    func `uses separate official identity and compatibility requests`() async throws {
        let profile = GitHubCopilotTestSupport.profile()
        let token = "redacted-token"
        let transport = StubHTTPTransport { request in
            if request.url?.path == "/user" {
                return GitHubCopilotTestSupport.identityResponse()
            }
            return GitHubCopilotTestSupport.usageResponse()
        }
        let probe = GitHubCopilotUsageProbe(
            credentialLoader: StubCredentialLoader(profile: profile, token: token),
            transport: transport,
            now: { GitHubCopilotTestSupport.referenceDate },
        )

        let result = try await probe.probe(profile)
        let requests = await transport.requests()

        #expect(result.identity.userID == 42)
        #expect(result.planName == "Pro")
        #expect(result.metrics.count == 2)
        #expect(result.observedAt == GitHubCopilotTestSupport.referenceDate)
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        #expect(requests[0].value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "token \(token)")
        #expect(requests[1].value(forHTTPHeaderField: "Editor-Plugin-Version") != nil)
    }

    @Test
    func `preserves retry interval`() async {
        let profile = GitHubCopilotTestSupport.profile()
        let transport = StubHTTPTransport { request in
            if request.url?.path == "/user" {
                return GitHubCopilotTestSupport.identityResponse()
            }
            return GitHubCopilotHTTPResponse(
                statusCode: 429,
                headers: ["Retry-After": "60"],
                body: Data(),
            )
        }
        let probe = makeProbe(profile: profile, transport: transport)

        await #expect(throws: GitHubCopilotSpikeError.rateLimited(retryAfter: 60)) {
            try await probe.probe(profile)
        }
        #expect(await transport.requests().count == 2)
    }

    @Test
    func `rejects duplicate durable GitHub identity`() async {
        let first = GitHubCopilotTestSupport.profile(login: "first")
        let second = GitHubCopilotTestSupport.profile(login: "second")
        let credential = GitHubCopilotCredential(token: "redacted-token")
        let transport = StubHTTPTransport { request in
            if request.url?.path == "/user" {
                let login = request.value(forHTTPHeaderField: "X-Test-Login") ?? "first"
                return GitHubCopilotTestSupport.identityResponse(id: 42, login: login)
            }
            return GitHubCopilotTestSupport.usageResponse()
        }
        let probe = GitHubCopilotUsageProbe(
            credentialLoader: StubCredentialLoader(credentialsByLogin: [
                first.githubLogin: credential,
                second.githubLogin: credential,
            ]),
            transport: LoginAwareTransport(base: transport, logins: ["first", "second"]),
        )

        await #expect(throws: GitHubCopilotSpikeError.duplicateIdentity) {
            try await probe.probeSequentially([first, second])
        }
    }

    private func makeProbe(
        profile: GitHubCopilotProfileBinding,
        transport: StubHTTPTransport,
    ) -> GitHubCopilotUsageProbe {
        GitHubCopilotUsageProbe(
            credentialLoader: StubCredentialLoader(profile: profile),
            transport: transport,
        )
    }
}

private actor LoginAwareTransport: GitHubCopilotHTTPTransport {
    let base: StubHTTPTransport
    var logins: [String]

    init(base: StubHTTPTransport, logins: [String]) {
        self.base = base
        self.logins = logins
    }

    func send(_ request: URLRequest) async throws -> GitHubCopilotHTTPResponse {
        var request = request
        if request.url?.path == "/user", !logins.isEmpty {
            request.setValue(logins.removeFirst(), forHTTPHeaderField: "X-Test-Login")
        }
        return try await base.send(request)
    }
}

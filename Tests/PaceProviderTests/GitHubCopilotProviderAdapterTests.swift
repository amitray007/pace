import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("GitHub Copilot provider adapter")
struct GitHubCopilotProviderAdapterTests {
    @Test
    func `discovers two explicit accounts and preserves bindings`() async throws {
        let personal = GitHubCopilotTestSupport.profile("personal")
        let work = GitHubCopilotTestSupport.profile("work")
        let reader = GitHubCopilotStubReader(results: [
            "personal": .success(GitHubCopilotTestSupport.result()),
            "work": .success(GitHubCopilotTestSupport.result(
                identity: GitHubCopilotTestSupport.identity(userID: 202, login: "work"),
            )),
        ])
        let adapter = GitHubCopilotProviderAdapter(
            profiles: [personal, work],
            reader: reader,
            now: { GitHubCopilotTestSupport.observedAt },
        )

        let accounts = try await adapter.discoverAccounts()

        #expect(accounts.map(\.suggestedDisplayName) == ["Personal", "Work"])
        #expect(accounts.map(\.credentialBinding) == [
            personal.credentialBinding,
            work.credentialBinding,
        ])
        #expect(Set(accounts.map(\.identity.subjectID)).count == 2)
        #expect(await reader.reads.allSatisfy { !$0.1 })
    }

    @Test
    func `signed out account does not hide healthy account`() async throws {
        let signedOut = GitHubCopilotTestSupport.profile("signed-out")
        let personal = GitHubCopilotTestSupport.profile("personal")
        let reader = GitHubCopilotStubReader(results: [
            "signed-out": .failure(.signedOut),
            "personal": .success(GitHubCopilotTestSupport.result()),
        ])
        let adapter = GitHubCopilotProviderAdapter(
            profiles: [signedOut, personal],
            reader: reader,
            now: Date.init,
        )

        let accounts = try await adapter.discoverAccounts()

        #expect(accounts.map(\.suggestedDisplayName) == ["Personal"])
    }

    @Test
    func `rejects duplicate durable identity across logins`() async {
        let reader = GitHubCopilotStubReader(results: [
            "personal": .success(GitHubCopilotTestSupport.result()),
            "alias": .success(GitHubCopilotTestSupport.result()),
        ])
        let adapter = GitHubCopilotProviderAdapter(
            profiles: [
                GitHubCopilotTestSupport.profile("personal"),
                GitHubCopilotTestSupport.profile("alias"),
            ],
            reader: reader,
            now: Date.init,
        )

        await #expect(
            throws: ProviderFailure.unavailable(code: "duplicate-github-copilot-identity"),
        ) {
            try await adapter.discoverAccounts()
        }
    }

    @Test
    func `refresh binds expected identity and owns normalized snapshots`() async throws {
        let profile = GitHubCopilotTestSupport.profile()
        let identity = GitHubCopilotTestSupport.identity()
        let account = GitHubCopilotTestSupport.account(profile: profile, identity: identity)
        let reader = GitHubCopilotStubReader(results: [
            "personal": .success(GitHubCopilotTestSupport.result(identity: identity)),
        ])
        let adapter = GitHubCopilotProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { GitHubCopilotTestSupport.observedAt },
        )

        let result = try await adapter.refresh(account)
        let read = try #require(await reader.reads.last)

        #expect(result.identity == account.identity)
        #expect(result.planName == "Individual")
        #expect(result.snapshots.map(\.id.accountID) == [account.id])
        #expect(result.snapshots.map(\.id.bucketID.rawValue) == ["credits"])
        #expect(result.snapshots.map(\.usedFraction) == [0.42])
        #expect(read.0.expectedIdentity == account.identity)
        #expect(read.1)
    }

    @Test
    func `accepts organization managed account without fabricating percentage`() async throws {
        let profile = GitHubCopilotTestSupport.profile()
        let identity = GitHubCopilotTestSupport.identity()
        let account = GitHubCopilotTestSupport.account(profile: profile, identity: identity)
        let reader = GitHubCopilotStubReader(results: [
            "personal": .success(GitHubCopilotTestSupport.result(
                identity: identity,
                metrics: [],
                isOrganizationManaged: true,
            )),
        ])
        let adapter = GitHubCopilotProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: Date.init,
        )

        let result = try await adapter.refresh(account)

        #expect(result.snapshots.isEmpty)
    }

    @Test
    func `uses conservative polling and backoff intervals`() {
        let adapter = GitHubCopilotProviderAdapter(
            profiles: [],
            reader: GitHubCopilotStubReader(results: [:]),
            now: { GitHubCopilotTestSupport.observedAt },
        )

        #expect(adapter.interval(after: .rateLimited(retryAt: nil)) == .seconds(1800))
        #expect(adapter.interval(after: .rateLimited(
            retryAt: GitHubCopilotTestSupport.observedAt.addingTimeInterval(1200),
        )) == .seconds(1200))
        #expect(adapter.interval(after: .signedOut) == .seconds(3600))
        #expect(adapter.interval(after: .identityMismatch) == .seconds(3600))
        #expect(adapter.interval(after: .failed(code: "test")) == .seconds(1800))
    }
}

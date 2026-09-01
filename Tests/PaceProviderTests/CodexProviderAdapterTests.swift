import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Codex provider adapter")
struct CodexProviderAdapterTests {
    private let observedAt = Date(timeIntervalSince1970: 1_788_134_400)

    @Test
    func `discovers isolated profiles and preserves their bindings`() async throws {
        let personal = profile("personal", displayName: "Personal")
        let work = profile("work", displayName: "Work")
        let reader = CodexStubReader(results: [
            personal.directory.path: .success(profileSnapshot(email: "person@example.invalid")),
            work.directory.path: .success(profileSnapshot(email: "work@example.invalid")),
        ])
        let adapter = CodexProviderAdapter(
            profiles: [personal, work],
            reader: reader,
            now: { observedAt },
        )

        let accounts = try await adapter.discoverAccounts()

        #expect(accounts.map(\.identity.subjectID) == [
            "chatgpt:person@example.invalid",
            "chatgpt:work@example.invalid",
        ])
        #expect(accounts.map(\.suggestedDisplayName) == ["Personal", "Work"])
        #expect(accounts.map(\.planName) == ["ChatGPT Plus", "ChatGPT Plus"])
        #expect(accounts.map(\.credentialBinding) == [
            .providerProfile(directory: personal.directory, ownership: .existing),
            .providerProfile(directory: work.directory, ownership: .paceManaged),
        ])
    }

    @Test
    func `refresh verifies identity and owns snapshots with the selected account`() async throws {
        let profile = profile("personal", displayName: "Personal")
        let reader = CodexStubReader(results: [
            profile.directory.path: .success(
                profileSnapshot(email: "person@example.invalid", includesUsage: true),
            ),
        ])
        let adapter = CodexProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { observedAt },
        )
        let accountID = accountID("20000000-0000-0000-0000-000000000001")
        let account = providerAccount(
            id: accountID,
            profile: profile,
            email: "person@example.invalid",
        )

        let result = try await adapter.refresh(account)

        #expect(result.identity == account.identity)
        #expect(result.planName == "ChatGPT Plus")
        #expect(result.verifiedAt == observedAt)
        #expect(result.snapshots.map(\.id.accountID) == [accountID])
        #expect(result.snapshots.map(\.usedFraction) == [0.21])
    }

    @Test
    func `contains a signed-out profile without hiding another discovered account`() async throws {
        let signedOut = profile("signed-out", displayName: "Signed out")
        let personal = profile("personal", displayName: "Personal")
        let reader = CodexStubReader(results: [
            signedOut.directory.path: .failure(.signedOut),
            personal.directory.path: .success(profileSnapshot(email: "person@example.invalid")),
        ])
        let adapter = CodexProviderAdapter(
            profiles: [signedOut, personal],
            reader: reader,
            now: { observedAt },
        )

        let accounts = try await adapter.discoverAccounts()

        #expect(accounts.map(\.suggestedDisplayName) == ["Personal"])
    }

    @Test
    func `rejects duplicate remote identity across two profile directories`() async {
        let first = profile("first", displayName: "First")
        let second = profile("second", displayName: "Second")
        let reader = CodexStubReader(results: [
            first.directory.path: .success(profileSnapshot(email: "same@example.invalid")),
            second.directory.path: .success(profileSnapshot(email: "same@example.invalid")),
        ])
        let adapter = CodexProviderAdapter(
            profiles: [first, second],
            reader: reader,
            now: { observedAt },
        )

        await #expect(throws: ProviderFailure.self) {
            _ = try await adapter.discoverAccounts()
        }
    }

    private func profile(_ name: String, displayName: String) -> CodexProfile {
        CodexProfile(
            directory: URL(filePath: "/profiles/codex/\(name)", directoryHint: .isDirectory),
            ownership: name == "work" ? .paceManaged : .existing,
            displayName: displayName,
        )
    }

    private func profileSnapshot(
        email: String,
        includesUsage: Bool = false,
    ) -> CodexProfileSnapshot {
        CodexProfileSnapshot(
            account: CodexAccountResponse(
                account: CodexAccountPayload(
                    email: email,
                    planType: "plus",
                    type: "chatgpt",
                ),
                requiresOpenaiAuth: true,
            ),
            rateLimits: includesUsage ? rateLimits() : nil,
        )
    }

    private func rateLimits() -> CodexRateLimitsResponse {
        CodexRateLimitsResponse(
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: "Codex",
                planType: "plus",
                primary: CodexRateLimitWindow(
                    resetsAt: 1_788_145_200,
                    usedPercent: 21,
                    windowDurationMins: 10080,
                ),
                secondary: nil,
            ),
            rateLimitsByLimitID: nil,
        )
    }

    private func accountID(_ value: String) -> AccountID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID")
        }
        return AccountID(rawValue: uuid)
    }

    private func providerAccount(
        id: AccountID,
        profile: CodexProfile,
        email: String,
    ) -> ProviderAccount {
        ProviderAccount(
            id: id,
            providerID: .codex,
            identity: ProviderIdentity(
                subjectID: "chatgpt:\(email)",
                email: email,
            ),
            credentialBinding: .providerProfile(
                directory: profile.directory,
                ownership: profile.ownership,
            ),
            addedAt: observedAt,
            displayName: "Personal",
            planName: "ChatGPT Plus",
            isEnabled: true,
            order: 0,
            connectionState: .connected(lastVerifiedAt: observedAt),
        )
    }
}

private actor CodexStubReader: CodexProfileReading {
    let results: [String: Result<CodexProfileSnapshot, CodexProviderError>]

    init(results: [String: Result<CodexProfileSnapshot, CodexProviderError>]) {
        self.results = results
    }

    func read(
        profile: CodexProfile,
        includeRateLimits _: Bool,
    ) throws(CodexProviderError) -> CodexProfileSnapshot {
        guard let result = results[profile.directory.path] else {
            throw .invalidResponse
        }
        return try result.get()
    }
}

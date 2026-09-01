import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Claude provider adapter")
struct ClaudeProviderAdapterTests {
    @Test
    func `discovers two isolated profiles and preserves bindings`() async throws {
        let personal = ClaudeTestSupport.profile("personal")
        let work = ClaudeTestSupport.profile("work")
        let reader = ClaudeStubReader(results: [
            personal.directory.path: .success(ClaudeTestSupport.result()),
            work.directory.path: .success(ClaudeTestSupport.result(
                identity: ClaudeTestSupport.identity(
                    accountID: "account-b",
                    organizationID: "organization-b",
                ),
            )),
        ])
        let adapter = ClaudeProviderAdapter(
            profiles: [personal, work],
            reader: reader,
            now: { ClaudeTestSupport.observedAt },
        )

        let accounts = try await adapter.discoverAccounts()

        #expect(accounts.map(\.suggestedDisplayName) == ["Personal", "Work"])
        #expect(accounts.map(\.credentialBinding) == [
            personal.credentialBinding,
            work.credentialBinding,
        ])
        #expect(Set(accounts.map(\.identity.subjectID)).count == 2)
    }

    @Test
    func `refresh binds expected identity and owns every snapshot`() async throws {
        let profile = ClaudeTestSupport.profile()
        let identity = ClaudeTestSupport.identity()
        let reader = ClaudeStubReader(results: [
            profile.directory.path: .success(ClaudeTestSupport.result(identity: identity)),
        ])
        let adapter = ClaudeProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { ClaudeTestSupport.observedAt },
        )
        let account = ProviderAccount(
            id: AccountID(),
            providerID: .claude,
            identity: identity.providerIdentity,
            credentialBinding: .providerProfile(
                directory: profile.directory,
                ownership: .existing,
            ),
            addedAt: ClaudeTestSupport.observedAt,
            displayName: "Personal",
            planName: nil,
            isEnabled: true,
            order: 0,
            connectionState: .needsAuthentication,
        )

        let result = try await adapter.refresh(account)
        let reads = await reader.reads

        #expect(result.identity == account.identity)
        #expect(result.planName == "Max 20x")
        #expect(result.snapshots.map(\.id.accountID) == [account.id, account.id])
        #expect(result.snapshots.map(\.usedFraction) == [0.42, 0.2])
        #expect(reads.last?.profile.expectedIdentity == account.identity)
        #expect(reads.last?.includeUsage == true)
    }

    @Test
    func `valid response with no quota buckets stays observable`() throws {
        let snapshots = try ClaudeRateLimitNormalizer.normalize(
            ClaudeTestSupport.result(metrics: []),
            accountID: AccountID(),
        )

        #expect(snapshots.isEmpty)
    }

    @Test
    func `normalizes dynamic percentage and amount buckets end to end`() throws {
        let accountID = AccountID()
        let snapshots = try ClaudeRateLimitNormalizer.normalize(
            ClaudeTestSupport.result(metrics: [
                .percentage(ClaudePercentageMetric(
                    id: "weekly-sonnet",
                    label: "Sonnet weekly",
                    usedFraction: 0.35,
                    windowDuration: 604_800,
                    resetsAt: ClaudeTestSupport.observedAt.addingTimeInterval(604_800),
                )),
                .amount(ClaudeAmountMetric(
                    id: "extra-usage",
                    label: "Extra usage",
                    used: 25,
                    limit: 100,
                    unit: "USD",
                )),
            ]),
            accountID: accountID,
        )

        #expect(snapshots.map(\.id.bucketID.rawValue) == ["weekly-sonnet", "extra-usage"])
        #expect(snapshots.map(\.usedFraction) == [0.35, 0.25])
        #expect(snapshots.allSatisfy { $0.id.accountID == accountID })
    }

    @Test
    func `contains one signed out profile without hiding another`() async throws {
        let signedOut = ClaudeTestSupport.profile("signed-out")
        let personal = ClaudeTestSupport.profile("personal")
        let reader = ClaudeStubReader(results: [
            signedOut.directory.path: .failure(.signedOut),
            personal.directory.path: .success(ClaudeTestSupport.result()),
        ])
        let adapter = ClaudeProviderAdapter(
            profiles: [signedOut, personal],
            reader: reader,
            now: Date.init,
        )

        let accounts = try await adapter.discoverAccounts()

        #expect(accounts.map(\.suggestedDisplayName) == ["Personal"])
    }

    @Test
    func `rejects duplicate identity across explicit profiles`() async {
        let first = ClaudeTestSupport.profile("first")
        let second = ClaudeTestSupport.profile("second")
        let reader = ClaudeStubReader(results: [
            first.directory.path: .success(ClaudeTestSupport.result()),
            second.directory.path: .success(ClaudeTestSupport.result()),
        ])
        let adapter = ClaudeProviderAdapter(
            profiles: [first, second],
            reader: reader,
            now: Date.init,
        )

        await #expect(throws: ProviderFailure.self) {
            _ = try await adapter.discoverAccounts()
        }
    }

    @Test
    func `uses conservative polling and backoff intervals`() async throws {
        let cases: [(ClaudeProviderError, Duration)] = [
            (.rateLimited(retryAfter: 45), .seconds(900)),
            (.rateLimited(retryAfter: 1200), .seconds(1200)),
            (.signedOut, .seconds(3600)),
            (.identityMismatch, .seconds(3600)),
            (.transportFailed, .seconds(1800)),
        ]

        for (failure, interval) in cases {
            try await assertNextPollingInterval(after: failure, equals: interval)
        }
    }

    private func assertNextPollingInterval(
        after error: ClaudeProviderError,
        equals expected: Duration,
    ) async throws {
        let profile = ClaudeTestSupport.profile()
        let reader = ClaudeStubReader(results: [profile.directory.path: .failure(error)])
        let sleeper = ClaudeTestPollSleeper()
        let adapter = ClaudeProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { ClaudeTestSupport.observedAt },
            pollInterval: .seconds(900),
            sleep: { duration in try await sleeper.sleep(for: duration) },
        )
        let account = ProviderAccount(
            id: AccountID(),
            providerID: .claude,
            identity: ClaudeTestSupport.identity().providerIdentity,
            credentialBinding: .providerProfile(
                directory: profile.directory,
                ownership: .existing,
            ),
            addedAt: ClaudeTestSupport.observedAt,
            displayName: "Personal",
            planName: nil,
            isEnabled: true,
            order: 0,
            connectionState: .needsAuthentication,
        )
        let updates = await adapter.updates(for: account)
        let recorder = ClaudePollingUpdateRecorder()
        let consumer = Task<Void, Never> {
            for await update in updates {
                await recorder.record(update)
            }
        }

        try await waitUntil { await sleeper.requestedIntervals.count == 1 }
        await sleeper.resume()
        try await waitUntil { await recorder.first != nil }
        try await waitUntil { await sleeper.requestedIntervals.count == 2 }
        #expect(await sleeper.requestedIntervals == [.seconds(900), expected])
        consumer.cancel()
        await consumer.value
    }
}

private actor ClaudePollingUpdateRecorder {
    private(set) var first: ProviderUpdate?

    func record(_ update: ProviderUpdate) {
        first = first ?? update
    }
}

private actor ClaudeTestPollSleeper {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var requestedIntervals: [Duration] = []

    func sleep(for duration: Duration) async throws {
        requestedIntervals.append(duration)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func resume() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }

    private func cancel() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(throwing: CancellationError())
    }
}

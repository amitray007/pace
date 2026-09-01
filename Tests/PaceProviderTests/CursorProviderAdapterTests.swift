import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Cursor provider adapter")
struct CursorProviderAdapterTests {
    @Test
    func `discovers isolated profiles and preserves their bindings`() async throws {
        let personal = CursorTestSupport.profile("personal", source: .defaultKeychain)
        let work = CursorTestSupport.profile("work")
        let reader = CursorStubReader(results: [
            personal.homeDirectory.path: .success(CursorTestSupport.result()),
            work.homeDirectory.path: .success(CursorTestSupport.result(
                identity: CursorTestSupport.identity(userID: "user-b", teamID: "team-b"),
            )),
        ])
        let adapter = CursorProviderAdapter(
            profiles: [personal, work],
            reader: reader,
            now: { CursorTestSupport.observedAt },
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
    func `contains one signed out profile without hiding another`() async throws {
        let signedOut = CursorTestSupport.profile("signed-out")
        let personal = CursorTestSupport.profile("personal")
        let reader = CursorStubReader(results: [
            signedOut.homeDirectory.path: .failure(.signedOut),
            personal.homeDirectory.path: .success(CursorTestSupport.result()),
        ])
        let adapter = CursorProviderAdapter(
            profiles: [signedOut, personal],
            reader: reader,
            now: Date.init,
        )

        let accounts = try await adapter.discoverAccounts()

        #expect(accounts.map(\.suggestedDisplayName) == ["Personal"])
    }

    @Test
    func `refresh binds expected identity and owns every snapshot`() async throws {
        let profile = CursorTestSupport.profile()
        let identity = CursorTestSupport.identity()
        let reader = CursorStubReader(results: [
            profile.homeDirectory.path: .success(CursorTestSupport.result(identity: identity)),
        ])
        let adapter = CursorProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { CursorTestSupport.observedAt },
        )
        let account = account(profile: profile, identity: identity.providerIdentity)

        let result = try await adapter.refresh(account)
        let reads = await reader.reads

        #expect(result.identity == account.identity)
        #expect(result.planName == "Team")
        #expect(result.snapshots.map(\.id.accountID) == [account.id, account.id])
        #expect(result.snapshots.map(\.usedFraction) == [0.42, 0.2])
        #expect(reads.last?.profile.expectedIdentity == account.identity)
        #expect(reads.last?.includeUsage == true)
    }

    @Test
    func `normalizes dynamic percentage amount and empty buckets`() throws {
        let accountID = AccountID()
        let result = CursorTestSupport.result(metrics: [
            .percentage(CursorPercentageMetric(
                id: "included",
                label: "Included usage",
                usedFraction: 0.35,
                resetsAt: CursorTestSupport.observedAt.addingTimeInterval(604_800),
                windowDuration: 604_800,
            )),
            .amount(CursorAmountMetric(
                id: "extra",
                label: "Extra usage",
                used: 25,
                limit: 100,
                unit: "USD",
                resetsAt: nil,
            )),
        ])

        let snapshots = try CursorRateLimitNormalizer.normalize(result, accountID: accountID)
        let empty = try CursorRateLimitNormalizer.normalize(
            CursorTestSupport.result(metrics: []),
            accountID: accountID,
        )

        #expect(snapshots.map(\.id.bucketID.rawValue) == ["included", "extra"])
        #expect(snapshots.map(\.usedFraction) == [0.35, 0.25])
        #expect(snapshots.allSatisfy { $0.id.accountID == accountID })
        #expect(empty.isEmpty)
    }

    @Test
    func `uses conservative polling and provider backoff`() async throws {
        let cases: [(CursorProviderError, Duration)] = [
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
        after error: CursorProviderError,
        equals expected: Duration,
    ) async throws {
        let profile = CursorTestSupport.profile()
        let reader = CursorStubReader(results: [profile.homeDirectory.path: .failure(error)])
        let sleeper = CursorTestPollSleeper()
        let adapter = CursorProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { CursorTestSupport.observedAt },
            pollInterval: .seconds(900),
            sleep: { duration in try await sleeper.sleep(for: duration) },
        )
        let updates = await adapter.updates(
            for: account(profile: profile, identity: CursorTestSupport.identity().providerIdentity),
        )
        let recorder = CursorPollingUpdateRecorder()
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

    private func account(
        profile: CursorProfile,
        identity: ProviderIdentity,
    ) -> ProviderAccount {
        ProviderAccount(
            id: AccountID(),
            providerID: .cursor,
            identity: identity,
            credentialBinding: profile.credentialBinding,
            addedAt: CursorTestSupport.observedAt,
            displayName: "Personal",
            planName: nil,
            isEnabled: true,
            order: 0,
            connectionState: .needsAuthentication,
        )
    }
}

private actor CursorPollingUpdateRecorder {
    private(set) var first: ProviderUpdate?

    func record(_ update: ProviderUpdate) {
        first = first ?? update
    }
}

private actor CursorTestPollSleeper {
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

import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Grok provider adapter")
struct GrokProviderAdapterTests {
    @Test
    func `discovers two isolated profiles and preserves bindings`() async throws {
        let personal = GrokTestSupport.profile("personal")
        let work = GrokTestSupport.profile("work")
        let reader = GrokStubReader(results: [
            personal.directory.path: .success(GrokTestSupport.result()),
            work.directory.path: .success(GrokTestSupport.result(
                identity: GrokTestSupport.identity(userID: "user-b", principalID: "principal-b"),
            )),
        ])
        let adapter = GrokProviderAdapter(
            profiles: [personal, work],
            reader: reader,
            now: { GrokTestSupport.observedAt },
        )

        let accounts = try await adapter.discoverAccounts()

        #expect(accounts.map(\.suggestedDisplayName) == ["Personal", "Work"])
        #expect(accounts.map(\.credentialBinding) == [
            .providerProfile(directory: personal.directory, ownership: .existing),
            .providerProfile(directory: work.directory, ownership: .paceManaged),
        ])
        #expect(Set(accounts.map(\.identity.subjectID)).count == 2)
    }

    @Test
    func `refresh verifies the registered identity and owns every snapshot`() async throws {
        let profile = GrokTestSupport.profile()
        let identity = GrokTestSupport.identity()
        let reader = GrokStubReader(results: [
            profile.directory.path: .success(GrokTestSupport.result(identity: identity)),
        ])
        let adapter = GrokProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { GrokTestSupport.observedAt },
        )
        let accountID = try AccountID(
            rawValue: #require(UUID(uuidString: "30000000-0000-0000-0000-000000000001")),
        )
        let account = ProviderAccount(
            id: accountID,
            providerID: .grok,
            identity: identity.providerIdentity,
            credentialBinding: .providerProfile(
                directory: profile.directory,
                ownership: .existing,
            ),
            addedAt: GrokTestSupport.observedAt,
            displayName: "Personal",
            planName: nil,
            isEnabled: true,
            order: 0,
            connectionState: .needsAuthentication,
        )

        let result = try await adapter.refresh(account)
        let reads = await reader.reads

        #expect(result.identity == account.identity)
        #expect(result.planName == "SuperGrok")
        #expect(result.snapshots.map(\.id.accountID) == [accountID, accountID])
        #expect(result.snapshots.map(\.usedFraction) == [0.42, 0.2])
        #expect(reads.last?.profile.expectedIdentity == account.identity)
        #expect(reads.last?.includeUsage == true)
    }

    @Test
    func `contains one signed out profile without hiding another`() async throws {
        let signedOut = GrokTestSupport.profile("signed-out")
        let personal = GrokTestSupport.profile("personal")
        let reader = GrokStubReader(results: [
            signedOut.directory.path: .failure(.signedOut),
            personal.directory.path: .success(GrokTestSupport.result()),
        ])
        let adapter = GrokProviderAdapter(
            profiles: [signedOut, personal],
            reader: reader,
            now: Date.init,
        )

        let accounts = try await adapter.discoverAccounts()

        #expect(accounts.map(\.suggestedDisplayName) == ["Personal"])
    }

    @Test
    func `maps provider retry interval to an absolute retry date`() async throws {
        let profile = GrokTestSupport.profile()
        let reader = GrokStubReader(results: [
            profile.directory.path: .failure(.rateLimited(retryAfter: 45)),
        ])
        let adapter = GrokProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { GrokTestSupport.observedAt },
        )
        let account = ProviderAccount(
            id: AccountID(),
            providerID: .grok,
            identity: GrokTestSupport.identity().providerIdentity,
            credentialBinding: .providerProfile(
                directory: profile.directory,
                ownership: .existing,
            ),
            addedAt: GrokTestSupport.observedAt,
            displayName: "Personal",
            planName: nil,
            isEnabled: true,
            order: 0,
            connectionState: .needsAuthentication,
        )

        await #expect(throws: ProviderFailure.rateLimited(
            retryAt: GrokTestSupport.observedAt.addingTimeInterval(45),
        )) {
            try await adapter.refresh(account)
        }
    }

    @Test
    func `rejects duplicate remote identity across two directories`() async {
        let first = GrokTestSupport.profile("first")
        let second = GrokTestSupport.profile("second")
        let reader = GrokStubReader(results: [
            first.directory.path: .success(GrokTestSupport.result()),
            second.directory.path: .success(GrokTestSupport.result()),
        ])
        let adapter = GrokProviderAdapter(
            profiles: [first, second],
            reader: reader,
            now: Date.init,
        )

        await #expect(throws: ProviderFailure.self) {
            _ = try await adapter.discoverAccounts()
        }
    }

    @Test
    func `polls conservatively and stops with the stream consumer`() async throws {
        let profile = GrokTestSupport.profile()
        let identity = GrokTestSupport.identity()
        let reader = GrokStubReader(results: [
            profile.directory.path: .success(GrokTestSupport.result(identity: identity)),
        ])
        let sleeper = GrokTestPollSleeper()
        let adapter = GrokProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { GrokTestSupport.observedAt },
            pollInterval: .seconds(900),
            sleep: { duration in try await sleeper.sleep(for: duration) },
        )
        let account = ProviderAccount(
            id: AccountID(),
            providerID: .grok,
            identity: identity.providerIdentity,
            credentialBinding: .providerProfile(
                directory: profile.directory,
                ownership: .existing,
            ),
            addedAt: GrokTestSupport.observedAt,
            displayName: "Personal",
            planName: nil,
            isEnabled: true,
            order: 0,
            connectionState: .needsAuthentication,
        )
        let updates = await adapter.updates(for: account)
        let recorder = GrokPollingUpdateRecorder()
        let consumer = Task<Void, Never> {
            for await update in updates {
                await recorder.record(update)
            }
        }

        try await waitUntil { await sleeper.isWaiting }
        #expect(await sleeper.requestedInterval == .seconds(900))
        await sleeper.resume()
        try await waitUntil { await recorder.first != nil }
        guard case let .refresh(result) = await recorder.first else {
            Issue.record("Expected a normalized polling refresh")
            return
        }
        #expect(result.identity == account.identity)
        consumer.cancel()
        await consumer.value
        try await waitUntil { await sleeper.wasCancelled }
    }

    @Test
    func `backs off polling according to provider failure`() async throws {
        let cases: [(GrokProviderError, Duration)] = [
            (.rateLimited(retryAfter: 45), .seconds(900)),
            (.rateLimited(retryAfter: 1200), .seconds(1200)),
            (.signedOut, .seconds(3600)),
            (.identityMismatch, .seconds(3600)),
            (.transportFailed, .seconds(1800)),
        ]

        for (failure, expectedInterval) in cases {
            try await assertNextPollingInterval(
                after: failure,
                equals: expectedInterval,
            )
        }
    }

    @Test
    func `normalizes team quota subject`() async throws {
        let profile = GrokTestSupport.profile()
        let identity = GrokTestSupport.identity(teamID: "team-a")
        let reader = GrokStubReader(results: [
            profile.directory.path: .success(GrokTestSupport.result(identity: identity)),
        ])
        let adapter = GrokProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { GrokTestSupport.observedAt },
        )
        let account = ProviderAccount(
            id: AccountID(),
            providerID: .grok,
            identity: identity.providerIdentity,
            credentialBinding: .providerProfile(
                directory: profile.directory,
                ownership: .existing,
            ),
            addedAt: GrokTestSupport.observedAt,
            displayName: "Team",
            planName: nil,
            isEnabled: true,
            order: 0,
            connectionState: .needsAuthentication,
        )

        let result = try await adapter.refresh(account)

        #expect(result.snapshots.allSatisfy {
            $0.quotaSubject?.id == QuotaSubjectID(rawValue: "grok-team:team-a")
        })
        #expect(result.snapshots.allSatisfy { $0.quotaSubject?.kind == .team })
    }

    private func assertNextPollingInterval(
        after failure: GrokProviderError,
        equals expectedInterval: Duration,
    ) async throws {
        let profile = GrokTestSupport.profile()
        let identity = GrokTestSupport.identity()
        let reader = GrokStubReader(results: [profile.directory.path: .failure(failure)])
        let sleeper = GrokTestPollSleeper()
        let adapter = GrokProviderAdapter(
            profiles: [profile],
            reader: reader,
            now: { GrokTestSupport.observedAt },
            pollInterval: .seconds(900),
            sleep: { duration in try await sleeper.sleep(for: duration) },
        )
        let account = ProviderAccount(
            id: AccountID(),
            providerID: .grok,
            identity: identity.providerIdentity,
            credentialBinding: .providerProfile(
                directory: profile.directory,
                ownership: .existing,
            ),
            addedAt: GrokTestSupport.observedAt,
            displayName: "Personal",
            planName: nil,
            isEnabled: true,
            order: 0,
            connectionState: .needsAuthentication,
        )
        let updates = await adapter.updates(for: account)
        let recorder = GrokPollingUpdateRecorder()
        let consumer = Task<Void, Never> {
            for await update in updates {
                await recorder.record(update)
            }
        }

        try await waitUntil { await sleeper.requestedIntervals.count == 1 }
        await sleeper.resume()
        try await waitUntil { await recorder.first != nil }
        try await waitUntil { await sleeper.requestedIntervals.count == 2 }

        #expect(await sleeper.requestedIntervals == [.seconds(900), expectedInterval])
        consumer.cancel()
        await consumer.value
        try await waitUntil { await sleeper.wasCancelled }
    }
}

private actor GrokPollingUpdateRecorder {
    private(set) var first: ProviderUpdate?

    func record(_ update: ProviderUpdate) {
        first = first ?? update
    }
}

private actor GrokTestPollSleeper {
    private var continuation: CheckedContinuation<Void, any Error>?
    private(set) var requestedIntervals: [Duration] = []
    private(set) var wasCancelled = false

    var requestedInterval: Duration? {
        requestedIntervals.last
    }

    var isWaiting: Bool {
        continuation != nil
    }

    func sleep(for duration: Duration) async throws {
        requestedIntervals.append(duration)
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                }
            } onCancel: {
                Task { await self.cancel() }
            }
        } catch {
            throw error
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }

    private func cancel() {
        wasCancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

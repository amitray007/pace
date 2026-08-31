import Foundation

public struct SimulatedAccountFixture: Sendable {
    public let id: AccountID
    public let account: DiscoveredAccount
    public let displayName: String

    public init(id: AccountID, account: DiscoveredAccount, displayName: String) {
        self.id = id
        self.account = account
        self.displayName = displayName
    }
}

public struct SimulatedScenario: Sendable {
    public let accounts: [SimulatedAccountFixture]
    public let adapters: [any ProviderAdapter]
    public let referenceDate: Date

    public init(
        accounts: [SimulatedAccountFixture],
        adapters: [any ProviderAdapter],
        referenceDate: Date,
    ) {
        self.accounts = accounts
        self.adapters = adapters
        self.referenceDate = referenceDate
    }

    public func seed(_ store: PaceStore) async throws {
        for fixture in accounts {
            try await store.register(
                fixture.account,
                displayName: fixture.displayName,
                id: fixture.id,
                addedAt: referenceDate,
            )
        }
    }
}

public enum SimulatedScenarios {
    public static let referenceDate = Date(timeIntervalSince1970: 1_788_134_400)

    public static func standard() throws -> SimulatedScenario {
        let fixtures = standardAccounts()
        let fixturesByProvider = Dictionary(grouping: fixtures, by: { $0.account.providerID })
        let adapters: [any ProviderAdapter] = try fixturesByProvider.map { providerID, accounts in
            let steps = try Dictionary(uniqueKeysWithValues: accounts.map { fixture in
                try (
                    fixture.id,
                    [
                        SimulatedRefreshStep.result(
                            refreshResult(for: fixture, observedAt: referenceDate),
                        ),
                    ],
                )
            })
            return SimulatedProviderAdapter(
                providerID: providerID,
                discoveredAccounts: accounts.map(\.account),
                refreshSteps: steps,
            )
        }

        return SimulatedScenario(
            accounts: fixtures,
            adapters: adapters,
            referenceDate: referenceDate,
        )
    }

    // A flat fixture list makes the planned provider matrix easy to review.
    // swiftlint:disable:next function_body_length
    private static func standardAccounts() -> [SimulatedAccountFixture] {
        [
            fixture(
                id: "00000000-0000-0000-0000-000000000001",
                providerID: .claude,
                identity: ProviderIdentity(
                    subjectID: "claude-personal",
                    email: "personal@example.invalid",
                ),
                displayName: "Personal",
                planName: "Claude Pro",
            ),
            fixture(
                id: "00000000-0000-0000-0000-000000000002",
                providerID: .claude,
                identity: ProviderIdentity(
                    subjectID: "claude-work",
                    email: "work@example.invalid",
                ),
                displayName: "Work",
                planName: "Claude Team",
            ),
            fixture(
                id: "00000000-0000-0000-0000-000000000003",
                providerID: .codex,
                identity: ProviderIdentity(
                    subjectID: "codex-personal",
                    email: "personal@example.invalid",
                ),
                displayName: "Personal",
                planName: "ChatGPT Plus",
            ),
            fixture(
                id: "00000000-0000-0000-0000-000000000004",
                providerID: .cursor,
                identity: ProviderIdentity(
                    subjectID: "cursor-work",
                    email: "work@example.invalid",
                ),
                displayName: "Work",
                planName: "Cursor Pro",
            ),
            fixture(
                id: "00000000-0000-0000-0000-000000000005",
                providerID: .grok,
                identity: ProviderIdentity(
                    subjectID: "grok-personal",
                    email: "personal@example.invalid",
                ),
                displayName: "Personal",
                planName: "SuperGrok",
            ),
            fixture(
                id: "00000000-0000-0000-0000-000000000006",
                providerID: .githubCopilot,
                identity: ProviderIdentity(
                    subjectID: "github-personal",
                    email: "personal@example.invalid",
                ),
                displayName: "Personal",
                planName: "Copilot Pro",
            ),
        ]
    }

    private static func fixture(
        id: String,
        providerID: ProviderID,
        identity: ProviderIdentity,
        displayName: String,
        planName: String,
    ) -> SimulatedAccountFixture {
        guard let uuid = UUID(uuidString: id) else {
            preconditionFailure("Invalid simulated account UUID: \(id)")
        }
        let accountID = AccountID(rawValue: uuid)
        let account = DiscoveredAccount(
            providerID: providerID,
            identity: identity,
            suggestedDisplayName: displayName,
            planName: planName,
            credentialBinding: .simulated,
        )
        return SimulatedAccountFixture(
            id: accountID,
            account: account,
            displayName: displayName,
        )
    }

    private static func refreshResult(
        for fixture: SimulatedAccountFixture,
        observedAt: Date,
    ) throws -> ProviderRefreshResult {
        let providerID = fixture.account.providerID
        let sessionUsage = usage(for: providerID, accountID: fixture.id, offset: 0)
        let weeklyUsage = usage(for: providerID, accountID: fixture.id, offset: 0.19)
        let snapshots = try [
            LimitSnapshot(
                providerID: providerID,
                accountID: fixture.id,
                bucketID: BucketID(rawValue: "session"),
                label: "Session",
                usedFraction: sessionUsage,
                windowDuration: 5 * 60 * 60,
                resetsAt: observedAt.addingTimeInterval(2 * 60 * 60),
                observedAt: observedAt,
                freshness: .current,
            ),
            LimitSnapshot(
                providerID: providerID,
                accountID: fixture.id,
                bucketID: BucketID(rawValue: "weekly"),
                label: "Weekly",
                usedFraction: weeklyUsage,
                windowDuration: 7 * 24 * 60 * 60,
                resetsAt: observedAt.addingTimeInterval(3 * 24 * 60 * 60),
                observedAt: observedAt,
                freshness: .current,
            ),
        ]
        return ProviderRefreshResult(
            identity: fixture.account.identity,
            planName: fixture.account.planName,
            snapshots: snapshots,
            verifiedAt: observedAt,
        )
    }

    private static func usage(
        for providerID: ProviderID,
        accountID: AccountID,
        offset: Double,
    ) -> Double {
        let providerSeed = providerID.rawValue.unicodeScalars.reduce(0) {
            $0 + Int($1.value)
        }
        let accountSeed = accountID.rawValue.uuid.15
        let normalizedSeed = Double((providerSeed + Int(accountSeed)) % 60) / 100
        return min(0.95, 0.15 + normalizedSeed + offset)
    }
}

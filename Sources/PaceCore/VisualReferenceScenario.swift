import Foundation

public extension SimulatedScenarios {
    static func visualReference() throws -> SimulatedScenario {
        let fixtures = visualReferenceAccounts()
        let resultsByAccount = try visualReferenceResults(fixtures: fixtures)
        let fixturesByProvider = Dictionary(grouping: fixtures, by: { $0.account.providerID })
        let adapters: [any ProviderAdapter] = try fixturesByProvider.map { providerID, accounts in
            let steps = try Dictionary(uniqueKeysWithValues: accounts.map { fixture in
                guard let result = resultsByAccount[fixture.id] else {
                    throw VisualReferenceScenarioError.missingResult(fixture.id)
                }
                return (fixture.id, [SimulatedRefreshStep.result(result)])
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

    private static func visualReferenceAccounts() -> [SimulatedAccountFixture] {
        [
            visualFixture(
                id: "10000000-0000-0000-0000-000000000001",
                providerID: .claude,
                subjectID: "visual-claude-personal",
                displayName: "Personal",
                planName: "Claude Pro",
            ),
            visualFixture(
                id: "10000000-0000-0000-0000-000000000002",
                providerID: .claude,
                subjectID: "visual-claude-work",
                displayName: "Work",
                planName: "Claude Team",
            ),
            visualFixture(
                id: "10000000-0000-0000-0000-000000000003",
                providerID: .codex,
                subjectID: "visual-codex-personal",
                displayName: "Personal",
                planName: "ChatGPT Plus",
            ),
            visualFixture(
                id: "10000000-0000-0000-0000-000000000004",
                providerID: .cursor,
                subjectID: "visual-cursor-work",
                displayName: "Work",
                planName: "Cursor Pro",
            ),
        ]
    }

    private static func visualFixture(
        id: String,
        providerID: ProviderID,
        subjectID: String,
        displayName: String,
        planName: String,
    ) -> SimulatedAccountFixture {
        guard let uuid = UUID(uuidString: id) else {
            preconditionFailure("Invalid visual fixture UUID: \(id)")
        }
        let account = DiscoveredAccount(
            providerID: providerID,
            identity: ProviderIdentity(
                subjectID: subjectID,
                email: "\(subjectID)@example.invalid",
            ),
            suggestedDisplayName: displayName,
            planName: planName,
            credentialBinding: .simulated,
        )
        return SimulatedAccountFixture(
            id: AccountID(rawValue: uuid),
            account: account,
            displayName: displayName,
        )
    }

    private static func visualReferenceResults(
        fixtures: [SimulatedAccountFixture],
    ) throws -> [AccountID: ProviderRefreshResult] {
        let fixtureBySubject = Dictionary(uniqueKeysWithValues: fixtures.map {
            ($0.account.identity.subjectID, $0)
        })
        let claudePersonal = try visualFixture(
            subjectID: "visual-claude-personal",
            in: fixtureBySubject,
        )
        let claudeWork = try visualFixture(
            subjectID: "visual-claude-work",
            in: fixtureBySubject,
        )
        let codexPersonal = try visualFixture(
            subjectID: "visual-codex-personal",
            in: fixtureBySubject,
        )
        let cursorWork = try visualFixture(
            subjectID: "visual-cursor-work",
            in: fixtureBySubject,
        )
        return try Dictionary(uniqueKeysWithValues: [
            claudePersonalResult(fixture: claudePersonal),
            claudeWorkResult(fixture: claudeWork),
            codexPersonalResult(fixture: codexPersonal),
            cursorWorkResult(fixture: cursorWork),
        ])
    }

    private static func claudePersonalResult(
        fixture: SimulatedAccountFixture,
    ) throws -> (AccountID, ProviderRefreshResult) {
        try visualResult(
            fixture: fixture,
            buckets: [
                VisualQuotaFixture(
                    id: "current-session",
                    label: "Current session",
                    usedFraction: 0.73,
                    duration: 5 * 60 * 60,
                    resetOffset: 2 * 60 * 60,
                ),
                VisualQuotaFixture(
                    id: "all-models",
                    label: "All models",
                    usedFraction: 0.07,
                    duration: 7 * 24 * 60 * 60,
                    resetOffset: 5 * 24 * 60 * 60,
                ),
            ],
        )
    }

    private static func claudeWorkResult(
        fixture: SimulatedAccountFixture,
    ) throws -> (AccountID, ProviderRefreshResult) {
        try visualResult(
            fixture: fixture,
            buckets: [
                VisualQuotaFixture(
                    id: "current-session",
                    label: "Current session",
                    usedFraction: 0.41,
                    duration: 5 * 60 * 60,
                    resetOffset: 3 * 60 * 60,
                ),
                VisualQuotaFixture(
                    id: "all-models",
                    label: "All models",
                    usedFraction: 0.36,
                    duration: 7 * 24 * 60 * 60,
                    resetOffset: 4 * 24 * 60 * 60,
                ),
            ],
        )
    }

    private static func codexPersonalResult(
        fixture: SimulatedAccountFixture,
    ) throws -> (AccountID, ProviderRefreshResult) {
        try visualResult(
            fixture: fixture,
            buckets: [
                VisualQuotaFixture(
                    id: "monthly-limit",
                    label: "Monthly limit",
                    usedFraction: 0.21,
                    duration: 30 * 24 * 60 * 60,
                    resetOffset: 12 * 24 * 60 * 60,
                ),
            ],
        )
    }

    private static func cursorWorkResult(
        fixture: SimulatedAccountFixture,
    ) throws -> (AccountID, ProviderRefreshResult) {
        try visualResult(
            fixture: fixture,
            buckets: [
                VisualQuotaFixture(
                    id: "included-usage",
                    label: "Included usage",
                    usedFraction: 0.52,
                    duration: 30 * 24 * 60 * 60,
                    resetOffset: 9 * 24 * 60 * 60,
                ),
                VisualQuotaFixture(
                    id: "api-usage",
                    label: "API usage",
                    usedFraction: 0.67,
                    duration: 30 * 24 * 60 * 60,
                    resetOffset: 9 * 24 * 60 * 60,
                ),
            ],
        )
    }

    private static func visualFixture(
        subjectID: String,
        in fixtures: [String: SimulatedAccountFixture],
    ) throws -> SimulatedAccountFixture {
        guard let fixture = fixtures[subjectID] else {
            throw VisualReferenceScenarioError.missingFixture(subjectID)
        }
        return fixture
    }

    private static func visualResult(
        fixture: SimulatedAccountFixture,
        buckets: [VisualQuotaFixture],
    ) throws -> (AccountID, ProviderRefreshResult) {
        let snapshots = try buckets.map { bucket in
            try LimitSnapshot(
                providerID: fixture.account.providerID,
                accountID: fixture.id,
                bucketID: BucketID(rawValue: bucket.id),
                label: bucket.label,
                usedFraction: bucket.usedFraction,
                windowDuration: bucket.duration,
                resetsAt: referenceDate.addingTimeInterval(bucket.resetOffset),
                observedAt: referenceDate,
                freshness: .current,
            )
        }
        return (
            fixture.id,
            ProviderRefreshResult(
                identity: fixture.account.identity,
                planName: fixture.account.planName,
                snapshots: snapshots,
                verifiedAt: referenceDate,
            ),
        )
    }
}

private struct VisualQuotaFixture {
    let id: String
    let label: String
    let usedFraction: Double
    let duration: TimeInterval
    let resetOffset: TimeInterval
}

private enum VisualReferenceScenarioError: Error {
    case missingFixture(String)
    case missingResult(AccountID)
}

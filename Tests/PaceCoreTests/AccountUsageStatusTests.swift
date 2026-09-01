import Foundation
@testable import PaceCore
import Testing

@Suite("Account usage status")
struct AccountUsageStatusTests {
    @Test
    func `reports current observations without a connection issue`() throws {
        let account = connectedAccount()
        let snapshot = try TestSupport.snapshot(
            accountID: account.id,
            usedFraction: 0.4,
        )

        let status = AccountUsageStatus(account: account, snapshots: [snapshot])

        #expect(status.dataFreshness == .current)
        #expect(status.connectionIssue == nil)
        #expect(status.observedAt == TestSupport.referenceDate)
        #expect(status.hasData)
    }

    @Test
    func `keeps stale last good data and its refresh failure separate`() throws {
        var account = connectedAccount()
        account.connectionState = .unavailable(code: "maintenance")
        var snapshot = try TestSupport.snapshot(
            accountID: account.id,
            usedFraction: 0.4,
        )
        snapshot.freshness = .stale

        let status = AccountUsageStatus(account: account, snapshots: [snapshot])

        #expect(status.dataFreshness == .stale)
        #expect(status.connectionIssue == .unavailable(code: "maintenance"))
        #expect(status.hasData)
    }

    @Test
    func `reports signed out without inventing usage data`() {
        var account = connectedAccount()
        account.connectionState = .needsAuthentication

        let status = AccountUsageStatus(account: account, snapshots: [])

        #expect(status.dataFreshness == .noData)
        #expect(status.connectionIssue == .needsAuthentication)
        #expect(status.observedAt == nil)
        #expect(!status.hasData)
    }

    private func connectedAccount() -> ProviderAccount {
        ProviderAccount(
            id: TestSupport.personalID,
            providerID: .claude,
            identity: ProviderIdentity(subjectID: "claude-personal"),
            credentialBinding: .simulated,
            addedAt: TestSupport.referenceDate,
            displayName: "Personal",
            planName: "Claude Pro",
            isEnabled: true,
            order: 0,
            connectionState: .connected(lastVerifiedAt: TestSupport.referenceDate),
        )
    }
}

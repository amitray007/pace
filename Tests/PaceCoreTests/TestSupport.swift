import Foundation
@testable import PaceCore

enum TestSupport {
    static let referenceDate = Date(timeIntervalSince1970: 1_788_134_400)
    static let personalID = accountID("10000000-0000-0000-0000-000000000001")
    static let workID = accountID("10000000-0000-0000-0000-000000000002")

    static func accountID(_ value: String) -> AccountID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID: \(value)")
        }
        return AccountID(rawValue: uuid)
    }

    static func discoveredAccount(
        providerID: ProviderID = .claude,
        subjectID: String,
        displayName: String,
        planName: String = "Pro",
        credentialBinding: CredentialBinding = .simulated,
    ) -> DiscoveredAccount {
        DiscoveredAccount(
            providerID: providerID,
            identity: ProviderIdentity(
                subjectID: subjectID,
                email: "\(subjectID)@example.invalid",
            ),
            suggestedDisplayName: displayName,
            planName: planName,
            credentialBinding: credentialBinding,
        )
    }

    static func snapshot(
        providerID: ProviderID = .claude,
        accountID: AccountID,
        bucketID: String = "weekly",
        usedFraction: Double = 0.5,
        freshness: Freshness = .current,
    ) throws -> LimitSnapshot {
        try LimitSnapshot(
            providerID: providerID,
            accountID: accountID,
            bucketID: BucketID(rawValue: bucketID),
            label: bucketID.capitalized,
            usedFraction: usedFraction,
            windowDuration: 7 * 24 * 60 * 60,
            resetsAt: referenceDate.addingTimeInterval(24 * 60 * 60),
            observedAt: referenceDate,
            freshness: freshness,
        )
    }

    static func result(
        for account: DiscoveredAccount,
        accountID _: AccountID,
        snapshots: [LimitSnapshot],
    ) -> ProviderRefreshResult {
        ProviderRefreshResult(
            identity: account.identity,
            planName: account.planName,
            snapshots: snapshots,
            verifiedAt: referenceDate,
        )
    }
}

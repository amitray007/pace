import Foundation
import PaceCore

public struct GrokProviderAdapter: ProviderUpdateStreamingAdapter {
    public nonisolated let providerID = ProviderID.grok
    public nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: true,
    )

    private let profiles: [GrokProfile]
    private let reader: any GrokUsageReading
    private let now: @Sendable () -> Date
    private let pollInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        profiles: [GrokProfile],
        timeout: TimeInterval = 15,
    ) {
        self.profiles = profiles
        reader = GrokUsageReader(timeout: timeout)
        now = Date.init
        pollInterval = .seconds(900)
        sleep = { duration in
            try await Task.sleep(for: duration)
        }
    }

    init(
        profiles: [GrokProfile],
        reader: any GrokUsageReading,
        now: @escaping @Sendable () -> Date,
        pollInterval: Duration = .seconds(900),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
    ) {
        self.profiles = profiles
        self.reader = reader
        self.now = now
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    public func discoverAccounts() async throws(ProviderFailure) -> [DiscoveredAccount] {
        var discoveredAccounts: [DiscoveredAccount] = []
        var firstFailure: ProviderFailure?
        for profile in profiles {
            do {
                let result = try await reader.read(profile: profile, includeUsage: false)
                let identity = result.identity.providerIdentity
                discoveredAccounts.append(DiscoveredAccount(
                    providerID: .grok,
                    identity: identity,
                    suggestedDisplayName: profile.displayName ?? suggestedName(result.identity),
                    planName: result.planName,
                    credentialBinding: .providerProfile(
                        directory: profile.directory,
                        ownership: profile.ownership,
                    ),
                ))
            } catch {
                firstFailure = firstFailure ?? providerFailure(for: error)
            }
        }
        let identities = discoveredAccounts.map(\.identity.subjectID)
        if Set(identities).count != identities.count {
            throw .unavailable(code: "duplicate-grok-identity")
        }
        if discoveredAccounts.isEmpty, let firstFailure {
            throw firstFailure
        }
        return discoveredAccounts
    }

    public func refresh(
        _ account: ProviderAccount,
    ) async throws(ProviderFailure) -> ProviderRefreshResult {
        guard account.providerID == .grok,
              let profile = profile(for: account)
        else {
            throw .unavailable(code: "grok-profile-missing")
        }
        do {
            let result = try await reader.read(profile: profile, includeUsage: true)
            let snapshots = try GrokRateLimitNormalizer.normalize(result, accountID: account.id)
            return ProviderRefreshResult(
                identity: result.identity.providerIdentity,
                planName: result.planName,
                snapshots: snapshots,
                verifiedAt: result.observedAt,
            )
        } catch {
            throw providerFailure(for: error)
        }
    }

    public func updates(for account: ProviderAccount) async -> AsyncStream<ProviderUpdate> {
        guard account.providerID == .grok, profile(for: account) != nil else {
            let pair = AsyncStream<ProviderUpdate>.makeStream()
            pair.continuation.yield(.failure(.unavailable(code: "grok-profile-missing")))
            pair.continuation.finish()
            return pair.stream
        }

        let pair = AsyncStream<ProviderUpdate>.makeStream(
            bufferingPolicy: .bufferingNewest(1),
        )
        let pollingTask = Task { [self] in
            var nextInterval = pollInterval
            while !Task.isCancelled {
                do {
                    try await sleep(nextInterval)
                } catch {
                    break
                }
                guard !Task.isCancelled else {
                    break
                }
                do {
                    try await pair.continuation.yield(.refresh(refresh(account)))
                    nextInterval = pollInterval
                } catch let failure as ProviderFailure {
                    pair.continuation.yield(.failure(failure))
                    nextInterval = interval(after: failure)
                } catch {
                    pair.continuation.yield(.failure(.failed(code: "grok-polling-failed")))
                    nextInterval = .seconds(1800)
                }
            }
            pair.continuation.finish()
        }
        pair.continuation.onTermination = { _ in pollingTask.cancel() }
        return pair.stream
    }

    private func interval(after failure: ProviderFailure) -> Duration {
        switch failure {
        case let .rateLimited(retryAt):
            guard let retryAt else {
                return .seconds(1800)
            }
            return max(pollInterval, .seconds(max(0, retryAt.timeIntervalSince(now()))))
        case .identityMismatch, .signedOut:
            return .seconds(3600)
        case .failed, .unavailable:
            return .seconds(1800)
        }
    }

    private func profile(for account: ProviderAccount) -> GrokProfile? {
        guard case let .providerProfile(directory, _) = account.credentialBinding else {
            return nil
        }
        let canonicalDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        return profiles.first {
            $0.directory.standardizedFileURL.resolvingSymlinksInPath() == canonicalDirectory
        }?.expecting(account.identity)
    }

    private func suggestedName(_ identity: GrokIdentity) -> String {
        identity.email ?? identity.displayName ?? "Grok"
    }

    private func providerFailure(for error: GrokProviderError) -> ProviderFailure {
        switch error {
        case .identityMismatch:
            .identityMismatch
        case let .rateLimited(retryAfter):
            .rateLimited(retryAt: retryAfter.map { now().addingTimeInterval($0) })
        case .reauthenticationRequired, .signedOut:
            .signedOut
        case .credentialReadFailed, .insecureCredentialFile:
            .unavailable(code: "grok-credential-unavailable")
        case .unsupportedCredential:
            .unavailable(code: "grok-credential-unsupported")
        case .ambiguousCredential, .invalidCredential:
            .failed(code: "grok-credential-invalid")
        case .invalidResponse:
            .failed(code: "grok-response-invalid")
        case .requestFailed, .transportFailed:
            .unavailable(code: "grok-service-unavailable")
        }
    }
}

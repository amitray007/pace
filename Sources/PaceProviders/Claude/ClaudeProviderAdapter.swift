import Foundation
import PaceCore

public struct ClaudeProviderAdapter: ProviderUpdateStreamingAdapter {
    public nonisolated let providerID = ProviderID.claude
    public nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: true,
    )

    private let profiles: [ClaudeProfile]
    private let reader: any ClaudeUsageReading
    private let now: @Sendable () -> Date
    private let pollInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(profiles: [ClaudeProfile], timeout: TimeInterval = 15) {
        self.profiles = profiles
        reader = ClaudeUsageReader(timeout: timeout)
        now = Date.init
        pollInterval = .seconds(900)
        sleep = { duration in try await Task.sleep(for: duration) }
    }

    init(
        profiles: [ClaudeProfile],
        reader: any ClaudeUsageReading,
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
        var accounts: [DiscoveredAccount] = []
        var firstFailure: ProviderFailure?
        for profile in profiles {
            do {
                let result = try await reader.read(profile: profile, includeUsage: false)
                accounts.append(DiscoveredAccount(
                    providerID: .claude,
                    identity: result.identity.providerIdentity,
                    suggestedDisplayName: profile.displayName ?? suggestedName(result.identity),
                    planName: result.planName,
                    credentialBinding: profile.credentialBinding,
                ))
            } catch {
                firstFailure = firstFailure ?? providerFailure(for: error)
            }
        }
        let identities = accounts.map(\.identity.subjectID)
        if Set(identities).count != identities.count {
            throw .unavailable(code: "duplicate-claude-identity")
        }
        if accounts.isEmpty, let firstFailure {
            throw firstFailure
        }
        return accounts
    }

    public func refresh(
        _ account: ProviderAccount,
    ) async throws(ProviderFailure) -> ProviderRefreshResult {
        guard account.providerID == .claude, let profile = profile(for: account) else {
            throw .unavailable(code: "claude-profile-missing")
        }
        do {
            let result = try await reader.read(profile: profile, includeUsage: true)
            return try ProviderRefreshResult(
                identity: result.identity.providerIdentity,
                planName: result.planName,
                snapshots: ClaudeRateLimitNormalizer.normalize(result, accountID: account.id),
                verifiedAt: result.observedAt,
            )
        } catch {
            throw providerFailure(for: error)
        }
    }

    public func updates(for account: ProviderAccount) async -> AsyncStream<ProviderUpdate> {
        guard account.providerID == .claude, profile(for: account) != nil else {
            let pair = AsyncStream<ProviderUpdate>.makeStream()
            pair.continuation.yield(.failure(.unavailable(code: "claude-profile-missing")))
            pair.continuation.finish()
            return pair.stream
        }
        let pair = AsyncStream<ProviderUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
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
                    pair.continuation.yield(.failure(.failed(code: "claude-polling-failed")))
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

    private func profile(for account: ProviderAccount) -> ClaudeProfile? {
        profiles.first { profile in
            switch account.credentialBinding {
            case let .claudeProfile(binding):
                profile.directory == binding.configurationDirectory
                    && profile.secureStorageDirectory == binding.secureStorageDirectory
                    && profile.keychainService == binding.keychainService
                    && profile.keychainAccount == binding.keychainAccount
            case let .providerProfile(directory, _):
                profile.directory.standardizedFileURL.resolvingSymlinksInPath()
                    == directory.standardizedFileURL.resolvingSymlinksInPath()
            default:
                false
            }
        }?.expecting(account.identity)
    }

    private func suggestedName(_ identity: ClaudeIdentity) -> String {
        identity.email ?? identity.accountName ?? identity.organizationName ?? "Claude"
    }

    private func providerFailure(for error: ClaudeProviderError) -> ProviderFailure {
        switch error {
        case .identityMismatch:
            .identityMismatch
        case let .rateLimited(retryAfter):
            .rateLimited(retryAt: retryAfter.map { now().addingTimeInterval($0) })
        case .reauthenticationRequired, .signedOut:
            .signedOut
        case .cancelled:
            .unavailable(code: "claude-request-cancelled")
        default:
            providerAvailabilityFailure(for: error)
        }
    }

    private func providerAvailabilityFailure(for error: ClaudeProviderError) -> ProviderFailure {
        switch error {
        case .credentialReadFailed, .credentialWriteFailed, .insecureCredentialFile:
            .unavailable(code: "claude-credential-unavailable")
        case .credentialUnavailable:
            // Every credential source refused to answer without interrupting
            // the user. This is a distinct, actionable state, not a generic
            // failure: the account is fine and signing in again through Claude
            // Code resolves it.
            .unavailable(code: "claude-credential-needs-authorization")
        case .missingProfileScope:
            .unavailable(code: "claude-profile-scope-missing")
        case .credentialChanged:
            .unavailable(code: "claude-credential-changed")
        case .refreshLocked:
            .unavailable(code: "claude-refresh-locked")
        case .invalidCredential:
            .failed(code: "claude-credential-invalid")
        case .invalidProfile:
            .failed(code: "claude-profile-invalid")
        case .invalidResponse:
            .failed(code: "claude-response-invalid")
        case .requestFailed, .transportFailed:
            .unavailable(code: "claude-service-unavailable")
        default:
            .failed(code: "claude-request-failed")
        }
    }
}

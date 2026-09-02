import Foundation
import PaceCore

public struct CursorProviderAdapter: ProviderUpdateStreamingAdapter {
    public nonisolated let providerID = ProviderID.cursor
    public nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: true,
    )

    private let profiles: [CursorProfile]
    private let reader: any CursorUsageReading
    private let now: @Sendable () -> Date
    private let pollInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(profiles: [CursorProfile], timeout: TimeInterval = 15) {
        self.profiles = profiles
        reader = CursorUsageReader(timeout: timeout)
        now = Date.init
        pollInterval = .seconds(900)
        sleep = { duration in try await Task.sleep(for: duration) }
    }

    init(
        profiles: [CursorProfile],
        reader: any CursorUsageReading,
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
                    providerID: .cursor,
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
            throw .unavailable(code: "duplicate-cursor-identity")
        }
        if accounts.isEmpty, let firstFailure {
            throw firstFailure
        }
        return accounts
    }

    public func refresh(
        _ account: ProviderAccount,
    ) async throws(ProviderFailure) -> ProviderRefreshResult {
        guard account.providerID == .cursor, let profile = profile(for: account) else {
            throw .unavailable(code: "cursor-profile-missing")
        }
        do {
            let result = try await reader.read(profile: profile, includeUsage: true)
            return try ProviderRefreshResult(
                identity: result.identity.providerIdentity,
                planName: result.planName,
                snapshots: CursorRateLimitNormalizer.normalize(result, accountID: account.id),
                verifiedAt: result.observedAt,
            )
        } catch {
            throw providerFailure(for: error)
        }
    }

    public func updates(for account: ProviderAccount) async -> AsyncStream<ProviderUpdate> {
        guard account.providerID == .cursor, profile(for: account) != nil else {
            let pair = AsyncStream<ProviderUpdate>.makeStream()
            pair.continuation.yield(.failure(.unavailable(code: "cursor-profile-missing")))
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
                    pair.continuation.yield(.failure(.failed(code: "cursor-polling-failed")))
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

    private func profile(for account: ProviderAccount) -> CursorProfile? {
        profiles.first { profile in
            switch account.credentialBinding {
            case let .cursorProfile(binding):
                profile.homeDirectory
                    == binding.homeDirectory.standardizedFileURL.resolvingSymlinksInPath()
                    && profile.credentialSource == binding.credentialSource
            case let .providerProfile(directory, _):
                profile.homeDirectory
                    == directory.standardizedFileURL.resolvingSymlinksInPath()
            default:
                false
            }
        }?.expecting(account.identity)
    }

    private func suggestedName(_ identity: CursorIdentity) -> String {
        identity.email ?? identity.displayName ?? "Cursor"
    }

    private func providerFailure(for error: CursorProviderError) -> ProviderFailure {
        switch error {
        case .identityMismatch:
            .identityMismatch
        case let .rateLimited(retryAfter):
            .rateLimited(retryAt: retryAfter.map { now().addingTimeInterval($0) })
        case .reauthenticationRequired, .signedOut:
            .signedOut
        case .cancelled:
            .unavailable(code: "cursor-request-cancelled")
        default:
            providerAvailabilityFailure(for: error)
        }
    }

    private func providerAvailabilityFailure(for error: CursorProviderError) -> ProviderFailure {
        switch error {
        case .credentialChanged:
            .unavailable(code: "cursor-credential-changed")
        case .credentialAccessDenied:
            // Listed in `KeychainInteractionPolicy.authorizationRequiredCodes`:
            // the account is fine, macOS just has not admitted Pace yet.
            .unavailable(code: "cursor-credential-needs-authorization")
        case .credentialReadFailed, .insecureCredentialFile:
            .unavailable(code: "cursor-credential-unavailable")
        case .invalidCredential:
            .failed(code: "cursor-credential-invalid")
        case .invalidProfile:
            .failed(code: "cursor-profile-invalid")
        case .invalidResponse:
            .failed(code: "cursor-response-invalid")
        case .requestFailed, .transportFailed:
            .unavailable(code: "cursor-service-unavailable")
        default:
            .failed(code: "cursor-request-failed")
        }
    }
}

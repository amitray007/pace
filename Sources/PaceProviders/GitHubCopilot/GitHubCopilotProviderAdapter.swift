import Foundation
import PaceCore

public struct GitHubCopilotProviderAdapter: ProviderUpdateStreamingAdapter {
    public nonisolated let providerID = ProviderID.githubCopilot
    public nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: true,
    )

    private let profiles: [GitHubCopilotProfile]
    private let reader: any GitHubCopilotUsageReading
    private let now: @Sendable () -> Date
    private let pollInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        profiles: [GitHubCopilotProfile],
        timeout: TimeInterval = 15,
    ) {
        self.profiles = profiles
        reader = GitHubCopilotUsageReader(timeout: timeout)
        now = Date.init
        pollInterval = .seconds(900)
        sleep = { duration in try await Task.sleep(for: duration) }
    }

    init(
        profiles: [GitHubCopilotProfile],
        reader: any GitHubCopilotUsageReading,
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
                discoveredAccounts.append(DiscoveredAccount(
                    providerID: .githubCopilot,
                    identity: result.identity.providerIdentity,
                    suggestedDisplayName: profile.displayName ?? result.identity.login,
                    credentialBinding: profile.credentialBinding,
                ))
            } catch {
                firstFailure = firstFailure ?? providerFailure(for: error)
            }
        }
        let identities = discoveredAccounts.map(\.identity.subjectID)
        if Set(identities).count != identities.count {
            throw .unavailable(code: "duplicate-github-copilot-identity")
        }
        if discoveredAccounts.isEmpty, let firstFailure {
            throw firstFailure
        }
        return discoveredAccounts
    }

    public func refresh(
        _ account: ProviderAccount,
    ) async throws(ProviderFailure) -> ProviderRefreshResult {
        guard account.providerID == .githubCopilot,
              let profile = profile(for: account)
        else {
            throw .unavailable(code: "github-copilot-profile-missing")
        }
        do {
            let result = try await reader.read(profile: profile, includeUsage: true)
            return try ProviderRefreshResult(
                identity: result.identity.providerIdentity,
                planName: result.planName,
                snapshots: GitHubCopilotRateLimitNormalizer.normalize(
                    result,
                    accountID: account.id,
                ),
                verifiedAt: result.observedAt,
            )
        } catch {
            throw providerFailure(for: error)
        }
    }

    public func updates(for account: ProviderAccount) async -> AsyncStream<ProviderUpdate> {
        guard account.providerID == .githubCopilot, profile(for: account) != nil else {
            let pair = AsyncStream<ProviderUpdate>.makeStream()
            pair.continuation.yield(
                .failure(.unavailable(code: "github-copilot-profile-missing")),
            )
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
                    pair.continuation.yield(
                        .failure(.failed(code: "github-copilot-polling-failed")),
                    )
                    nextInterval = .seconds(1800)
                }
            }
            pair.continuation.finish()
        }
        pair.continuation.onTermination = { _ in pollingTask.cancel() }
        return pair.stream
    }

    func interval(after failure: ProviderFailure) -> Duration {
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

    private func profile(for account: ProviderAccount) -> GitHubCopilotProfile? {
        guard case let .commandLineAccount(tool, login, configurationDirectory) =
            account.credentialBinding,
            tool == GitHubCopilotProfile.credentialTool
        else {
            return nil
        }
        let canonicalDirectory = configurationDirectory?
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return profiles.first { profile in
            profile.githubLogin.caseInsensitiveCompare(login) == .orderedSame
                && profile.configurationDirectory == canonicalDirectory
        }?.expecting(account.identity)
    }

    private func providerFailure(for error: any Error) -> ProviderFailure {
        guard let error = error as? GitHubCopilotProviderError else {
            return .failed(code: "github-copilot-unknown-failure")
        }
        return GitHubCopilotFailureMapper.providerFailure(for: error, now: now())
    }
}

enum GitHubCopilotFailureMapper {
    static func providerFailure(
        for error: GitHubCopilotProviderError,
        now: Date,
    ) -> ProviderFailure {
        switch error {
        case .identityMismatch:
            .identityMismatch
        case let .rateLimited(retryAfter):
            .rateLimited(retryAt: retryAfter.map { now.addingTimeInterval($0) })
        case .reauthenticationRequired, .signedOut:
            .signedOut
        case let .requestFailed(statusCode):
            requestFailure(statusCode: statusCode)
        default:
            staticFailure(for: error)
        }
    }

    private static func staticFailure(for error: GitHubCopilotProviderError) -> ProviderFailure {
        switch error {
        case .cliUnavailable:
            .unavailable(code: "github-cli-unavailable")
        case .cliFailed:
            .unavailable(code: "github-cli-failed")
        case .quotaUnavailable:
            .unavailable(code: "github-copilot-quota-unavailable")
        case .transportFailed:
            .unavailable(code: "github-copilot-service-unavailable")
        case .invalidCredential, .invalidProfile, .invalidResponse:
            .failed(code: "github-copilot-response-invalid")
        default:
            .failed(code: "github-copilot-unknown-failure")
        }
    }

    private static func requestFailure(statusCode: Int) -> ProviderFailure {
        if statusCode == 404 {
            .unavailable(code: "github-copilot-not-entitled")
        } else if statusCode >= 500 {
            .unavailable(code: "github-copilot-service-unavailable")
        } else {
            .failed(code: "github-copilot-request-\(statusCode)")
        }
    }
}

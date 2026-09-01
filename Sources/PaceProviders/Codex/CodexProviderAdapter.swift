import Foundation
import PaceCore

public struct CodexProviderAdapter: ProviderAdapterLifecycle, ProviderUpdateStreamingAdapter {
    public nonisolated let providerID = ProviderID.codex
    public nonisolated let capabilities = ProviderCapabilities(
        supportsAccountDiscovery: true,
        supportsMultipleAccounts: true,
        supportsStreamingUpdates: true,
    )

    private let profiles: [CodexProfile]
    private let reader: any CodexProfileSessionReading
    private let now: @Sendable () -> Date

    public init(
        profiles: [CodexProfile],
        executableURL: URL? = nil,
        timeout: TimeInterval = 10,
    ) {
        self.profiles = profiles
        let reader = CodexAppServerReader(executableURL: executableURL, timeout: timeout)
        self.reader = reader
        now = Date.init
    }

    init(
        profiles: [CodexProfile],
        reader: any CodexProfileSessionReading,
        now: @escaping @Sendable () -> Date,
    ) {
        self.profiles = profiles
        self.reader = reader
        self.now = now
    }

    public func discoverAccounts() async throws(ProviderFailure) -> [DiscoveredAccount] {
        var discoveredAccounts: [DiscoveredAccount] = []
        var firstFailure: ProviderFailure?
        for profile in profiles {
            do {
                let snapshot = try await reader.read(
                    profile: profile,
                    includeRateLimits: false,
                )
                let identity = try identity(from: snapshot.account)
                discoveredAccounts.append(
                    DiscoveredAccount(
                        providerID: .codex,
                        identity: identity,
                        suggestedDisplayName: profile.displayName ?? suggestedName(identity),
                        planName: planName(snapshot.account.account?.planType),
                        credentialBinding: .providerProfile(
                            directory: profile.directory,
                            ownership: profile.ownership,
                        ),
                    ),
                )
            } catch {
                firstFailure = firstFailure ?? providerFailure(for: error)
            }
        }
        let discoveredIdentities = discoveredAccounts.map(\.identity.subjectID)
        if Set(discoveredIdentities).count != discoveredIdentities.count {
            throw .unavailable(code: "duplicate-codex-identity")
        }
        if discoveredAccounts.isEmpty, let firstFailure {
            throw firstFailure
        }
        return discoveredAccounts
    }

    public func refresh(
        _ account: ProviderAccount,
    ) async throws(ProviderFailure) -> ProviderRefreshResult {
        guard account.providerID == .codex,
              let profile = profile(for: account.credentialBinding)
        else {
            throw .unavailable(code: "codex-profile-missing")
        }
        do {
            let observedAt = now()
            let profileSnapshot = try await reader.read(
                profile: profile,
                includeRateLimits: true,
            )
            let identity = try identity(from: profileSnapshot.account)
            guard let rateLimits = profileSnapshot.rateLimits else {
                throw CodexProviderError.invalidResponse
            }
            let snapshots = try CodexRateLimitNormalizer.normalize(
                rateLimits,
                accountID: account.id,
                observedAt: observedAt,
            )
            return ProviderRefreshResult(
                identity: identity,
                planName: planName(profileSnapshot.account.account?.planType),
                snapshots: snapshots,
                verifiedAt: observedAt,
            )
        } catch let error as CodexProviderError {
            throw providerFailure(for: error)
        } catch {
            throw .failed(code: "codex-normalization-failed")
        }
    }

    public func updates(for account: ProviderAccount) async -> AsyncStream<ProviderUpdate> {
        guard account.providerID == .codex,
              let profile = profile(for: account.credentialBinding)
        else {
            return Self.finishedUpdateStream(
                with: .failure(.unavailable(code: "codex-profile-missing")),
            )
        }
        let events: AsyncStream<CodexProfileEvent>
        do {
            events = try await reader.events(for: profile)
        } catch {
            return Self.finishedUpdateStream(with: .failure(providerFailure(for: error)))
        }

        let pair = AsyncStream<ProviderUpdate>.makeStream(
            bufferingPolicy: .bufferingNewest(8),
        )
        let updateTask = Task { [self] in
            for await event in events {
                guard !Task.isCancelled else {
                    break
                }
                switch event {
                case .connectionFailed:
                    pair.continuation.yield(
                        .failure(.unavailable(code: "codex-app-server-disconnected")),
                    )
                case .rateLimitsChanged, .reconnected:
                    do {
                        try await pair.continuation.yield(.refresh(refresh(account)))
                    } catch let failure as ProviderFailure {
                        pair.continuation.yield(.failure(failure))
                    } catch {
                        pair.continuation.yield(
                            .failure(.failed(code: "codex-monitor-refresh-failed")),
                        )
                    }
                }
            }
            await reader.close(profile: profile)
            pair.continuation.finish()
        }
        pair.continuation.onTermination = { [reader] _ in
            updateTask.cancel()
            Task { await reader.close(profile: profile) }
        }
        return pair.stream
    }

    public func shutdown() async {
        await reader.shutdown()
    }

    public func stopUpdates(for account: ProviderAccount) async {
        guard let profile = profile(for: account.credentialBinding) else {
            return
        }
        await reader.close(profile: profile)
    }

    private func profile(for binding: CredentialBinding) -> CodexProfile? {
        guard case let .providerProfile(directory, _) = binding else {
            return nil
        }
        return profiles.first {
            $0.directory.standardizedFileURL == directory.standardizedFileURL
        }
    }

    private func identity(
        from response: CodexAccountResponse,
    ) throws(CodexProviderError) -> ProviderIdentity {
        guard let account = response.account else {
            throw .signedOut
        }
        guard account.type == "chatgpt",
              let email = account.email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty
        else {
            throw .invalidAccount
        }
        return ProviderIdentity(
            subjectID: "chatgpt:\(email.lowercased())",
            email: email,
        )
    }

    private func suggestedName(_ identity: ProviderIdentity) -> String {
        identity.email ?? "Codex"
    }

    private func planName(_ planType: String?) -> String? {
        guard let planType else {
            return nil
        }
        return switch planType {
        case "free": "ChatGPT Free"
        case "go": "ChatGPT Go"
        case "plus": "ChatGPT Plus"
        case "pro", "prolite": "ChatGPT Pro"
        case "team", "business", "self_serve_business_prolite",
             "self_serve_business_usage_based": "ChatGPT Business"
        case "edu", "edu_plus", "edu_pro": "ChatGPT Edu"
        case "ent26", "enterprise", "enterprise_cbp_automation",
             "enterprise_cbp_usage_based": "ChatGPT Enterprise"
        default: nil
        }
    }

    private func providerFailure(for error: CodexProviderError) -> ProviderFailure {
        switch error {
        case .signedOut:
            .signedOut
        case .executableUnavailable:
            .unavailable(code: "codex-executable-unavailable")
        case .timedOut:
            .unavailable(code: "codex-app-server-timeout")
        case .invalidAccount:
            .unavailable(code: "codex-account-identity-unavailable")
        case .invalidResponse, .processFailed, .protocolFailure:
            .failed(code: "codex-app-server-failed")
        }
    }

    private static func finishedUpdateStream(
        with update: ProviderUpdate? = nil,
    ) -> AsyncStream<ProviderUpdate> {
        let pair = AsyncStream<ProviderUpdate>.makeStream()
        if let update {
            pair.continuation.yield(update)
        }
        pair.continuation.finish()
        return pair.stream
    }
}

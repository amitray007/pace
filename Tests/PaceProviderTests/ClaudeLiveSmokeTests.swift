import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Claude live smoke")
struct ClaudeLiveSmokeTests {
    @Test
    func `reads selected profile without a running Claude process`() async throws {
        guard ProcessInfo.processInfo.environment["PACE_LIVE_CLAUDE"] == "1" else {
            return
        }
        let trace = ClaudeLiveSmokeTrace()
        let profile = ClaudeProfile.current(environment: ProcessInfo.processInfo.environment)
        let adapter = ClaudeProviderAdapter(
            profiles: [profile],
            reader: ClaudeUsageReader(
                transport: ClaudeLiveSmokeTracingTransport(trace: trace),
                allowsCredentialRefresh: false,
            ),
            now: Date.init,
        )

        do {
            let accounts = try await adapter.discoverAccounts()
            let discovered = try #require(accounts.first)
            let account = ProviderAccount(
                id: AccountID(),
                providerID: .claude,
                identity: discovered.identity,
                credentialBinding: discovered.credentialBinding,
                addedAt: Date(),
                displayName: discovered.suggestedDisplayName,
                planName: discovered.planName,
                isEnabled: true,
                order: 0,
                connectionState: .needsAuthentication,
            )
            let result = try await adapter.refresh(account)

            #expect(result.identity == discovered.identity)
            #expect(!result.snapshots.isEmpty)
            #expect(result.snapshots.allSatisfy { $0.id.accountID == account.id })
        } catch {
            let report = await trace.report()
            Issue.record("Claude live request trace: \(report)")
            throw error
        }
    }
}

private struct ClaudeLiveSmokeTracingTransport: ClaudeHTTPTransport {
    private let base = ClaudeURLSessionTransport()
    let trace: ClaudeLiveSmokeTrace

    func send(_ request: URLRequest) async throws -> ClaudeHTTPResponse {
        do {
            let response = try await base.send(request)
            await trace.record(path: request.url?.path, statusCode: response.statusCode)
            return response
        } catch {
            let errorType = String(describing: type(of: error))
            await trace.record(
                path: request.url?.path,
                errorType: errorType,
            )
            throw error
        }
    }
}

private actor ClaudeLiveSmokeTrace {
    private var entries: [String] = []

    func record(path: String?, statusCode: Int) {
        entries.append("\(path ?? "unknown-path") HTTP \(statusCode)")
    }

    func record(path: String?, errorType: String) {
        entries.append("\(path ?? "unknown-path") transport \(errorType)")
    }

    func report() -> String {
        entries.isEmpty ? "no request completed" : entries.joined(separator: ", ")
    }
}

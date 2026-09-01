import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Cursor live smoke")
struct CursorLiveSmokeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PACE_LIVE_CURSOR_TEST"] == "1"))
    func `reads current profile without a running Cursor process`() async throws {
        let trace = CursorLiveSmokeTrace()
        let adapter = CursorProviderAdapter(
            profiles: [.current()],
            reader: CursorUsageReader(
                transport: CursorLiveSmokeTracingTransport(trace: trace),
            ),
            now: Date.init,
        )

        do {
            let discovered = try await adapter.discoverAccounts()
            let candidate = try #require(discovered.first)
            let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
            let account = try await store.register(candidate)
            let refreshed = try await adapter.refresh(account)

            #expect(discovered.count == 1)
            #expect(candidate.providerID == .cursor)
            #expect(refreshed.identity == candidate.identity)
            #expect(!refreshed.snapshots.isEmpty)
            #expect(refreshed.snapshots.allSatisfy { $0.id.accountID == account.id })
        } catch {
            let report = await trace.report()
            Issue.record("Cursor live request trace: \(report)")
            throw error
        }
    }
}

private struct CursorLiveSmokeTracingTransport: CursorHTTPTransport {
    private let base = CursorURLSessionTransport()
    let trace: CursorLiveSmokeTrace

    func send(_ request: URLRequest) async throws -> CursorHTTPResponse {
        do {
            let response = try await base.send(request)
            await trace.record(path: request.url?.path, statusCode: response.statusCode)
            return response
        } catch {
            await trace.record(
                path: request.url?.path,
                errorType: String(describing: type(of: error)),
            )
            throw error
        }
    }
}

private actor CursorLiveSmokeTrace {
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

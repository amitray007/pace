import Foundation
import PaceCore
@testable import PaceProviders
import Testing

extension CodexAppServerSessionTests {
    @Test
    func `disabling an account closes its monitored profile process`() async throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }
        let store = try await PaceStore.open(persistence: InMemoryPaceStatePersistence())
        let adapter = CodexProviderAdapter(
            profiles: [fixture.profile],
            executableURL: fixture.executableURL,
            timeout: 2,
        )
        let refreshCoordinator = try RefreshCoordinator(store: store, adapters: [adapter])
        let accountCoordinator = AccountCoordinator(
            store: store,
            refreshCoordinator: refreshCoordinator,
        )
        let candidate = try #require(
            await accountCoordinator.discover(for: .codex).first,
        )
        let account = try await accountCoordinator.add(candidate)
        let updates = await refreshCoordinator.updateStream()
        let collector = Task {
            for await _ in updates {}
        }
        try await waitUntil { fixture.processIDIfPresent() != nil }
        let processID = try fixture.processID()

        try await accountCoordinator.setEnabled(account.id, isEnabled: false)

        try await waitUntil { !fixture.processIsRunning(processID) }
        collector.cancel()
        await collector.value
        await refreshCoordinator.shutdownAdapters()
    }

    @Test
    func `shutdown cancels and reaps a connection that is still opening`() async throws {
        let fixture = try CodexServerFixture(omitsInitializeResponse: true)
        defer { fixture.remove() }
        let reader = CodexAppServerReader(
            executableURL: fixture.executableURL,
            timeout: 5,
            reconnectDelays: [.milliseconds(10)],
        )
        let readTask = Task<Void, Never> {
            do {
                _ = try await reader.read(
                    profile: fixture.profile,
                    includeRateLimits: false,
                )
            } catch {
                return
            }
            Issue.record("Expected shutdown to cancel the opening read")
        }
        try await waitUntil { fixture.processIDIfPresent() != nil }
        let processID = try fixture.processID()

        await reader.shutdown()

        _ = try await taskValue(readTask)
        try await waitUntil { !fixture.processIsRunning(processID) }
        #expect(try fixture.startCount() == 1)
    }
}

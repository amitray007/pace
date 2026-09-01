import Foundation

struct ProviderTestTimeout: Error {}

func taskValue<Value: Sendable>(
    _ task: Task<Value, Never>,
    within timeout: Duration = .seconds(2),
) async throws -> Value {
    do {
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                await task.value
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ProviderTestTimeout()
            }
            guard let value = try await group.next() else {
                throw ProviderTestTimeout()
            }
            group.cancelAll()
            return value
        }
    } catch {
        task.cancel()
        throw error
    }
}

func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @Sendable () async -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            throw ProviderTestTimeout()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

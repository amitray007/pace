import Foundation

actor CursorRequestGate {
    private var isLocked = false
    private var waiters: [Waiter] = []

    func acquire() async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if !isLocked {
                    isLocked = true
                    continuation.resume()
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
            do {
                try Task.checkCancellation()
            } catch {
                release()
                throw error
            }
        } onCancel: {
            Task { await cancelWaiter(id) }
        }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }
}

actor CursorRequestGatePool {
    static let shared = CursorRequestGatePool()

    private var gates: [CursorProfileKey: CursorRequestGate] = [:]

    func gate(for profile: CursorProfile) -> CursorRequestGate {
        let key = CursorProfileKey(profile: profile)
        if let gate = gates[key] {
            return gate
        }
        let gate = CursorRequestGate()
        gates[key] = gate
        return gate
    }
}

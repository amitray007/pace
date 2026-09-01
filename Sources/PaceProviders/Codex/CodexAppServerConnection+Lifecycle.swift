import Foundation

extension CodexAppServerConnection {
    func beginClosing() -> Bool {
        let captured = lock.withLock { () -> ClosingCapture in
            guard lifecycle == .starting || lifecycle == .running else {
                return ClosingCapture(events: [], requests: [], shouldClose: false)
            }
            lifecycle = .closing
            let events = Array(eventContinuations.values)
            eventContinuations.removeAll()
            let requests = Array(pendingRequests.values)
            pendingRequests.removeAll()
            activeRequestIDs.removeAll()
            cancelledRequestIDs.removeAll()
            pendingRateLimitsChange = false
            return ClosingCapture(events: events, requests: requests, shouldClose: true)
        }
        guard captured.shouldClose else {
            return false
        }

        output.fileHandleForReading.readabilityHandler = nil
        for request in captured.requests {
            request.timeout.cancel()
            request.continuation.resume(throwing: CodexProviderError.processFailed)
        }
        for continuation in captured.events {
            continuation.yield(.exited)
            continuation.finish()
        }
        return true
    }

    func cancelRequest(_ requestID: Int) {
        let pending = lock.withLock { () -> PendingRequest? in
            guard activeRequestIDs.contains(requestID) else {
                return nil
            }
            if let pending = pendingRequests.removeValue(forKey: requestID) {
                activeRequestIDs.remove(requestID)
                return pending
            }
            cancelledRequestIDs.insert(requestID)
            return nil
        }
        if let pending {
            pending.timeout.cancel()
            pending.continuation.resume(throwing: CodexProviderError.processFailed)
        }
        closeSoon()
    }

    func completeRequest(id: Int, response: Data) {
        let pending = lock.withLock { () -> PendingRequest? in
            guard let pending = pendingRequests.removeValue(forKey: id) else {
                return nil
            }
            activeRequestIDs.remove(id)
            cancelledRequestIDs.remove(id)
            return pending
        }
        guard let pending else {
            return
        }
        pending.timeout.cancel()
        pending.continuation.resume(returning: response)
    }

    func failRequest(
        id: Int,
        error: CodexProviderError,
    ) {
        let pending = lock.withLock { () -> PendingRequest? in
            guard let pending = pendingRequests.removeValue(forKey: id) else {
                return nil
            }
            activeRequestIDs.remove(id)
            cancelledRequestIDs.remove(id)
            return pending
        }
        guard let pending else {
            return
        }
        pending.timeout.cancel()
        pending.continuation.resume(throwing: error)
        closeSoon()
    }

    func markRunning() {
        let shouldClose = lock.withLock {
            guard lifecycle == .starting else {
                return true
            }
            lifecycle = .running
            return false
        }
        if shouldClose {
            closeSoon()
        }
    }

    func removeEventContinuation(_ id: UUID) {
        lock.withLock { _ = eventContinuations.removeValue(forKey: id) }
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return operation()
    }
}

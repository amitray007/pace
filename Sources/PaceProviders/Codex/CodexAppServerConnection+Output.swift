import Foundation

extension CodexAppServerConnection {
    private struct ExitCapture {
        let events: [AsyncStream<CodexConnectionEvent>.Continuation]
        let requests: [PendingRequest]
        let shouldFinish: Bool
        let waiters: [CheckedContinuation<Void, Never>]
    }

    func consume(_ data: Data) {
        var completedResponses: [(Int, Data)] = []
        var emittedEvents: [CodexConnectionEvent] = []
        var continuations: [AsyncStream<CodexConnectionEvent>.Continuation] = []
        var invalidBuffer = false

        lock.lock()
        buffer.append(data)
        let newline = Data([0x0A])
        while let boundary = buffer.range(of: newline) {
            let line = Data(buffer[..<boundary.lowerBound])
            buffer.removeSubrange(..<boundary.upperBound)
            consumeLine(
                line,
                completedResponses: &completedResponses,
                emittedEvents: &emittedEvents,
            )
        }
        if buffer.count > Self.maximumBufferBytes {
            invalidBuffer = true
            buffer.removeAll(keepingCapacity: false)
        }
        if !emittedEvents.isEmpty {
            continuations = Array(eventContinuations.values)
        }
        lock.unlock()

        for (id, response) in completedResponses {
            completeRequest(id: id, response: response)
        }
        for event in emittedEvents {
            continuations.forEach { $0.yield(event) }
        }
        if invalidBuffer {
            closeSoon()
        }
    }

    private func consumeLine(
        _ line: Data,
        completedResponses: inout [(Int, Data)],
        emittedEvents: inout [CodexConnectionEvent],
    ) {
        guard !line.isEmpty,
              let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else {
            return
        }
        if message["method"] == nil {
            guard let responseID = (message["id"] as? NSNumber)?.intValue,
                  pendingRequests[responseID] != nil
            else {
                return
            }
            completedResponses.append((responseID, line))
            return
        }
        guard message["method"] as? String == "account/rateLimits/updated" else {
            return
        }
        if eventContinuations.isEmpty {
            pendingRateLimitsChange = true
        } else {
            emittedEvents.append(.rateLimitsChanged)
        }
    }

    func didExit() {
        output.fileHandleForReading.readabilityHandler = nil
        let captured = lock.withLock { () -> ExitCapture in
            guard lifecycle != .exited else {
                return ExitCapture(events: [], requests: [], shouldFinish: false, waiters: [])
            }
            lifecycle = .exited
            let events = Array(eventContinuations.values)
            eventContinuations.removeAll()
            let requests = Array(pendingRequests.values)
            pendingRequests.removeAll()
            activeRequestIDs.removeAll()
            cancelledRequestIDs.removeAll()
            let waiters = exitWaiters
            exitWaiters.removeAll()
            return ExitCapture(
                events: events,
                requests: requests,
                shouldFinish: true,
                waiters: waiters,
            )
        }
        guard captured.shouldFinish else {
            return
        }

        for request in captured.requests {
            request.timeout.cancel()
            request.continuation.resume(throwing: CodexProviderError.processFailed)
        }
        for continuation in captured.events {
            continuation.yield(.exited)
            continuation.finish()
        }
        captured.waiters.forEach { $0.resume() }
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return operation()
    }
}

import Foundation

enum CodexProfileEvent: Equatable, Sendable {
    case connectionFailed
    case rateLimitsChanged
    case reconnected
}

actor CodexConnectionPool {
    private enum ObservationResult {
        case cancelled
        case disconnected(wasStable: Bool)
    }

    private struct OpeningConnection {
        let id: UUID
        let task: Task<CodexAppServerConnection, Error>
    }

    private let executableURL: URL
    private let reconnectDelays: [Duration]
    private let requestTimeout: TimeInterval
    private var connections: [String: CodexAppServerConnection] = [:]
    private var isShutdown = false
    private var openingConnections: [String: OpeningConnection] = [:]

    init(
        executableURL: URL,
        requestTimeout: TimeInterval,
        reconnectDelays: [Duration] = [
            .milliseconds(250),
            .seconds(1),
            .seconds(5),
            .seconds(30),
        ],
    ) {
        self.executableURL = executableURL
        self.requestTimeout = requestTimeout
        self.reconnectDelays = reconnectDelays.isEmpty ? [.seconds(1)] : reconnectDelays
    }

    deinit {
        openingConnections.values.forEach { $0.task.cancel() }
        connections.values.forEach { $0.closeSoon() }
    }

    func connection(
        for profile: CodexProfile,
    ) async throws(CodexProviderError) -> CodexAppServerConnection {
        guard !isShutdown else {
            throw .processFailed
        }
        let key = profile.directory.standardizedFileURL.path
        if let connection = connections[key], connection.isUsable {
            return connection
        }
        if let opening = openingConnections[key] {
            return try await result(of: opening.task)
        }

        let staleConnection = connections[key]
        let openingID = UUID()
        let task = Task<CodexAppServerConnection, Error> {
            if let staleConnection {
                await staleConnection.close()
            }
            return try await CodexAppServerConnection.open(
                executableURL: executableURL,
                profileDirectory: profile.directory,
                requestTimeout: requestTimeout,
            )
        }
        openingConnections[key] = OpeningConnection(id: openingID, task: task)

        do {
            let candidate = try await result(of: task)
            guard !isShutdown, openingConnections[key]?.id == openingID else {
                await candidate.close()
                throw CodexProviderError.processFailed
            }
            if openingConnections[key]?.id == openingID {
                openingConnections.removeValue(forKey: key)
                connections[key] = candidate
            }
            return candidate
        } catch let error as CodexProviderError {
            if openingConnections[key]?.id == openingID {
                openingConnections.removeValue(forKey: key)
                if connections[key] === staleConnection {
                    connections.removeValue(forKey: key)
                }
            }
            throw error
        } catch {
            throw .processFailed
        }
    }

    func events(for profile: CodexProfile) -> AsyncStream<CodexProfileEvent> {
        guard !isShutdown else {
            let pair = AsyncStream<CodexProfileEvent>.makeStream()
            pair.continuation.finish()
            return pair.stream
        }
        let pair = AsyncStream<CodexProfileEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(8),
        )
        let monitorTask = Task { [weak self] in
            guard let self else {
                pair.continuation.finish()
                return
            }
            await monitor(profile: profile, continuation: pair.continuation)
        }
        pair.continuation.onTermination = { [weak self] _ in
            monitorTask.cancel()
            Task { await self?.close(profile: profile) }
        }
        return pair.stream
    }

    func close(profile: CodexProfile) async {
        let key = profile.directory.standardizedFileURL.path
        let opening = openingConnections.removeValue(forKey: key)
        opening?.task.cancel()
        let connection = connections.removeValue(forKey: key)
        await connection?.close()
        if let opening, let openedConnection = try? await opening.task.value {
            await openedConnection.close()
        }
    }

    func shutdown() async {
        isShutdown = true
        let openings = Array(openingConnections.values)
        openingConnections.removeAll()
        openings.forEach { $0.task.cancel() }

        let activeConnections = Array(connections.values)
        connections.removeAll()
        await withTaskGroup(of: Void.self) { group in
            for connection in activeConnections {
                group.addTask {
                    await connection.close()
                }
            }
        }
        for opening in openings {
            if let connection = try? await opening.task.value {
                await connection.close()
            }
        }
    }

    private func monitor(
        profile: CodexProfile,
        continuation: AsyncStream<CodexProfileEvent>.Continuation,
    ) async {
        var failureCount = 0
        while !Task.isCancelled {
            let result = await observeProfile(
                profile,
                failureCount: failureCount,
                continuation: continuation,
            )
            guard case let .disconnected(wasStable) = result else {
                break
            }
            if wasStable {
                failureCount = 0
            }
            continuation.yield(.connectionFailed)
            let delay = reconnectDelays[min(failureCount, reconnectDelays.count - 1)]
            failureCount += 1
            do {
                try await Task.sleep(for: delay)
            } catch {
                break
            }
        }
        continuation.finish()
    }

    private func observeProfile(
        _ profile: CodexProfile,
        failureCount: Int,
        continuation: AsyncStream<CodexProfileEvent>.Continuation,
    ) async -> ObservationResult {
        do {
            let connection = try await connection(for: profile)
            guard !Task.isCancelled else {
                await invalidate(connection, for: profile)
                return .cancelled
            }
            if failureCount > 0 {
                continuation.yield(.reconnected)
            }
            let connectedAt = ContinuousClock.now
            let wasCancelled = await forwardEvents(
                from: connection,
                to: continuation,
            )
            await invalidate(connection, for: profile)
            guard !wasCancelled else {
                return .cancelled
            }
            let lifetime = connectedAt.duration(to: ContinuousClock.now)
            return .disconnected(wasStable: lifetime >= .seconds(30))
        } catch {
            // Public events intentionally omit process and credential details.
            return Task.isCancelled ? .cancelled : .disconnected(wasStable: false)
        }
    }

    private func forwardEvents(
        from connection: CodexAppServerConnection,
        to continuation: AsyncStream<CodexProfileEvent>.Continuation,
    ) async -> Bool {
        for await event in connection.events() {
            guard !Task.isCancelled else {
                return true
            }
            if case .rateLimitsChanged = event {
                continuation.yield(.rateLimitsChanged)
            }
        }
        return Task.isCancelled
    }

    private func invalidate(
        _ connection: CodexAppServerConnection,
        for profile: CodexProfile,
    ) async {
        let key = profile.directory.standardizedFileURL.path
        await connection.close()
        if connections[key] === connection {
            connections.removeValue(forKey: key)
        }
    }

    private func result(
        of task: Task<CodexAppServerConnection, Error>,
    ) async throws(CodexProviderError) -> CodexAppServerConnection {
        do {
            return try await task.value
        } catch let error as CodexProviderError {
            throw error
        } catch {
            throw .processFailed
        }
    }
}

final class CodexConnectionPoolResolver: @unchecked Sendable {
    private let configuredExecutableURL: URL?
    private let lock = NSLock()
    private let reconnectDelays: [Duration]
    private let requestTimeout: TimeInterval
    private var resolvedPool: CodexConnectionPool?
    private var isShutdown = false

    init(
        executableURL: URL?,
        requestTimeout: TimeInterval,
        reconnectDelays: [Duration],
    ) {
        configuredExecutableURL = executableURL
        self.requestTimeout = requestTimeout
        self.reconnectDelays = reconnectDelays
    }

    func pool() throws(CodexProviderError) -> CodexConnectionPool {
        let current = lock.withLock { (isShutdown, resolvedPool) }
        guard !current.0 else {
            throw .processFailed
        }
        if let resolvedPool = current.1 {
            return resolvedPool
        }
        let executableURL: URL = if let configuredExecutableURL {
            configuredExecutableURL
        } else {
            try CodexExecutableLocator.locate()
        }
        let candidate = CodexConnectionPool(
            executableURL: executableURL,
            requestTimeout: requestTimeout,
            reconnectDelays: reconnectDelays,
        )
        let installedPool: CodexConnectionPool? = lock.withLock {
            guard !isShutdown else {
                return nil
            }
            if let resolvedPool {
                return Optional(resolvedPool)
            }
            resolvedPool = candidate
            return Optional(candidate)
        }
        guard let installedPool else {
            throw .processFailed
        }
        return installedPool
    }

    func shutdown() async {
        let pool = lock.withLock { () -> CodexConnectionPool? in
            isShutdown = true
            defer { resolvedPool = nil }
            return resolvedPool
        }
        await pool?.shutdown()
    }

    func close(profile: CodexProfile) async {
        let pool = lock.withLock { resolvedPool }
        await pool?.close(profile: profile)
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return operation()
    }
}

import Darwin
import Foundation

enum CodexConnectionEvent: Sendable {
    case exited
    case rateLimitsChanged
}

final class CodexAppServerConnection: @unchecked Sendable {
    enum Lifecycle {
        case starting
        case running
        case closing
        case exited
    }

    struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeout: DispatchWorkItem
    }

    struct ClosingCapture {
        let events: [AsyncStream<CodexConnectionEvent>.Continuation]
        let requests: [PendingRequest]
        let shouldClose: Bool
    }

    static let maximumBufferBytes = 1_048_576
    private static let shutdownGrace: TimeInterval = 0.25
    private static let forceKillGrace: TimeInterval = 0.5

    private let input = Pipe()
    private let ioQueue: DispatchQueue
    let lock = NSLock()
    let output = Pipe()
    private let process = Process()
    private let requestTimeout: TimeInterval
    private let shutdownQueue: DispatchQueue
    private let timerQueue: DispatchQueue
    var activeRequestIDs: Set<Int> = []
    var buffer = Data()
    var cancelledRequestIDs: Set<Int> = []
    var eventContinuations: [
        UUID: AsyncStream<CodexConnectionEvent>.Continuation
    ] = [:]
    var exitWaiters: [CheckedContinuation<Void, Never>] = []
    var lifecycle = Lifecycle.starting
    private var nextRequestID = 1
    var pendingRateLimitsChange = false
    var pendingRequests: [Int: PendingRequest] = [:]

    private init(
        executableURL: URL,
        profileDirectory: URL,
        requestTimeout: TimeInterval,
    ) {
        self.requestTimeout = requestTimeout
        let queueID = UUID().uuidString
        ioQueue = DispatchQueue(label: "app.pace.codex.io.\(queueID)")
        shutdownQueue = DispatchQueue(label: "app.pace.codex.shutdown.\(queueID)")
        timerQueue = DispatchQueue(label: "app.pace.codex.timer.\(queueID)")

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.environment = CodexLaunchEnvironment.environment(
            executableURL: executableURL,
            profileDirectory: profileDirectory,
        )
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in self?.didExit() }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                self?.consume(data)
            }
        }
    }

    static func open(
        executableURL: URL,
        profileDirectory: URL,
        requestTimeout: TimeInterval,
    ) async throws(CodexProviderError) -> CodexAppServerConnection {
        let connection = CodexAppServerConnection(
            executableURL: executableURL,
            profileDirectory: profileDirectory,
            requestTimeout: requestTimeout,
        )
        do {
            try connection.process.run()
            connection.markRunning()
            _ = try await connection.request(
                method: "initialize",
                params: #"{"clientInfo":{"name":"pace","title":"Pace","version":"0.1.0"}}"#,
            )
            connection.notify(method: "initialized", params: "{}")
            return connection
        } catch let error as CodexProviderError {
            await connection.close()
            throw connection.launchFailure(or: error)
        } catch {
            await connection.close()
            throw .executableUnavailable
        }
    }

    var isUsable: Bool {
        lock.withLock { lifecycle == .running && process.isRunning }
    }

    /// Distinguishes a runtime that could not start from a server that failed.
    ///
    /// A `#!/usr/bin/env node` script exits with 127 when `node` is missing and 126 when the
    /// interpreter cannot be executed, before it reads the initialize request.
    private func launchFailure(or error: CodexProviderError) -> CodexProviderError {
        guard error == .processFailed,
              !process.isRunning,
              process.terminationReason == .exit,
              [126, 127].contains(process.terminationStatus)
        else {
            return error
        }
        return .executableUnavailable
    }

    func request(
        method: String,
        params: String? = nil,
    ) async throws(CodexProviderError) -> Data {
        let requestID = lock.withLock { () -> Int? in
            guard lifecycle == .running, process.isRunning else {
                return nil
            }
            let requestID = nextRequestID
            nextRequestID += 1
            activeRequestIDs.insert(requestID)
            return requestID
        }
        guard let requestID else {
            throw .processFailed
        }
        let message = Self.requestMessage(id: requestID, method: method, params: params)

        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    registerRequest(
                        id: requestID,
                        message: message,
                        continuation: continuation,
                    )
                }
            } onCancel: {
                self.cancelRequest(requestID)
            }
        } catch let error as CodexProviderError {
            throw error
        } catch {
            throw .processFailed
        }
    }

    func events() -> AsyncStream<CodexConnectionEvent> {
        let id = UUID()
        let pair = AsyncStream<CodexConnectionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(8),
        )
        let state = lock.withLock { () -> (isExited: Bool, hasPendingChange: Bool) in
            guard lifecycle == .running else {
                return (true, false)
            }
            eventContinuations[id] = pair.continuation
            let hasPendingChange = pendingRateLimitsChange
            pendingRateLimitsChange = false
            return (false, hasPendingChange)
        }
        if state.hasPendingChange {
            pair.continuation.yield(.rateLimitsChanged)
        }
        if state.isExited {
            pair.continuation.yield(.exited)
            pair.continuation.finish()
        }
        pair.continuation.onTermination = { [weak self] _ in
            self?.removeEventContinuation(id)
        }
        return pair.stream
    }

    func close() async {
        closeSoon()
        await withCheckedContinuation { continuation in
            let resumesImmediately = lock.withLock {
                guard lifecycle != .exited else {
                    return true
                }
                exitWaiters.append(continuation)
                return false
            }
            if resumesImmediately {
                continuation.resume()
            }
        }
    }

    func closeSoon() {
        guard beginClosing() else {
            return
        }
        shutdownQueue.async { [self] in
            try? input.fileHandleForWriting.close()
            guard process.isRunning else {
                didExit()
                return
            }

            process.terminate()
            if waitForProcessExit(within: Self.shutdownGrace) {
                didExit()
                return
            }

            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            if !waitForProcessExit(within: Self.forceKillGrace), process.isRunning {
                process.waitUntilExit()
            }
            didExit()
        }
    }

    private func notify(method: String, params: String) {
        let message = Data(
            #"{"jsonrpc":"2.0","method":"\#(method)","params":\#(params)}"#.utf8,
        ) + Data([0x0A])
        ioQueue.async { [weak self] in
            guard let self, isUsable else {
                return
            }
            do {
                try input.fileHandleForWriting.write(contentsOf: message)
            } catch {
                closeSoon()
            }
        }
    }

    private func registerRequest(
        id: Int,
        message: Data,
        continuation: CheckedContinuation<Data, Error>,
    ) {
        let timeout = DispatchWorkItem { [weak self] in
            self?.failRequest(id: id, error: .timedOut)
        }
        let registered = lock.withLock {
            guard lifecycle == .running,
                  activeRequestIDs.contains(id),
                  cancelledRequestIDs.remove(id) == nil
            else {
                activeRequestIDs.remove(id)
                return false
            }
            pendingRequests[id] = PendingRequest(
                continuation: continuation,
                timeout: timeout,
            )
            return true
        }
        guard registered else {
            timeout.cancel()
            continuation.resume(throwing: CodexProviderError.processFailed)
            return
        }

        timerQueue.asyncAfter(
            deadline: .now() + requestTimeout,
            execute: timeout,
        )
        ioQueue.async { [weak self] in
            guard let self else {
                return
            }
            do {
                try input.fileHandleForWriting.write(contentsOf: message)
            } catch {
                failRequest(id: id, error: .processFailed)
            }
        }
    }

    private func waitForProcessExit(within duration: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: duration)
        while process.isRunning, Date() < deadline {
            usleep(10000)
        }
        return !process.isRunning
    }

    private static func requestMessage(
        id: Int,
        method: String,
        params: String?,
    ) -> Data {
        let paramsField = params.map { #", "params":\#($0)"# } ?? ""
        return Data(
            #"{"jsonrpc":"2.0","method":"\#(method)","id":\#(id)\#(paramsField)}"#.utf8,
        ) + Data([0x0A])
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return operation()
    }
}

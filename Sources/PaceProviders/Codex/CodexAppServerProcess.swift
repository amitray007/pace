import Foundation

private final class CodexResponseCollector: @unchecked Sendable {
    private let condition = NSCondition()
    private let expectedResponseIDs: Set<Int>
    private var buffer = Data()
    private var responses: [Int: Data] = [:]
    private var processExited = false

    init(expectedResponseIDs: Set<Int>) {
        self.expectedResponseIDs = expectedResponseIDs
    }

    func consume(_ data: Data) {
        condition.lock()
        defer { condition.unlock() }
        buffer.append(data)
        let newline = Data([0x0A])
        while let boundary = buffer.range(of: newline) {
            let line = Data(buffer[..<boundary.lowerBound])
            buffer.removeSubrange(..<boundary.upperBound)
            guard let id = Self.responseID(from: line), expectedResponseIDs.contains(id) else {
                continue
            }
            responses[id] = line
        }
        if expectedResponseIDs.isSubset(of: responses.keys) {
            condition.broadcast()
        }
    }

    func processDidExit() {
        condition.lock()
        processExited = true
        condition.broadcast()
        condition.unlock()
    }

    func wait(timeout: TimeInterval) -> [Int: Data]? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !expectedResponseIDs.isSubset(of: responses.keys), !processExited {
            if !condition.wait(until: deadline) {
                return nil
            }
        }
        return expectedResponseIDs.isSubset(of: responses.keys) ? responses : nil
    }

    private static func responseID(from data: Data) -> Int? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = object as? [String: Any]
        else {
            return nil
        }
        return (message["id"] as? NSNumber)?.intValue
    }
}

enum CodexAppServerProcess {
    static func exchange(
        executableURL: URL,
        profileDirectory: URL,
        includeRateLimits: Bool,
        timeout: TimeInterval,
    ) throws(CodexProviderError) -> [Int: Data] {
        let expectedResponseIDs: Set<Int> = includeRateLimits ? [2, 3] : [2]
        let collector = CodexResponseCollector(expectedResponseIDs: expectedResponseIDs)
        let process = Process()
        let input = Pipe()
        let output = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = profileDirectory.standardizedFileURL.path
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in collector.processDidExit() }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                collector.consume(data)
            }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw .executableUnavailable
        }
        input.fileHandleForWriting.write(requestData(includeRateLimits: includeRateLimits))

        let responses = collector.wait(timeout: timeout)
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        guard let responses else {
            if process.terminationStatus == 127 {
                throw .executableUnavailable
            }
            throw process.terminationReason == .uncaughtSignal ? .timedOut : .processFailed
        }
        return responses
    }

    private static func requestData(includeRateLimits: Bool) -> Data {
        let initialize =
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"# +
            #""name":"pace","title":"Pace","version":"0.1.0"}}}"#
        var requests = [
            initialize,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/read","id":2,"params":{"refreshToken":false}}"#,
        ]
        if includeRateLimits {
            requests.append(#"{"method":"account/rateLimits/read","id":3}"#)
        }
        return Data((requests.joined(separator: "\n") + "\n").utf8)
    }
}

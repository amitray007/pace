#!/usr/bin/env swift

import Foundation

/// Minimal proof that a local macOS process can read supported Codex quota snapshots without
/// reading OAuth tokens or calling private web endpoints.
final class ResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var response: [String: Any]?
    let finished = DispatchSemaphore(value: 0)

    func consume(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)
        let newline = Data([0x0A])

        while let boundary = buffer.range(of: newline) {
            let line = buffer[..<boundary.lowerBound]
            buffer.removeSubrange(..<boundary.upperBound)

            guard
                !line.isEmpty,
                let object = try? JSONSerialization.jsonObject(with: Data(line)),
                let message = object as? [String: Any],
                (message["id"] as? NSNumber)?.intValue == 2
            else {
                continue
            }

            response = message
            finished.signal()
            return
        }
    }

    func takeResponse() -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return response
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

let process = Process()
let input = Pipe()
let output = Pipe()
let errors = Pipe()
let collector = ResponseCollector()

process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["codex", "app-server", "--stdio"]
process.standardInput = input
process.standardOutput = output
process.standardError = errors

output.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty {
        collector.consume(data)
    }
}

do {
    try process.run()
} catch {
    fail("could not start `codex app-server`: \(error.localizedDescription)")
}

let requests = [
    #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"pace-spike","title":"Pace Spike","version":"0.1.0"}}}"#,
    #"{"method":"initialized","params":{}}"#,
    #"{"method":"account/rateLimits/read","id":2}"#,
].joined(separator: "\n") + "\n"

input.fileHandleForWriting.write(Data(requests.utf8))

guard collector.finished.wait(timeout: .now() + 10) == .success else {
    process.terminate()
    fail("Codex did not return a rate-limit snapshot within 10 seconds")
}

output.fileHandleForReading.readabilityHandler = nil
process.terminate()
process.waitUntilExit()

guard
    let message = collector.takeResponse(),
    message["error"] == nil,
    let result = message["result"] as? [String: Any]
else {
    let stderr = errors.fileHandleForReading.readDataToEndOfFile()
    let detail = String(data: stderr, encoding: .utf8) ?? "unknown app-server error"
    fail(detail.trimmingCharacters(in: .whitespacesAndNewlines))
}

var buckets = result["rateLimitsByLimitId"] as? [String: Any] ?? [:]
if buckets.isEmpty, let fallback = result["rateLimits"] as? [String: Any] {
    let fallbackID = fallback["limitId"] as? String ?? "codex"
    buckets[fallbackID] = fallback
}

if buckets.isEmpty {
    fail("Codex returned no quota buckets for the current account")
}

let dateFormatter = ISO8601DateFormatter()

for bucketID in buckets.keys.sorted() {
    guard let bucket = buckets[bucketID] as? [String: Any] else { continue }
    let label = bucket["limitName"] as? String ?? bucketID

    for windowName in ["primary", "secondary"] {
        guard let window = bucket[windowName] as? [String: Any] else { continue }
        let usedPercent = (window["usedPercent"] as? NSNumber)?.intValue ?? 0
        let durationMinutes = (window["windowDurationMins"] as? NSNumber)?.intValue
        let resetsAt = (window["resetsAt"] as? NSNumber).map {
            dateFormatter.string(from: Date(timeIntervalSince1970: $0.doubleValue))
        }

        let durationText = durationMinutes.map { "\($0) min" } ?? "unknown window"
        let resetText = resetsAt ?? "unknown reset"
        print(
            "\(label) [\(windowName)]: \(usedPercent)% used, \(durationText), resets \(resetText)",
        )
    }
}

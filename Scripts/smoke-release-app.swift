import AppKit
import CoreGraphics
import Darwin
import Foundation

private enum ReleaseSmokeError: LocalizedError {
    case appExited(Int32)
    case appStayedRunning
    case invalidArguments
    case missingExecutable(String)
    case railWindowDidNotAppear
    case terminationWasRejected
    case unexpectedExit(Int32)

    var errorDescription: String? {
        switch self {
        case let .appExited(status):
            "extracted Pace app exited before its rail appeared with status \(status)"
        case .appStayedRunning:
            "extracted Pace app did not terminate after the smoke check"
        case .invalidArguments:
            "usage: smoke-release-app APP_BUNDLE STATE_DIRECTORY"
        case let .missingExecutable(path):
            "missing extracted Pace executable: \(path)"
        case .railWindowDidNotAppear:
            "extracted Pace app did not present a rail window"
        case .terminationWasRejected:
            "extracted Pace app rejected the termination request"
        case let .unexpectedExit(status):
            "extracted Pace app terminated with unexpected status \(status)"
        }
    }
}

@main
private enum ReleaseSmokeApp {
    @MainActor
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(
                Data("release smoke failed: \(error.localizedDescription)\n".utf8),
            )
            Foundation.exit(1)
        }
    }

    @MainActor
    private static func run() throws {
        guard CommandLine.arguments.count == 3 else {
            throw ReleaseSmokeError.invalidArguments
        }
        let appBundle = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
        let stateDirectory = URL(
            filePath: CommandLine.arguments[2],
            directoryHint: .isDirectory,
        )
        let executable = appBundle.appending(
            components: "Contents",
            "MacOS",
            "Pace",
        )
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ReleaseSmokeError.missingExecutable(executable.path)
        }
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true,
        )

        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["PACE_APPLICATION_SUPPORT_DIRECTORY"] = stateDirectory.path
        environment["PACE_REFERENCE_INTERACTION"] = "0"
        environment["PACE_REFERENCE_PREVIEW"] = "mini"
        environment["PACE_SIMULATED_STATE"] = "current"
        environment.removeValue(forKey: "PACE_REFERENCE_MENU")
        environment.removeValue(forKey: "PACE_REFERENCE_MOTION")
        environment.removeValue(forKey: "PACE_REFERENCE_SETTINGS")
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let processID = process.processIdentifier
        var terminationRequested = false
        defer {
            if process.isRunning {
                if !terminationRequested {
                    process.terminate()
                }
                wait(for: process, timeout: 2)
                if process.isRunning {
                    process.interrupt()
                    wait(for: process, timeout: 2)
                }
                if process.isRunning {
                    _ = Darwin.kill(processID, SIGKILL)
                    wait(for: process, timeout: 2)
                }
            }
        }

        let launchDeadline = Date().addingTimeInterval(10)
        var railBounds: CGRect?
        while Date() < launchDeadline {
            guard process.isRunning else {
                process.waitUntilExit()
                throw ReleaseSmokeError.appExited(process.terminationStatus)
            }
            if let bounds = railWindowBounds(for: processID) {
                railBounds = bounds
                break
            }
            runLoopStep()
        }
        guard let railBounds else {
            throw ReleaseSmokeError.railWindowDidNotAppear
        }

        let stabilityDeadline = Date().addingTimeInterval(0.5)
        while Date() < stabilityDeadline {
            guard process.isRunning else {
                process.waitUntilExit()
                throw ReleaseSmokeError.appExited(process.terminationStatus)
            }
            runLoopStep()
        }

        guard let application = NSRunningApplication(processIdentifier: processID),
              application.terminate()
        else {
            throw ReleaseSmokeError.terminationWasRejected
        }
        terminationRequested = true
        wait(for: process, timeout: 8)
        guard !process.isRunning else {
            throw ReleaseSmokeError.appStayedRunning
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ReleaseSmokeError.unexpectedExit(process.terminationStatus)
        }

        print("app_bundle=\(appBundle.path)")
        print("process_id=\(processID)")
        print(
            "rail_window=\(Int(railBounds.width))x\(Int(railBounds.height))"
                + "@\(Int(railBounds.minX)),\(Int(railBounds.minY))",
        )
        print("graceful_exit=true")
    }

    private static func railWindowBounds(for processID: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID,
        ) as? [[String: Any]] else {
            return nil
        }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 3,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue,
                  // A plausible rail, not an exact size. The canvas is derived
                  // from the detail panel's width and the provider row count,
                  // so pinning literals here made a deliberate layout change
                  // fail the release instead of the app. The app's own geometry
                  // owns those numbers; this only has to recognise the window.
                  width > 200, width < 600,
                  height > 300, height < 900,
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue
            else {
                continue
            }
            return CGRect(x: x, y: y, width: width, height: height)
        }
        return nil
    }

    private static func wait(for process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            runLoopStep()
        }
    }

    private static func runLoopStep() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}

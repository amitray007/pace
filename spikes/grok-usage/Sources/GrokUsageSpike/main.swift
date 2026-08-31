import CryptoKit
import Darwin
import Foundation
import GrokUsageSpikeCore

@main
struct GrokUsageSpikeCommand {
    static func main() async {
        do {
            let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            if arguments.showHelp {
                print(helpText)
                return
            }
            let profiles = arguments.grokHomes.isEmpty
                ? [GrokProfileBinding.defaultProfile]
                : arguments.grokHomes.map { GrokProfileBinding(grokHome: profileURL($0)) }
            let results = try await GrokUsageProbe().probeSequentially(profiles)
            for (index, result) in results.enumerated() {
                if index > 0 {
                    print("")
                }
                print("Profile \(index + 1): \(profiles[index].grokHome.lastPathComponent)")
                print("Identity: \(fingerprint(result.identity.stableKey))")
                print("Plan: \(result.planName ?? "Unknown")")
                for metric in result.metrics {
                    printMetric(metric)
                }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("Grok spike failed: \(message)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func parseArguments(_ arguments: [String]) throws -> Arguments {
        var grokHomes: [String] = []
        var showHelp = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--help", "-h":
                showHelp = true
                index += 1
            case "--grok-home":
                guard arguments.indices.contains(index + 1) else {
                    throw CommandError.missingProfilePath
                }
                grokHomes.append(arguments[index + 1])
                index += 2
            default:
                throw CommandError.unknownArgument(arguments[index])
            }
        }
        return Arguments(grokHomes: grokHomes, showHelp: showHelp)
    }

    private static func profileURL(_ path: String) -> URL {
        let expanded: String = if path == "~" {
            FileManager.default.homeDirectoryForCurrentUser.path
        } else if path.hasPrefix("~/") {
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: String(path.dropFirst(2)))
                .path
        } else {
            path
        }
        return URL(filePath: expanded, directoryHint: .isDirectory)
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func printMetric(_ metric: GrokMetric) {
        switch metric {
        case let .amount(amount):
            let used = NSDecimalNumber(decimal: amount.used).stringValue
            let limit = amount.limit.map { NSDecimalNumber(decimal: $0).stringValue }
            let limitText = limit.map { " / \($0)" } ?? ""
            let reset = amount.resetsAt.map { " · resets \($0.ISO8601Format())" } ?? ""
            print("\(amount.label): \(used)\(limitText) \(amount.unit)\(reset)")
        case let .percentage(percentage):
            let used = Int((percentage.usedFraction * 100).rounded())
            let reset = percentage.resetsAt.map { " · resets \($0.ISO8601Format())" } ?? ""
            print("\(percentage.label): \(used)%\(reset)")
        }
    }
}

private struct Arguments {
    let grokHomes: [String]
    let showHelp: Bool
}

private enum CommandError: Error, LocalizedError {
    case missingProfilePath
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingProfilePath:
            "--grok-home requires a Grok home-directory path."
        case let .unknownArgument(argument):
            "Unknown argument: \(argument)"
        }
    }
}

private let helpText = """
Usage: swift run grok-usage-spike [--grok-home <profile-home>]...

Each profile home must have been authenticated with GROK_HOME=<profile-home> grok login. The
command verifies the server account before requesting billing data. It never prints or changes
credentials, and it does not require Grok to remain running.
"""

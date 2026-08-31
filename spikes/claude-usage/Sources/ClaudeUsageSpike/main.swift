import ClaudeUsageSpikeCore
import CryptoKit
import Darwin
import Foundation

@main
struct ClaudeUsageSpikeCommand {
    static func main() async {
        do {
            let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            if arguments.showHelp {
                print(helpText)
                return
            }

            let profiles = arguments.profilePaths.isEmpty
                ? [ClaudeProfileBinding.defaultProfile]
                : arguments.profilePaths.map { path in
                    ClaudeProfileBinding(configDirectory: profileURL(path))
                }
            let results = try await ClaudeUsageProbe().probeSequentially(profiles)
            for (index, result) in results.enumerated() {
                if index > 0 {
                    print("")
                }
                print("Profile \(index + 1): \(profiles[index].configDirectory.lastPathComponent)")
                print("Identity: \(fingerprint(result.identity.stableKey))")
                print("Plan: \(result.planName ?? "Unknown")")
                print("Credential source: \(result.credentialSource.label)")
                for metric in result.metrics {
                    printMetric(metric)
                }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("Claude spike failed: \(message)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func parseArguments(_ arguments: [String]) throws -> Arguments {
        var paths: [String] = []
        var showHelp = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--help", "-h":
                showHelp = true
                index += 1
            case "--profile":
                guard arguments.indices.contains(index + 1) else {
                    throw CommandError.missingProfilePath
                }
                paths.append(arguments[index + 1])
                index += 2
            default:
                throw CommandError.unknownArgument(arguments[index])
            }
        }
        return Arguments(profilePaths: paths, showHelp: showHelp)
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

    private static func printMetric(_ metric: ClaudeMetric) {
        switch metric {
        case let .amount(amount):
            let value = NSDecimalNumber(decimal: amount.value).stringValue
            let limit = amount.limit.map { NSDecimalNumber(decimal: $0).stringValue }
            let limitText = limit.map { " / \($0)" } ?? ""
            print("\(amount.label): \(value)\(limitText) \(amount.unit)")
        case let .percentage(percentage):
            let used = Int((percentage.usedFraction * 100).rounded())
            let reset = percentage.resetsAt.map { " · resets \($0.ISO8601Format())" } ?? ""
            print("\(percentage.label): \(used)%\(reset)")
        }
    }
}

private struct Arguments {
    let profilePaths: [String]
    let showHelp: Bool
}

private enum CommandError: Error, LocalizedError {
    case missingProfilePath
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingProfilePath:
            "--profile requires a config-directory path."
        case let .unknownArgument(argument):
            "Unknown argument: \(argument)"
        }
    }
}

private let helpText = """
Usage: swift run claude-usage-spike [--profile <config-directory>]...

Reads each explicit Claude Code profile, verifies its OAuth identity, then fetches usage directly.
The command never prints tokens, email addresses, organization names, or raw account identifiers.
Profiles are checked sequentially to avoid aggressive polling of the compatibility endpoint.
"""

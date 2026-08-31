import CryptoKit
import Darwin
import Foundation
import GitHubCopilotUsageSpikeCore

@main
struct GitHubCopilotUsageSpikeCommand {
    static func main() async {
        do {
            let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            if arguments.showHelp {
                print(helpText)
                return
            }
            let profiles = try arguments.githubUsers.isEmpty
                ? GitHubCLIAccountDiscovery().profiles()
                : arguments.githubUsers.map { GitHubCopilotProfileBinding(githubLogin: $0) }
            let results = try await GitHubCopilotUsageProbe().probeSequentially(profiles)
            for (index, result) in results.enumerated() {
                if index > 0 {
                    print("")
                }
                print("Profile \(index + 1)")
                print("Identity: \(fingerprint(result.identity.stableKey))")
                print("Plan: \(result.planName ?? "Unknown")")
                if result.metrics.isEmpty, result.isOrganizationManaged {
                    print("Usage: organization-managed; no personal quota returned")
                }
                for metric in result.metrics {
                    printMetric(metric)
                }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("GitHub Copilot spike failed: \(message)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func parseArguments(_ arguments: [String]) throws -> Arguments {
        var githubUsers: [String] = []
        var showHelp = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--help", "-h":
                showHelp = true
                index += 1
            case "--github-user":
                guard arguments.indices.contains(index + 1) else {
                    throw CommandError.missingUser
                }
                githubUsers.append(arguments[index + 1])
                index += 2
            default:
                throw CommandError.unknownArgument(arguments[index])
            }
        }
        return Arguments(githubUsers: githubUsers, showHelp: showHelp)
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func printMetric(_ metric: GitHubCopilotMetric) {
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
    let githubUsers: [String]
    let showHelp: Bool
}

private enum CommandError: Error, LocalizedError {
    case missingUser
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingUser:
            "--github-user requires a GitHub.com login."
        case let .unknownArgument(argument):
            "Unknown argument: \(argument)"
        }
    }
}

private let helpText = """
Usage: swift run github-copilot-usage-spike [--github-user <login>]...

With no arguments, the command checks every authenticated GitHub.com account reported by GitHub
CLI. Every token read still uses an explicit --user binding; the active gh account is never used as
an implicit selector or changed. Output excludes logins, tokens, names, and raw identifiers.
"""

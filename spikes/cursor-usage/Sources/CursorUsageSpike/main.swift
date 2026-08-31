import CryptoKit
import CursorUsageSpikeCore
import Darwin
import Foundation

@main
struct CursorUsageSpikeCommand {
    static func main() async {
        do {
            let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            if arguments.showHelp {
                print(helpText)
                return
            }

            let profiles = arguments.profileHomes.isEmpty
                ? [CursorProfileBinding.defaultProfile]
                : arguments.profileHomes.map { path in
                    CursorProfileBinding.isolated(homeDirectory: profileURL(path))
                }
            let results = try await CursorUsageProbe().probeSequentially(profiles)
            for (index, result) in results.enumerated() {
                if index > 0 {
                    print("")
                }
                print("Profile \(index + 1): \(profileLabel(profiles[index]))")
                print("Identity: \(fingerprint(result.identity.stableKey))")
                print("Plan: \(result.planName ?? "Unknown")")
                print("Credential source: \(result.credentialSource.label)")
                for metric in result.metrics {
                    printMetric(metric)
                }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("Cursor spike failed: \(message)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func parseArguments(_ arguments: [String]) throws -> Arguments {
        var profileHomes: [String] = []
        var showHelp = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--help", "-h":
                showHelp = true
                index += 1
            case "--profile-home":
                guard arguments.indices.contains(index + 1) else {
                    throw CommandError.missingProfilePath
                }
                profileHomes.append(arguments[index + 1])
                index += 2
            default:
                throw CommandError.unknownArgument(arguments[index])
            }
        }
        return Arguments(profileHomes: profileHomes, showHelp: showHelp)
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

    private static func profileLabel(_ profile: CursorProfileBinding) -> String {
        switch profile.credentialStore {
        case .defaultKeychain:
            "default"
        case .isolatedFile:
            profile.homeDirectory.lastPathComponent
        }
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func printMetric(_ metric: CursorMetric) {
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
    let profileHomes: [String]
    let showHelp: Bool
}

private enum CommandError: Error, LocalizedError {
    case missingProfilePath
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingProfilePath:
            "--profile-home requires an isolated home-directory path."
        case let .unknownArgument(argument):
            "Unknown argument: \(argument)"
        }
    }
}

private let helpText = """
Usage: swift run cursor-usage-spike [--profile-home <isolated-home>]...

With no profile, verifies the default Cursor Agent login through its server-side status command,
then reads the Cursor Agent Keychain access token and fetches current usage. Each explicit profile
must have been logged in with Cursor Agent's isolated file credential store. The command never
reads Cursor Desktop SQLite state or browser cookies, and never prints tokens or account details.
"""

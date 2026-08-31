import Foundation

public struct GitHubCLIOutput: Equatable, Sendable {
    public let status: Int32
    public let stdout: Data

    public init(status: Int32, stdout: Data) {
        self.status = status
        self.stdout = stdout
    }
}

public protocol GitHubCLIExecuting: Sendable {
    func run(arguments: [String], environment: [String: String]) throws -> GitHubCLIOutput
}

public struct GitHubCLIExecutor: GitHubCLIExecuting {
    private static let maximumOutputSize = 1_048_576
    private let executableURL: URL?

    public init(
        executableURL: URL? = Self.findExecutable(
            environment: ProcessInfo.processInfo.environment,
        ),
    ) {
        self.executableURL = executableURL
    }

    public func run(arguments: [String], environment: [String: String]) throws -> GitHubCLIOutput {
        guard let executableURL else {
            throw GitHubCopilotSpikeError.cliUnavailable
        }
        let output = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw GitHubCopilotSpikeError.cliFailed
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard data.count <= Self.maximumOutputSize else {
            throw GitHubCopilotSpikeError.cliFailed
        }
        return GitHubCLIOutput(status: process.terminationStatus, stdout: data)
    }

    public static func findExecutable(environment: [String: String]) -> URL? {
        var candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        candidates += (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/gh" }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(filePath: path)
        }
        return nil
    }
}

public protocol GitHubCopilotCredentialLoading: Sendable {
    func load(for profile: GitHubCopilotProfileBinding) throws -> GitHubCopilotCredential
}

public struct GitHubCLICredentialLoader: GitHubCopilotCredentialLoading {
    private let executor: any GitHubCLIExecuting
    private let baseEnvironment: [String: String]

    public init(
        executor: any GitHubCLIExecuting = GitHubCLIExecutor(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
    ) {
        self.executor = executor
        self.baseEnvironment = baseEnvironment
    }

    public func load(for profile: GitHubCopilotProfileBinding) throws -> GitHubCopilotCredential {
        guard Self.isValidLogin(profile.githubLogin) else {
            throw GitHubCopilotSpikeError.invalidProfile
        }
        let output = try executor.run(
            arguments: [
                "auth", "token",
                "--hostname", "github.com",
                "--user", profile.githubLogin,
            ],
            environment: Self.environment(for: profile, inheriting: baseEnvironment),
        )
        guard output.status == 0 else {
            throw GitHubCopilotSpikeError.signedOut
        }
        guard let value = String(data: output.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            !value.contains(charactersIn: .newlines)
        else {
            throw GitHubCopilotSpikeError.invalidCredential
        }
        return GitHubCopilotCredential(token: value)
    }

    static func environment(
        for profile: GitHubCopilotProfileBinding,
        inheriting base: [String: String],
    ) -> [String: String] {
        var environment = base
        for key in ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GH_CONFIG_DIR"] {
            environment.removeValue(forKey: key)
        }
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        if let configDirectory = profile.configDirectory {
            environment["GH_CONFIG_DIR"] = configDirectory.path
        }
        return environment
    }

    static func isValidLogin(_ login: String) -> Bool {
        guard (1 ... 39).contains(login.count),
              login.first != "-",
              login.last != "-"
        else {
            return false
        }
        return login.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}

public struct GitHubCLIAccountDiscovery: Sendable {
    private let executor: any GitHubCLIExecuting
    private let baseEnvironment: [String: String]
    private let configDirectory: URL?

    public init(
        executor: any GitHubCLIExecuting = GitHubCLIExecutor(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        configDirectory: URL? = nil,
    ) {
        self.executor = executor
        self.baseEnvironment = baseEnvironment
        self.configDirectory = configDirectory
    }

    public func profiles() throws -> [GitHubCopilotProfileBinding] {
        let seed = GitHubCopilotProfileBinding(
            githubLogin: "discovery",
            configDirectory: configDirectory,
        )
        let output = try executor.run(
            arguments: [
                "auth", "status",
                "--hostname", "github.com",
                "--json", "hosts",
            ],
            environment: GitHubCLICredentialLoader.environment(
                for: seed,
                inheriting: baseEnvironment,
            ),
        )
        let document: StatusDocument
        do {
            document = try JSONDecoder().decode(StatusDocument.self, from: output.stdout)
        } catch {
            throw GitHubCopilotSpikeError.cliFailed
        }
        let profiles = (document.hosts["github.com"] ?? [])
            .filter { $0.state == "success" && GitHubCLICredentialLoader.isValidLogin($0.login) }
            .map {
                GitHubCopilotProfileBinding(
                    githubLogin: $0.login,
                    configDirectory: configDirectory,
                )
            }
            .sorted {
                $0.githubLogin.localizedCaseInsensitiveCompare($1.githubLogin) == .orderedAscending
            }
        guard !profiles.isEmpty else {
            throw GitHubCopilotSpikeError.signedOut
        }
        return profiles
    }
}

private struct StatusDocument: Decodable {
    let hosts: [String: [StatusAccount]]
}

private struct StatusAccount: Decodable {
    let login: String
    let state: String
}

private extension String {
    func contains(charactersIn set: CharacterSet) -> Bool {
        rangeOfCharacter(from: set) != nil
    }
}

import Darwin
import Foundation

struct GitHubCLIOutput: Equatable, Sendable {
    let status: Int32
    let stdout: Data
}

protocol GitHubCLIExecuting: Sendable {
    func run(arguments: [String], environment: [String: String]) async throws -> GitHubCLIOutput
}

struct GitHubCLIExecutor: GitHubCLIExecuting {
    private static let maximumOutputSize = 1_048_576
    private let executableURL: URL?
    private let timeout: TimeInterval

    init(
        executableURL: URL? = Self.findExecutable(
            environment: ProcessInfo.processInfo.environment,
        ),
        timeout: TimeInterval = 10,
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func run(
        arguments: [String],
        environment: [String: String],
    ) async throws -> GitHubCLIOutput {
        guard let executableURL else {
            throw GitHubCopilotProviderError.cliUnavailable
        }
        let invocation = GitHubCLIInvocation(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            timeout: timeout,
            maximumOutputSize: Self.maximumOutputSize,
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                invocation.start(continuation)
            }
        } onCancel: {
            invocation.cancel()
        }
    }

    static func findExecutable(environment: [String: String]) -> URL? {
        var candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        candidates += (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/gh" }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath()
        }
        return nil
    }
}

protocol GitHubCopilotCredentialLoading: Sendable {
    func load(for profile: GitHubCopilotProfile) async throws -> GitHubCopilotCredential
}

struct GitHubCLICredentialLoader: GitHubCopilotCredentialLoading {
    private let executor: any GitHubCLIExecuting
    private let baseEnvironment: [String: String]

    init(
        executor: any GitHubCLIExecuting = GitHubCLIExecutor(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
    ) {
        self.executor = executor
        self.baseEnvironment = baseEnvironment
    }

    func load(for profile: GitHubCopilotProfile) async throws -> GitHubCopilotCredential {
        guard Self.isValidLogin(profile.githubLogin) else {
            throw GitHubCopilotProviderError.invalidProfile
        }
        let output = try await executor.run(
            arguments: [
                "auth", "token",
                "--hostname", "github.com",
                "--user", profile.githubLogin,
            ],
            environment: Self.environment(for: profile, inheriting: baseEnvironment),
        )
        guard output.status == 0 else {
            throw GitHubCopilotProviderError.signedOut
        }
        guard let token = String(data: output.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty,
            token.rangeOfCharacter(from: .newlines) == nil
        else {
            throw GitHubCopilotProviderError.invalidCredential
        }
        return GitHubCopilotCredential(token: token)
    }

    static func environment(
        for profile: GitHubCopilotProfile,
        inheriting base: [String: String],
    ) -> [String: String] {
        var environment = base
        for key in [
            "GH_TOKEN",
            "GITHUB_TOKEN",
            "GH_ENTERPRISE_TOKEN",
            "GITHUB_ENTERPRISE_TOKEN",
            "GH_CONFIG_DIR",
            "GH_HOST",
        ] {
            environment.removeValue(forKey: key)
        }
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        if let configurationDirectory = profile.configurationDirectory {
            environment["GH_CONFIG_DIR"] = configurationDirectory.path
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
        return login.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
        }
    }
}

struct GitHubCLIAccountDiscovery: Sendable {
    private let executor: any GitHubCLIExecuting
    private let baseEnvironment: [String: String]
    private let configurationDirectory: URL?

    init(
        executor: any GitHubCLIExecuting = GitHubCLIExecutor(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        configurationDirectory: URL? = nil,
    ) {
        self.executor = executor
        self.baseEnvironment = baseEnvironment
        self.configurationDirectory = configurationDirectory
    }

    func profiles() async throws -> [GitHubCopilotProfile] {
        let seed = GitHubCopilotProfile(
            githubLogin: "discovery",
            configurationDirectory: configurationDirectory,
        )
        let output = try await executor.run(
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
        let document: GitHubCLIStatusDocument
        do {
            document = try JSONDecoder().decode(GitHubCLIStatusDocument.self, from: output.stdout)
        } catch {
            throw GitHubCopilotProviderError.cliFailed
        }
        let profiles = (document.hosts["github.com"] ?? [])
            .filter {
                $0.state == "success" && GitHubCLICredentialLoader.isValidLogin($0.login)
            }
            .map {
                GitHubCopilotProfile(
                    githubLogin: $0.login,
                    configurationDirectory: configurationDirectory,
                )
            }
            .sorted {
                $0.githubLogin.localizedCaseInsensitiveCompare($1.githubLogin) == .orderedAscending
            }
        guard !profiles.isEmpty else {
            throw GitHubCopilotProviderError.signedOut
        }
        return profiles
    }
}

private struct GitHubCLIStatusDocument: Decodable {
    let hosts: [String: [GitHubCLIStatusAccount]]
}

private struct GitHubCLIStatusAccount: Decodable {
    let login: String
    let state: String
}

private final class GitHubCLIInvocation: @unchecked Sendable {
    private static let workQueue = DispatchQueue(
        label: "app.pace.github-cli.work",
        qos: .utility,
        attributes: .concurrent,
    )
    private static let timerQueue = DispatchQueue(label: "app.pace.github-cli.timer")

    private let executableURL: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let lock = NSLock()
    private let maximumOutputSize: Int
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<GitHubCLIOutput, any Error>?
    private var isCancelled = false
    private var outputHandle: FileHandle?
    private var process: Process?
    private var timeoutWorkItem: DispatchWorkItem?

    init(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        maximumOutputSize: Int,
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.timeout = timeout
        self.maximumOutputSize = maximumOutputSize
    }

    func start(_ continuation: CheckedContinuation<GitHubCLIOutput, any Error>) {
        let shouldStart = lock.withLock { () -> Bool in
            guard !isCancelled else {
                return false
            }
            self.continuation = continuation
            return true
        }
        guard shouldStart else {
            continuation.resume(throwing: GitHubCopilotProviderError.cliFailed)
            return
        }
        Self.workQueue.async { [self] in execute() }
    }

    func cancel() {
        let resources = lock.withLock { () -> (Process?, FileHandle?) in
            isCancelled = true
            return (process, outputHandle)
        }
        terminate(resources.0)
        try? resources.1?.close()
        finish(.failure(GitHubCopilotProviderError.cliFailed))
    }

    private func execute() {
        let output = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let shouldRun = lock.withLock { () -> Bool in
            guard !isCancelled, continuation != nil else {
                return false
            }
            self.process = process
            outputHandle = output.fileHandleForReading
            return true
        }
        guard shouldRun else {
            finish(.failure(GitHubCopilotProviderError.cliFailed))
            return
        }

        do {
            try process.run()
        } catch {
            finish(.failure(GitHubCopilotProviderError.cliFailed))
            return
        }
        scheduleTimeout()
        let data: Data
        do {
            data = try readBoundedOutput(from: output.fileHandleForReading)
        } catch {
            terminate(process)
            finish(.failure(GitHubCopilotProviderError.cliFailed))
            return
        }
        process.waitUntilExit()
        let wasCancelled = lock.withLock { isCancelled }
        guard !wasCancelled else {
            finish(.failure(GitHubCopilotProviderError.cliFailed))
            return
        }
        finish(.success(GitHubCLIOutput(status: process.terminationStatus, stdout: data)))
    }

    private func readBoundedOutput(from handle: FileHandle) throws -> Data {
        var data = Data()
        data.reserveCapacity(min(maximumOutputSize, 65536))
        while data.count <= maximumOutputSize {
            let remaining = maximumOutputSize + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(remaining, 65536)),
                  !chunk.isEmpty
            else {
                return data
            }
            data.append(chunk)
        }
        throw GitHubCopilotProviderError.cliFailed
    }

    private func scheduleTimeout() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.cancel()
        }
        let shouldSchedule = lock.withLock { () -> Bool in
            guard continuation != nil else {
                return false
            }
            timeoutWorkItem = workItem
            return true
        }
        guard shouldSchedule else {
            return
        }
        Self.timerQueue.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func terminate(_ process: Process?) {
        guard let process, process.isRunning else {
            return
        }
        process.terminate()
        let processID = process.processIdentifier
        Self.timerQueue.asyncAfter(deadline: .now() + 0.5) {
            if process.isRunning {
                Darwin.kill(processID, SIGKILL)
            }
        }
    }

    private func finish(_ result: Result<GitHubCLIOutput, any Error>) {
        let completion = lock.withLock {
            () -> (CheckedContinuation<GitHubCLIOutput, any Error>, FileHandle?)? in
            guard let continuation else {
                return nil
            }
            self.continuation = nil
            let handle = outputHandle
            process = nil
            outputHandle = nil
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            return (continuation, handle)
        }
        try? completion?.1?.close()
        completion?.0.resume(with: result)
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () -> Result) -> Result {
        lock()
        defer { unlock() }
        return operation()
    }
}

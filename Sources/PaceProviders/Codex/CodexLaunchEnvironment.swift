import Foundation

/// Builds the environment for a `codex app-server` child process.
///
/// A GUI application launched by launchd receives a minimal `PATH`
/// (`/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`). Codex installed through npm is usually a
/// `#!/usr/bin/env node` script reached through a symbolic-link chain such as
/// `~/.local/bin/codex -> <prefix>/bin/codex -> ../lib/node_modules/@openai/codex/bin/codex.js`,
/// with `node` stored beside one of those links. Prepending every directory in that chain lets
/// `env` find the runtime without reading the user's shell configuration.
enum CodexLaunchEnvironment {
    private static let maximumLinkDepth = 16

    static func environment(
        executableURL: URL,
        profileDirectory: URL,
        base: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
    ) -> [String: String] {
        var environment = base
        environment["CODEX_HOME"] = profileDirectory.standardizedFileURL.path
        environment["PATH"] = searchPath(
            executableURL: executableURL,
            basePath: base["PATH"],
            fileManager: fileManager,
        )
        return environment
    }

    static func searchPath(
        executableURL: URL,
        basePath: String?,
        fileManager: FileManager = .default,
    ) -> String {
        let linkDirectories = symbolicLinkChain(from: executableURL, fileManager: fileManager)
            .map { $0.deletingLastPathComponent().standardizedFileURL.path }
        let baseDirectories = (basePath ?? "")
            .split(separator: ":")
            .map(String.init)
        var seen = Set<String>()
        return (linkDirectories + baseDirectories)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
    }

    /// Every path in the symbolic-link chain, starting with the requested executable.
    static func symbolicLinkChain(
        from executableURL: URL,
        fileManager: FileManager = .default,
    ) -> [URL] {
        var current = executableURL.standardizedFileURL
        var chain = [current]
        for _ in 0 ..< maximumLinkDepth {
            guard let destination = try? fileManager.destinationOfSymbolicLink(
                atPath: current.path,
            ) else {
                break
            }
            let next = destination.hasPrefix("/")
                ? URL(filePath: destination)
                : current.deletingLastPathComponent().appending(path: destination)
            current = next.standardizedFileURL
            chain.append(current)
        }
        return chain
    }
}

import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Codex launch environment")
struct CodexLaunchEnvironmentTests {
    @Test
    func `prepends every directory in the executable symlink chain`() throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }
        let layout = try CodexNodeShimLayout(fixture: fixture)

        let path = CodexLaunchEnvironment.searchPath(
            executableURL: layout.executableURL,
            basePath: "/usr/bin:/bin:\(layout.prefixBin.path)",
        )

        #expect(path == [
            layout.localBin.path,
            layout.prefixBin.path,
            layout.scriptDirectory.path,
            "/usr/bin",
            "/bin",
        ].joined(separator: ":"))
    }

    @Test
    func `keeps a plain executable path and replaces CODEX_HOME`() throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }

        let environment = CodexLaunchEnvironment.environment(
            executableURL: fixture.executableURL,
            profileDirectory: fixture.profile.directory,
            base: ["PATH": "/usr/bin", "CODEX_HOME": "/elsewhere", "LANG": "C"],
        )

        #expect(environment["PATH"] == "\(fixture.directory.standardizedFileURL.path):/usr/bin")
        #expect(environment["CODEX_HOME"] == fixture.profile.directory.standardizedFileURL.path)
        #expect(environment["LANG"] == "C")
    }

    @Test
    func `starts an env-script codex whose runtime lives beside its symlink`() async throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }
        let layout = try CodexNodeShimLayout(fixture: fixture)
        let reader = CodexAppServerReader(
            executableURL: layout.executableURL,
            timeout: 3,
            reconnectDelays: [.milliseconds(10)],
        )
        defer { Task { await reader.shutdown() } }

        let snapshot = try await reader.read(profile: fixture.profile, includeRateLimits: true)

        #expect(snapshot.account.account?.email == "person@example.invalid")
        #expect(snapshot.rateLimits?.rateLimits.primary?.usedPercent == 21)
        #expect(try fixture.startCount() == 1)
    }

    @Test
    func `reports a missing script runtime as executable unavailable`() async throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }
        let script = "#!/usr/bin/env pace-missing-runtime-\(UUID().uuidString)\nexit 0\n"
        let executableURL = fixture.directory.appending(path: "codex-without-runtime")
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executableURL.path,
        )
        let reader = CodexAppServerReader(
            executableURL: executableURL,
            timeout: 3,
            reconnectDelays: [.milliseconds(10)],
        )

        do {
            _ = try await reader.read(profile: fixture.profile, includeRateLimits: false)
            Issue.record("Expected the unavailable runtime to fail the read")
        } catch {
            #expect(error == .executableUnavailable)
        }
    }
}

/// Mirrors an npm global install: `~/.local/bin/codex -> <prefix>/bin/codex ->
/// ../lib/node_modules/codex/bin/codex.js`, where `codex.js` is a `#!/usr/bin/env` script and the
/// runtime it needs lives only in `<prefix>/bin`.
private struct CodexNodeShimLayout {
    let executableURL: URL
    let localBin: URL
    let prefixBin: URL
    let scriptDirectory: URL

    init(fixture: CodexServerFixture) throws {
        let fileManager = FileManager.default
        let root = fixture.directory.standardizedFileURL
        localBin = root.appending(path: "home/.local/bin", directoryHint: .isDirectory)
        prefixBin = root.appending(path: "prefix/bin", directoryHint: .isDirectory)
        scriptDirectory = root.appending(
            path: "prefix/lib/node_modules/codex/bin",
            directoryHint: .isDirectory,
        )
        for directory in [localBin, prefixBin, scriptDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let runtimeName = "pace-fake-node"
        let original = try String(contentsOf: fixture.executableURL, encoding: .utf8)
        let body = original
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .dropFirst()
            .joined()
        let script = scriptDirectory.appending(path: "codex.js")
        try "#!/usr/bin/env \(runtimeName)\n\(body)".write(
            to: script,
            atomically: true,
            encoding: .utf8,
        )
        let runtime = prefixBin.appending(path: runtimeName)
        try "#!/bin/zsh\nexec /bin/zsh \"$@\"\n".write(
            to: runtime,
            atomically: true,
            encoding: .utf8,
        )
        for file in [script, runtime] {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }

        try fileManager.createSymbolicLink(
            atPath: prefixBin.appending(path: "codex").path,
            withDestinationPath: "../lib/node_modules/codex/bin/codex.js",
        )
        executableURL = localBin.appending(path: "codex")
        try fileManager.createSymbolicLink(
            atPath: executableURL.path,
            withDestinationPath: prefixBin.appending(path: "codex").path,
        )
    }
}

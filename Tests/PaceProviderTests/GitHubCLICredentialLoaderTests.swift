import Foundation
@testable import PaceProviders
import Testing

@Suite("GitHub CLI account credentials")
struct GitHubCLICredentialLoaderTests {
    @Test
    func `loads only selected login and clears ambient overrides`() async throws {
        let executor = GitHubCLIStubExecutor(result: .success(GitHubCLIOutput(
            status: 0,
            stdout: Data("selected-token\n".utf8),
        )))
        let loader = GitHubCLICredentialLoader(
            executor: executor,
            baseEnvironment: [
                "GH_TOKEN": "ambient-gh",
                "GITHUB_TOKEN": "ambient-github",
                "GH_CONFIG_DIR": "/ambient",
                "PATH": "/usr/bin",
            ],
        )
        let directory = URL(filePath: "/profiles/gh-work", directoryHint: .isDirectory)

        let credential = try await loader.load(for: GitHubCopilotTestSupport.profile(
            "work-account",
            configurationDirectory: directory,
        ))
        let invocation = try #require(await executor.invocations.first)

        #expect(credential.token == "selected-token")
        #expect(invocation.arguments == [
            "auth", "token", "--hostname", "github.com", "--user", "work-account",
        ])
        #expect(invocation.environment["GH_TOKEN"] == nil)
        #expect(invocation.environment["GITHUB_TOKEN"] == nil)
        #expect(invocation.environment["GH_CONFIG_DIR"] == directory.path)
        #expect(invocation.environment["GH_PROMPT_DISABLED"] == "1")
    }

    @Test
    func `discovers all healthy accounts and ignores unhealthy records`() async throws {
        let executor = GitHubCLIStubExecutor(result: .success(GitHubCLIOutput(
            status: 1,
            stdout: Data(
                """
                {"hosts":{"github.com":[
                  {"login":"work","state":"success"},
                  {"login":"signed-out","state":"failure"},
                  {"login":"Personal","state":"success"}
                ]}}
                """.utf8,
            ),
        )))

        let profiles = try await GitHubCLIAccountDiscovery(
            executor: executor,
            baseEnvironment: [:],
        ).profiles()

        #expect(profiles.map(\.githubLogin) == ["Personal", "work"])
    }

    @Test
    func `rejects invalid login before invoking git hub CLI`() async {
        let executor = GitHubCLIStubExecutor(result: .failure(.cliFailed))
        let loader = GitHubCLICredentialLoader(executor: executor, baseEnvironment: [:])

        await #expect(throws: GitHubCopilotProviderError.invalidProfile) {
            try await loader.load(for: GitHubCopilotTestSupport.profile("bad login"))
        }
        #expect(await executor.invocations.isEmpty)
    }

    @Test
    func `terminates command that exceeds timeout`() async {
        let executor = GitHubCLIExecutor(
            executableURL: URL(filePath: "/bin/sh"),
            timeout: 0.05,
        )

        await #expect(throws: GitHubCopilotProviderError.cliFailed) {
            _ = try await executor.run(
                arguments: ["-c", "sleep 2"],
                environment: ProcessInfo.processInfo.environment,
            )
        }
    }

    @Test
    func `timeout is not held open by descendant pipe writer`() async {
        let executor = GitHubCLIExecutor(
            executableURL: URL(filePath: "/bin/sh"),
            timeout: 0.05,
        )
        let clock = ContinuousClock()
        let startedAt = clock.now

        await #expect(throws: GitHubCopilotProviderError.cliFailed) {
            _ = try await executor.run(
                arguments: ["-c", "trap '' HUP; sleep 2 & exit 0"],
                environment: ProcessInfo.processInfo.environment,
            )
        }
        #expect(startedAt.duration(to: clock.now) < .seconds(1))
    }

    @Test
    func `rejects output as soon as it exceeds the bound`() async {
        let executor = GitHubCLIExecutor(
            executableURL: URL(filePath: "/usr/bin/yes"),
            timeout: 2,
        )
        let clock = ContinuousClock()
        let startedAt = clock.now

        await #expect(throws: GitHubCopilotProviderError.cliFailed) {
            _ = try await executor.run(
                arguments: [],
                environment: ProcessInfo.processInfo.environment,
            )
        }
        #expect(startedAt.duration(to: clock.now) < .seconds(1))
    }
}

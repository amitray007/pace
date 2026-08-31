import Foundation
@testable import GitHubCopilotUsageSpikeCore
import Testing

@Suite("GitHub CLI account binding")
struct GitHubCLICredentialLoaderTests {
    @Test
    func `loads an explicit user and removes ambient token overrides`() throws {
        let executor = StubGitHubCLIExecutor(stdout: "gho_redacted\n")
        let profile = GitHubCopilotProfileBinding(
            githubLogin: "octocat",
            configDirectory: URL(filePath: "/profiles/work"),
        )
        let loader = GitHubCLICredentialLoader(
            executor: executor,
            baseEnvironment: [
                "GH_TOKEN": "wrong",
                "GITHUB_TOKEN": "wrong",
                "GH_CONFIG_DIR": "/wrong",
                "PATH": "/bin",
            ],
        )

        let credential = try loader.load(for: profile)
        let invocation = executor.invocations()
        let expectedArguments = [
            "auth", "token", "--hostname", "github.com", "--user", "octocat",
        ]

        #expect(credential.token == "gho_redacted")
        #expect(invocation.arguments == [expectedArguments])
        #expect(invocation.environments[0]["GH_TOKEN"] == nil)
        #expect(invocation.environments[0]["GITHUB_TOKEN"] == nil)
        #expect(invocation.environments[0]["GH_CONFIG_DIR"] == "/profiles/work")
        #expect(invocation.environments[0]["GH_PROMPT_DISABLED"] == "1")
    }

    @Test
    func `rejects invalid login before invoking gh`() {
        let executor = StubGitHubCLIExecutor(stdout: "should-not-be-read")
        let loader = GitHubCLICredentialLoader(executor: executor)

        #expect(throws: GitHubCopilotSpikeError.invalidProfile) {
            try loader.load(for: GitHubCopilotProfileBinding(githubLogin: "--help"))
        }
        #expect(executor.invocations().arguments.isEmpty)
    }

    @Test
    func `discovers every successful github dot com account`() throws {
        let executor = StubGitHubCLIExecutor(
            status: 1,
            stdout: """
            {
              "hosts": {
                "github.com": [
                  {"login":"work-user","state":"success"},
                  {"login":"expired-user","state":"failure"},
                  {"login":"Personal-User","state":"success"}
                ],
                "enterprise.example": [
                  {"login":"enterprise-user","state":"success"}
                ]
              }
            }
            """,
        )

        let profiles = try GitHubCLIAccountDiscovery(executor: executor).profiles()

        #expect(profiles.map(\.githubLogin) == ["Personal-User", "work-user"])
        #expect(executor.invocations().arguments[0] == [
            "auth", "status", "--hostname", "github.com", "--json", "hosts",
        ])
    }

    @Test
    func `reports signed out when discovery has no healthy account`() {
        let executor = StubGitHubCLIExecutor(stdout: #"{"hosts":{"github.com":[]}}"#)

        #expect(throws: GitHubCopilotSpikeError.signedOut) {
            try GitHubCLIAccountDiscovery(executor: executor).profiles()
        }
    }
}

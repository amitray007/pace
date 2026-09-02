import Darwin
import Foundation
import PaceCore
@testable import PaceProviders
import Testing

@Suite("Codex persistent app-server session")
struct CodexAppServerSessionTests {
    @Test
    func `reuses one process and forwards rate-limit notifications`() async throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }
        let reader = CodexAppServerReader(
            executableURL: fixture.executableURL,
            timeout: 10,
            reconnectDelays: [.milliseconds(10)],
        )
        let events = try await reader.events(for: fixture.profile)
        let rateLimitEvent = Task<CodexProfileEvent?, Never> {
            for await event in events where event == .rateLimitsChanged {
                return event
            }
            return nil
        }

        let first = try await reader.read(profile: fixture.profile, includeRateLimits: true)
        let second = try await reader.read(profile: fixture.profile, includeRateLimits: true)
        let event = try await taskValue(rateLimitEvent)
        let startCount = try fixture.startCount()

        #expect(first.account.account?.email == "person@example.invalid")
        #expect(second.rateLimits?.rateLimits.primary?.usedPercent == 21)
        #expect(event == .rateLimitsChanged)
        #expect(startCount == 1)
    }

    @Test
    func `reports exit and reconnects with bounded backoff`() async throws {
        let fixture = try CodexServerFixture(exitsAfterRateLimitRead: true)
        defer { fixture.remove() }
        // This asserts that a dropped session reconnects, not how quickly it
        // does. The fixture is a zsh script, so a run has to spawn a shell,
        // let it exit, and spawn it again; on a loaded machine that exceeded a
        // two-second budget often enough to fail roughly one run in three.
        let reader = CodexAppServerReader(
            executableURL: fixture.executableURL,
            timeout: 10,
            reconnectDelays: [.milliseconds(10)],
        )
        let events = try await reader.events(for: fixture.profile)
        let reconnectEvents = Task<[CodexProfileEvent], Never> {
            var observed: [CodexProfileEvent] = []
            for await event in events {
                observed.append(event)
                if event == .reconnected {
                    return observed
                }
            }
            return observed
        }

        _ = try await reader.read(profile: fixture.profile, includeRateLimits: true)
        let observed = try await taskValue(reconnectEvents)
        let startCount = try fixture.startCount()

        #expect(observed.contains(.connectionFailed))
        #expect(observed.last == .reconnected)
        #expect(startCount == 2)
    }

    @Test
    func `starts independent profiles without cross-account blocking`() async throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }
        let secondProfile = try fixture.makeProfile(named: "second")
        try Data(secondProfile.directory.path.utf8).write(
            to: fixture.profile.directory.appending(path: "wait-for-peer"),
        )
        let reader = CodexAppServerReader(
            executableURL: fixture.executableURL,
            timeout: 10,
            reconnectDelays: [.milliseconds(10)],
        )

        async let first = reader.read(profile: fixture.profile, includeRateLimits: true)
        async let second = reader.read(profile: secondProfile, includeRateLimits: true)
        let snapshots = try await [first, second]

        #expect(snapshots[0].account.account?.email == "person@example.invalid")
        #expect(snapshots[1].account.account?.email == "second@example.invalid")
        #expect(snapshots[0].rateLimits?.rateLimits.primary?.usedPercent == 21)
        #expect(snapshots[1].rateLimits?.rateLimits.primary?.usedPercent == 42)
        #expect(try fixture.startCount(for: fixture.profile) == 1)
        #expect(try fixture.startCount(for: secondProfile) == 1)
    }

    @Test
    func `coalesces a notification received before event subscription`() async throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }
        let reader = CodexAppServerReader(
            executableURL: fixture.executableURL,
            timeout: 10,
            reconnectDelays: [.milliseconds(10)],
        )

        _ = try await reader.read(profile: fixture.profile, includeRateLimits: true)
        let events = try await reader.events(for: fixture.profile)
        let pendingEvent = Task<CodexProfileEvent?, Never> {
            for await event in events where event == .rateLimitsChanged {
                return event
            }
            return nil
        }

        #expect(try await taskValue(pendingEvent) == .rateLimitsChanged)
        #expect(try fixture.startCount() == 1)
    }

    @Test
    func `force reaps a profile process that ignores termination`() async throws {
        let fixture = try CodexServerFixture(ignoresTermination: true)
        defer { fixture.remove() }
        let connection = try await CodexAppServerConnection.open(
            executableURL: fixture.executableURL,
            profileDirectory: fixture.profile.directory,
            requestTimeout: 2,
        )
        let pid = try fixture.processID()

        await connection.close()

        try await waitUntil {
            !fixture.processIsRunning(pid)
        }
    }

    @Test
    func `cancelling profile monitoring closes its cached process`() async throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }
        let reader = CodexAppServerReader(
            executableURL: fixture.executableURL,
            timeout: 10,
            reconnectDelays: [.milliseconds(10)],
        )
        let events = try await reader.events(for: fixture.profile)
        let collector = Task {
            for await _ in events {}
        }
        try await waitUntil {
            fixture.processIDIfPresent() != nil
        }
        let pid = try fixture.processID()

        collector.cancel()
        _ = try await taskValue(collector)
        try await waitUntil {
            !fixture.processIsRunning(pid)
        }
    }

    @Test
    func `explicit shutdown closes a cached profile process without a monitor`() async throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }
        let reader = CodexAppServerReader(
            executableURL: fixture.executableURL,
            timeout: 10,
            reconnectDelays: [.milliseconds(10)],
        )
        _ = try await reader.read(profile: fixture.profile, includeRateLimits: false)
        let processID = try fixture.processID()
        #expect(fixture.processIsRunning(processID))

        await reader.shutdown()

        try await waitUntil { !fixture.processIsRunning(processID) }
    }

    @Test
    func `shutdown is terminal and cannot restart a profile process`() async throws {
        let fixture = try CodexServerFixture()
        defer { fixture.remove() }
        let reader = CodexAppServerReader(
            executableURL: fixture.executableURL,
            timeout: 10,
            reconnectDelays: [.milliseconds(10)],
        )
        _ = try await reader.read(profile: fixture.profile, includeRateLimits: false)
        let processID = try fixture.processID()

        await reader.shutdown()
        try await waitUntil { !fixture.processIsRunning(processID) }

        do {
            _ = try await reader.read(profile: fixture.profile, includeRateLimits: false)
            Issue.record("Expected a reader to reject work after shutdown")
        } catch {
            #expect(error == .processFailed)
        }
        #expect(try fixture.startCount() == 1)
    }

    @Test
    func `request timeout does not stall unrelated async work`() async throws {
        let fixture = try CodexServerFixture(omitsAccountResponse: true)
        defer { fixture.remove() }
        let reader = CodexAppServerReader(
            executableURL: fixture.executableURL,
            timeout: 0.1,
            reconnectDelays: [.milliseconds(10)],
        )
        let readTask = Task<Result<CodexProfileSnapshot, CodexProviderError>, Never> {
            do {
                return try await .success(
                    reader.read(
                        profile: fixture.profile,
                        includeRateLimits: false,
                    ),
                )
            } catch let error as CodexProviderError {
                return .failure(error)
            } catch {
                return .failure(.processFailed)
            }
        }
        let heartbeat = Task {
            try? await Task.sleep(for: .milliseconds(20))
            return true
        }

        #expect(try await taskValue(heartbeat, within: .milliseconds(100)))
        let result = try await taskValue(readTask, within: .seconds(1))
        guard case let .failure(error) = result else {
            Issue.record("Expected the unresponsive request to time out")
            return
        }
        #expect(error == .timedOut)
    }
}

struct CodexServerFixture: Sendable {
    let directory: URL
    let executableURL: URL
    let profile: CodexProfile

    init(
        exitsAfterRateLimitRead: Bool = false,
        ignoresTermination: Bool = false,
        omitsAccountResponse: Bool = false,
        omitsInitializeResponse: Bool = false,
    ) throws {
        let fileManager = FileManager.default
        directory = fileManager.temporaryDirectory
            .appending(path: "pace-codex-session-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let profileDirectory = directory.appending(path: "profile", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        if exitsAfterRateLimitRead {
            try Data().write(to: profileDirectory.appending(path: "exit-on-rate"))
        }
        if ignoresTermination {
            try Data().write(to: profileDirectory.appending(path: "ignore-term"))
        }
        if omitsAccountResponse {
            try Data().write(to: profileDirectory.appending(path: "omit-account-response"))
        }
        if omitsInitializeResponse {
            try Data().write(to: profileDirectory.appending(path: "omit-initialize-response"))
        }
        try Data("person@example.invalid".utf8).write(
            to: profileDirectory.appending(path: "email"),
        )
        executableURL = directory.appending(path: "fake-codex")
        try Self.serverScript.write(to: executableURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executableURL.path,
        )
        profile = CodexProfile(
            directory: profileDirectory,
            ownership: .paceManaged,
            displayName: "Fixture",
        )
    }

    func startCount() throws -> Int {
        try startCount(for: profile)
    }

    func startCount(for profile: CodexProfile) throws -> Int {
        let data = try String(
            contentsOf: profile.directory.appending(path: "starts"),
            encoding: .utf8,
        )
        return data.split(separator: "\n").count
    }

    func makeProfile(named name: String) throws -> CodexProfile {
        let profileDirectory = directory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: profileDirectory,
            withIntermediateDirectories: true,
        )
        try Data("\(name)@example.invalid".utf8).write(
            to: profileDirectory.appending(path: "email"),
        )
        return CodexProfile(
            directory: profileDirectory,
            ownership: .paceManaged,
            displayName: name.capitalized,
        )
    }

    func processID() throws -> pid_t {
        guard let processID = processIDIfPresent() else {
            throw ProviderTestTimeout()
        }
        return processID
    }

    func processIDIfPresent() -> pid_t? {
        guard let value = try? String(
            contentsOf: profile.directory.appending(path: "pid"),
            encoding: .utf8,
        ).trimmingCharacters(in: .whitespacesAndNewlines),
            let processID = pid_t(value)
        else {
            return nil
        }
        return processID
    }

    func processIsRunning(_ processID: pid_t) -> Bool {
        Darwin.kill(processID, 0) == 0
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    // swiftlint:disable line_length
    private static let serverScript = #"""
    #!/bin/zsh
    print -r -- start >> "$CODEX_HOME/starts"
    print -r -- $$ > "$CODEX_HOME/pid"
    [[ -f "$CODEX_HOME/ignore-term" ]] && trap '' TERM
    touch "$CODEX_HOME/started"
    if [[ -f "$CODEX_HOME/wait-for-peer" ]]; then
      peer=$(<"$CODEX_HOME/wait-for-peer")
      for attempt in {1..200}; do
        [[ -f "$peer/started" ]] && break
        sleep 0.01
      done
      [[ -f "$peer/started" ]] || exit 9
    fi
    email=$(<"$CODEX_HOME/email")
    usage=21
    [[ "$email" == "second@example.invalid" ]] && usage=42
    initialized=0
    notified=0
    while IFS= read -r line; do
      if [[ "$line" == *'"id":'* ]]; then
        request_id=$(print -r -- "$line" | sed -E 's/.*"id":([0-9]+).*/\1/')
      fi
      if [[ "$line" == *'"method":"initialize"'* ]]; then
        if [[ ! -f "$CODEX_HOME/omit-initialize-response" ]]; then
          print -r -- "{\"id\":$request_id,\"result\":{}}"
        fi
      elif [[ "$line" == *'"method":"initialized"'* ]]; then
        initialized=1
      elif [[ "$line" == *'"method":"account/read"'* ]]; then
        [[ $initialized -eq 1 ]] || exit 8
        if [[ ! -f "$CODEX_HOME/omit-account-response" ]]; then
          print -r -- "{\"id\":$request_id,\"result\":{\"account\":{\"email\":\"$email\",\"planType\":\"plus\",\"type\":\"chatgpt\"},\"requiresOpenaiAuth\":true}}"
        fi
      elif [[ "$line" == *'"method":"account/rateLimits/read"'* ]]; then
        print -r -- "{\"id\":$request_id,\"result\":{\"rateLimits\":{\"limitId\":\"codex\",\"limitName\":\"Codex\",\"planType\":\"plus\",\"primary\":{\"usedPercent\":$usage,\"windowDurationMins\":300,\"resetsAt\":1788145200},\"secondary\":null},\"rateLimitsByLimitId\":null}}"
        if [[ $notified -eq 0 ]]; then
          print -r -- '{"method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","limitName":"Codex","planType":"plus","primary":{"usedPercent":22,"windowDurationMins":300,"resetsAt":1788145200},"secondary":null}}}'
          notified=1
        fi
        if [[ -f "$CODEX_HOME/exit-on-rate" ]]; then
          exit 0
        fi
      fi
    done
    if [[ -f "$CODEX_HOME/ignore-term" ]]; then
      while true; do sleep 1; done
    fi
    """#
    // swiftlint:enable line_length
}

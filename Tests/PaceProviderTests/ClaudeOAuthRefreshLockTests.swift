import Foundation
@testable import PaceProviders
import Testing

@Suite("Claude OAuth refresh lock")
struct ClaudeOAuthRefreshLockTests {
    @Test
    func `holds current and legacy Claude Code locks until release`() async throws {
        let parent = FileManager.default.temporaryDirectory.appending(
            path: "pace-claude-oauth-lock-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let storage = parent.appending(path: "profile", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: parent) }
        let profile = ClaudeProfile(
            directory: storage,
            ownership: .existing,
            secureStorageDirectory: storage,
        )

        let lease = try await ClaudeOAuthRefreshFileLock().acquire(for: profile)
        let currentLock = storage.appending(
            path: ".oauth_refresh.lock",
            directoryHint: .isDirectory,
        )
        let legacyLock = URL(
            filePath: storage.resolvingSymlinksInPath().path + ".lock",
            directoryHint: .isDirectory,
        )

        #expect(FileManager.default.fileExists(atPath: currentLock.path))
        #expect(FileManager.default.fileExists(atPath: legacyLock.path))
        var acquiredCompetingLock = false
        do {
            _ = try ClaudeCompatibleFileLock.acquire(
                at: currentLock,
                staleAfter: 60,
                retries: 0,
                minimumDelay: 0,
                maximumDelay: 0,
            )
            acquiredCompetingLock = true
        } catch {}
        #expect(!acquiredCompetingLock)

        lease.release()

        #expect(!FileManager.default.fileExists(atPath: currentLock.path))
        #expect(!FileManager.default.fileExists(atPath: legacyLock.path))
    }
}

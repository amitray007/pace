import Foundation

protocol ClaudeOAuthRefreshLocking: Sendable {
    func acquire(for profile: ClaudeProfile) async throws(ClaudeProviderError)
        -> ClaudeOAuthRefreshLockLease
}

final class ClaudeOAuthRefreshLockLease: @unchecked Sendable {
    private let lock = NSLock()
    private var isReleased = false
    private let heartbeat: Task<Void, Never>?
    private let heldLocks: [ClaudeCompatibleFileLock.HeldLock]

    init(
        heldLocks: [ClaudeCompatibleFileLock.HeldLock] = [],
        heartbeat: Task<Void, Never>? = nil,
    ) {
        self.heldLocks = heldLocks
        self.heartbeat = heartbeat
    }

    func release() {
        let shouldRelease = lock.withLock {
            guard !isReleased else {
                return false
            }
            isReleased = true
            return true
        }
        guard shouldRelease else {
            return
        }
        heartbeat?.cancel()
        for heldLock in heldLocks.reversed() {
            ClaudeCompatibleFileLock.release(heldLock)
        }
    }

    deinit {
        release()
    }
}

struct ClaudeOAuthRefreshFileLock: ClaudeOAuthRefreshLocking {
    private static let staleInterval: TimeInterval = 60
    private static let heartbeatInterval = Duration.seconds(5)
    private static let maximumAttempts = 5

    func acquire(
        for profile: ClaudeProfile,
    ) async throws(ClaudeProviderError) -> ClaudeOAuthRefreshLockLease {
        try prepareStorageDirectory(profile.secureStorageDirectory)
        for attempt in 1 ... Self.maximumAttempts {
            guard !Task.isCancelled else {
                throw .cancelled
            }
            do {
                let heldLocks = try acquireCompatibleLocks(for: profile)
                return ClaudeOAuthRefreshLockLease(
                    heldLocks: heldLocks,
                    heartbeat: heartbeat(for: heldLocks),
                )
            } catch {
                guard attempt < Self.maximumAttempts else {
                    throw .refreshLocked
                }
                try await waitBeforeRetry()
            }
        }
        throw .refreshLocked
    }

    private func prepareStorageDirectory(_ directory: URL) throws(ClaudeProviderError) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
        } catch {
            throw .credentialWriteFailed
        }
    }

    private func acquireCompatibleLocks(
        for profile: ClaudeProfile,
    ) throws -> [ClaudeCompatibleFileLock.HeldLock] {
        var locks: [ClaudeCompatibleFileLock.HeldLock] = []
        do {
            try locks.append(acquireLock(at: profile.secureStorageDirectory.appending(
                path: ".oauth_refresh.lock",
                directoryHint: .isDirectory,
            )))
            let resolvedStorage = profile.secureStorageDirectory.resolvingSymlinksInPath()
            try locks.append(acquireLock(at: URL(
                filePath: resolvedStorage.path + ".lock",
                directoryHint: .isDirectory,
            )))
            return locks
        } catch {
            locks.reversed().forEach(ClaudeCompatibleFileLock.release)
            throw error
        }
    }

    private func acquireLock(at url: URL) throws -> ClaudeCompatibleFileLock.HeldLock {
        try ClaudeCompatibleFileLock.acquire(
            at: url,
            staleAfter: Self.staleInterval,
            retries: 0,
            minimumDelay: 0,
            maximumDelay: 0,
        )
    }

    private func heartbeat(
        for locks: [ClaudeCompatibleFileLock.HeldLock],
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.heartbeatInterval)
                } catch {
                    break
                }
                locks.forEach(ClaudeCompatibleFileLock.touch)
            }
        }
    }

    private func waitBeforeRetry() async throws(ClaudeProviderError) {
        do {
            try await Task.sleep(for: .milliseconds(Int.random(in: 1000 ... 2000)))
        } catch {
            throw .cancelled
        }
    }
}

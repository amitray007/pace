import Darwin
import Foundation

enum ClaudeCompatibleFileLock {
    private static let storageWriteLockName = ".storage-write.lock"
    private static let storageWriteStaleInterval: TimeInterval = 15

    struct HeldLock: Sendable {
        let url: URL
        let inode: UInt64
    }

    static func withStorageWriteLock<Result>(
        in directory: URL,
        operation: () throws -> Result,
    ) throws(ClaudeProviderError) -> Result {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
            let lock = try acquire(
                at: directory.appending(
                    path: storageWriteLockName,
                    directoryHint: .isDirectory,
                ),
                staleAfter: storageWriteStaleInterval,
                retries: 10,
                minimumDelay: 0.1,
                maximumDelay: 1,
            )
            defer { release(lock) }
            return try operation()
        } catch let error as ClaudeProviderError {
            throw error
        } catch {
            throw .credentialWriteFailed
        }
    }

    static func acquire(
        at url: URL,
        staleAfter: TimeInterval,
        retries: Int,
        minimumDelay: TimeInterval,
        maximumDelay: TimeInterval,
    ) throws -> HeldLock {
        var delay = minimumDelay
        for attempt in 0 ... retries {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                return try HeldLock(url: url, inode: inode(at: url))
            } catch {
                if try removeIfStale(at: url, staleAfter: staleAfter) {
                    continue
                }
                guard attempt < retries else {
                    throw error
                }
                Thread.sleep(forTimeInterval: delay)
                delay = min(maximumDelay, delay * 2)
            }
        }
        throw ClaudeProviderError.credentialWriteFailed
    }

    static func release(_ lock: HeldLock) {
        guard (try? inode(at: lock.url)) == lock.inode else {
            return
        }
        _ = lock.url.path.withCString { rmdir($0) }
    }

    static func touch(_ lock: HeldLock) {
        guard (try? inode(at: lock.url)) == lock.inode else {
            return
        }
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: lock.url.path,
        )
    }

    private static func removeIfStale(
        at url: URL,
        staleAfter: TimeInterval,
    ) throws -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modifiedAt) > staleAfter,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              (try? Self.inode(at: url)) == inode
        else {
            return false
        }
        return url.path.withCString { rmdir($0) } == 0
    }

    private static func inode(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
            throw CocoaError(.fileReadUnknown)
        }
        return inode
    }
}

import Foundation
import PaceCore

/// A short-lived cache in front of a Cursor keychain reader.
///
/// Reading a Cursor credential touches two keychain items, and one refresh
/// reads the credential twice: once to make the request and once afterwards to
/// notice whether Cursor rotated it mid-flight. That is four keychain reads per
/// refresh for a single account, and each read is a separate access-control
/// check by macOS.
///
/// The cache holds a value only long enough to cover one refresh, so the reads
/// inside a refresh share one keychain access while consecutive refreshes still
/// observe the current credential. The rotation check keeps working because an
/// entry expires far inside the provider's polling interval.
///
/// This wraps another reader rather than replacing it, so the caching decision
/// stays out of the credential-loading logic.
struct CursorCachingKeychainReader: CursorKeychainReading {
    /// Long enough to span a single refresh, short enough that a rotation is
    /// noticed on the next one.
    static let lifetime: TimeInterval = 2

    private let base: any CursorKeychainReading
    private let storage: CursorKeychainReadStorage
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date

    init(
        base: any CursorKeychainReading = CursorSecurityKeychainReader(),
        storage: CursorKeychainReadStorage = .shared,
        lifetime: TimeInterval = Self.lifetime,
        now: @escaping @Sendable () -> Date = Date.init,
    ) {
        self.base = base
        self.storage = storage
        self.lifetime = lifetime
        self.now = now
    }

    func readGenericPassword(
        service: String,
        account: String,
    ) throws(CursorProviderError) -> CursorKeychainRecord? {
        let readAt = now()
        if let cached = storage.record(
            service: service,
            account: account,
            notOlderThan: lifetime,
            now: readAt,
        ) {
            return cached
        }
        let record = try base.readGenericPassword(service: service, account: account)
        storage.store(record, service: service, account: account, now: readAt)
        return record
    }
}

/// Thread-safe storage for `CursorCachingKeychainReader`.
///
/// A provider refresh can run on any executor, so the entries are guarded by a
/// lock rather than assuming a single caller.
final class CursorKeychainReadStorage: @unchecked Sendable {
    static let shared = CursorKeychainReadStorage()

    private struct Key: Hashable {
        let service: String
        let account: String
    }

    private struct Entry {
        let record: CursorKeychainRecord?
        let readAt: Date
    }

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]

    /// The cached record, or `nil` when nothing usable is cached.
    ///
    /// A cached absence is itself meaningful, so this returns a double optional:
    /// the outer level distinguishes "nothing cached" from "cached, and the
    /// item does not exist".
    func record(
        service: String,
        account: String,
        notOlderThan lifetime: TimeInterval,
        now: Date,
    ) -> CursorKeychainRecord?? {
        let key = Key(service: service, account: account)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else {
            return nil
        }
        guard now.timeIntervalSince(entry.readAt) < lifetime else {
            entries.removeValue(forKey: key)
            return nil
        }
        return .some(entry.record)
    }

    func store(
        _ record: CursorKeychainRecord?,
        service: String,
        account: String,
        now: Date,
    ) {
        let key = Key(service: service, account: account)
        lock.lock()
        defer { lock.unlock() }
        entries[key] = Entry(record: record, readAt: now)
    }
}

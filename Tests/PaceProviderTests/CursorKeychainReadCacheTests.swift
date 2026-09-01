import Foundation
@testable import PaceProviders
import Testing

/// A keychain reader that records how many times each item was read, so a test
/// can assert on keychain access rather than on returned values alone.
private final class CountingKeychain: CursorKeychainReading, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data]
    private(set) var readCount = 0

    init(storage: [String: Data]) {
        self.storage = storage
    }

    func setValue(_ value: Data, for service: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[service] = value
    }

    func readGenericPassword(
        service: String,
        account _: String,
    ) throws(CursorProviderError) -> CursorKeychainRecord? {
        lock.lock()
        defer { lock.unlock() }
        readCount += 1
        return storage[service].map(CursorKeychainRecord.init(data:))
    }
}

@Suite("Cursor keychain read cache")
struct CursorKeychainReadCacheTests {
    private func makeReader(
        base: CountingKeychain,
        clock: @escaping @Sendable () -> Date,
    ) -> CursorCachingKeychainReader {
        CursorCachingKeychainReader(
            base: base,
            storage: CursorKeychainReadStorage(),
            lifetime: 2,
            now: clock,
        )
    }

    @Test
    func `repeated reads inside one refresh touch the keychain once`() throws {
        // One Cursor refresh loads the credential twice and each load reads two
        // items, so without a cache a single refresh asks macOS four times.
        let base = CountingKeychain(storage: ["cursor-access-token": Data("a".utf8)])
        let start = Date(timeIntervalSince1970: 0)
        let reader = makeReader(base: base) { start }

        for _ in 0 ..< 4 {
            _ = try reader.readGenericPassword(
                service: "cursor-access-token",
                account: "cursor-user",
            )
        }

        #expect(base.readCount == 1)
    }

    @Test
    func `a later refresh reads the keychain again`() throws {
        let base = CountingKeychain(storage: ["cursor-access-token": Data("a".utf8)])
        let clock = MutableClock(now: Date(timeIntervalSince1970: 0))
        let reader = makeReader(base: base) { clock.now }

        _ = try reader.readGenericPassword(
            service: "cursor-access-token",
            account: "cursor-user",
        )
        clock.now = Date(timeIntervalSince1970: 3)
        _ = try reader.readGenericPassword(
            service: "cursor-access-token",
            account: "cursor-user",
        )

        #expect(base.readCount == 2)
    }

    @Test
    func `a rotated credential is observed on the next refresh`() throws {
        // The cache must not hide a rotation, because the reader compares the
        // credential before and after a request to detect one.
        let base = CountingKeychain(storage: ["cursor-access-token": Data("old".utf8)])
        let clock = MutableClock(now: Date(timeIntervalSince1970: 0))
        let reader = makeReader(base: base) { clock.now }

        let before = try reader.readGenericPassword(
            service: "cursor-access-token",
            account: "cursor-user",
        )
        base.setValue(Data("new".utf8), for: "cursor-access-token")
        clock.now = Date(timeIntervalSince1970: 3)
        let after = try reader.readGenericPassword(
            service: "cursor-access-token",
            account: "cursor-user",
        )

        #expect(before?.data == Data("old".utf8))
        #expect(after?.data == Data("new".utf8))
    }

    @Test
    func `separate items do not share a cache entry`() throws {
        let base = CountingKeychain(storage: [
            "cursor-access-token": Data("a".utf8),
            "cursor-refresh-token": Data("r".utf8),
        ])
        let start = Date(timeIntervalSince1970: 0)
        let reader = makeReader(base: base) { start }

        let access = try reader.readGenericPassword(
            service: "cursor-access-token",
            account: "cursor-user",
        )
        let refresh = try reader.readGenericPassword(
            service: "cursor-refresh-token",
            account: "cursor-user",
        )

        #expect(access?.data == Data("a".utf8))
        #expect(refresh?.data == Data("r".utf8))
        #expect(base.readCount == 2)
    }

    @Test
    func `a missing item is cached without re-reading`() throws {
        // A signed-out account has no item. Repeating that read would prompt
        // just as often as a present one, so absence is cached too.
        let base = CountingKeychain(storage: [:])
        let start = Date(timeIntervalSince1970: 0)
        let reader = makeReader(base: base) { start }

        let first = try reader.readGenericPassword(
            service: "cursor-access-token",
            account: "cursor-user",
        )
        let second = try reader.readGenericPassword(
            service: "cursor-access-token",
            account: "cursor-user",
        )

        #expect(first == nil)
        #expect(second == nil)
        #expect(base.readCount == 1)
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: Date

    init(now: Date) {
        storedNow = now
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedNow
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedNow = newValue
        }
    }
}

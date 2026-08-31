import Foundation

public enum PacePreferencesPersistenceError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
}

public protocol PacePreferencesPersistence: Sendable {
    func load() async throws -> PacePreferences?
    func save(_ preferences: PacePreferences) async throws
}

public actor InMemoryPacePreferencesPersistence: PacePreferencesPersistence {
    private var storedPreferences: PacePreferences?

    public init(initialPreferences: PacePreferences? = nil) {
        storedPreferences = initialPreferences
    }

    public func load() -> PacePreferences? {
        storedPreferences
    }

    public func save(_ preferences: PacePreferences) {
        storedPreferences = preferences
    }
}

public struct FilePacePreferencesPersistence: PacePreferencesPersistence {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    @concurrent
    public func load() async throws -> PacePreferences? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let preferences = try JSONDecoder().decode(PacePreferences.self, from: data)
        guard preferences.version == PacePreferences.currentVersion else {
            throw PacePreferencesPersistenceError.unsupportedVersion(preferences.version)
        }
        return preferences
    }

    @concurrent
    public func save(_ preferences: PacePreferences) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700],
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path,
        )
    }
}

public actor PacePreferencesStore {
    private let persistence: any PacePreferencesPersistence
    private var preferences: PacePreferences

    public init(
        preferences: PacePreferences = PacePreferences(),
        persistence: any PacePreferencesPersistence,
    ) {
        self.preferences = preferences
        self.persistence = persistence
    }

    public static func open(
        persistence: any PacePreferencesPersistence,
    ) async throws -> PacePreferencesStore {
        let preferences = try await persistence.load() ?? PacePreferences()
        return PacePreferencesStore(preferences: preferences, persistence: persistence)
    }

    public func currentPreferences() -> PacePreferences {
        preferences
    }

    public func replace(with preferences: PacePreferences) async throws {
        try await persistence.save(preferences)
        self.preferences = preferences
    }
}

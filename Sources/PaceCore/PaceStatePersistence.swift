import Foundation

public enum PaceStatePersistenceError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
}

public protocol PaceStatePersistence: Sendable {
    func load() async throws -> PaceState?
    func save(_ state: PaceState) async throws
}

public actor InMemoryPaceStatePersistence: PaceStatePersistence {
    private var storedState: PaceState?

    public init(initialState: PaceState? = nil) {
        storedState = initialState
    }

    public func load() -> PaceState? {
        storedState
    }

    public func save(_ state: PaceState) {
        storedState = state
    }
}

public struct FilePaceStatePersistence: PaceStatePersistence {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    @concurrent
    public func load() async throws -> PaceState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(PaceState.self, from: data)
        guard state.version == PaceState.currentVersion else {
            throw PaceStatePersistenceError.unsupportedVersion(state.version)
        }
        return state
    }

    @concurrent
    public func save(_ state: PaceState) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700],
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path,
        )
    }
}

import Foundation
@testable import PaceCore
import Testing

@Suite("Pace preferences")
struct PacePreferencesTests {
    @Test
    func `defaults keep the rail opt-in and use safe activation`() {
        let preferences = PacePreferences()

        #expect(preferences.surfaceMode == .menuBar)
        #expect(preferences.railEdge == .right)
        #expect(preferences.railVerticalPosition == .center)
        #expect(preferences.activationMode == .modifierHover)
        #expect(preferences.activationModifier == .shift)
        #expect(preferences.providerOrder == PacePreferences.defaultProviderOrder)
    }

    @Test
    func `normalizes provider order and bounded delays`() {
        let customProvider = ProviderID(rawValue: "custom")
        let preferences = PacePreferences(
            dwellDelay: .infinity,
            dismissalDelay: 10,
            providerOrder: [.cursor, .claude, .cursor, customProvider],
        )

        #expect(preferences.dwellDelay == 0.2)
        #expect(preferences.dismissalDelay == 2)
        #expect(preferences.providerOrder == [
            .cursor,
            .claude,
            customProvider,
            .codex,
            .grok,
            .githubCopilot,
        ])
    }

    @Test
    func `decodes sparse preferences with current defaults`() throws {
        let data = Data("""
        {
          "version": 1,
          "railEdge": "left"
        }
        """.utf8)

        let preferences = try JSONDecoder().decode(PacePreferences.self, from: data)

        #expect(preferences.railEdge == .left)
        #expect(preferences.surfaceMode == .menuBar)
        #expect(preferences.activationModifier == .shift)
    }

    @Test
    func `round-trips private preference file and store`() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "pace-preferences-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fileURL = directoryURL.appending(path: "preferences.json")
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let persistence = FilePacePreferencesPersistence(fileURL: fileURL)
        let store = try await PacePreferencesStore.open(persistence: persistence)
        let expected = PacePreferences(
            surfaceMode: .both,
            railEdge: .left,
            selectedDisplayID: "display-2",
            railVerticalPosition: .top,
            activationMode: .clickHandle,
            providerOrder: [.cursor, .claude, .codex],
        )
        try await store.replace(with: expected)

        let reopened = try await PacePreferencesStore.open(persistence: persistence)
        let actual = await reopened.currentPreferences()
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)

        #expect(actual == expected)
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test
    func `rejects an unsupported stored version`() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "pace-preferences-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fileURL = directoryURL.appending(path: "preferences.json")
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
        )
        try JSONEncoder().encode(PacePreferences(version: 99)).write(to: fileURL)
        let persistence = FilePacePreferencesPersistence(fileURL: fileURL)

        await #expect(throws: PacePreferencesPersistenceError.unsupportedVersion(99)) {
            _ = try await persistence.load()
        }
    }
}

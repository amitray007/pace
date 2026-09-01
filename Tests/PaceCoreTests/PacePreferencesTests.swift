import Foundation
@testable import PaceCore
import Testing

@Suite("Pace preferences")
struct PacePreferencesTests {
    @Test
    func `defaults keep the rail opt-in and use deliberate hover activation`() {
        let preferences = PacePreferences()

        #expect(preferences.surfaceMode == .menuBar)
        #expect(preferences.railEdge == .right)
        #expect(preferences.railScale == .medium)
        #expect(preferences.railVerticalPosition == .center)
        #expect(preferences.activationMode == .dwellHover)
        #expect(preferences.dwellDelay == PacePreferences.defaultDwellDelay)
        #expect(preferences.activationModifier == .shift)
        #expect(preferences.notificationPolicy == .disabled)
        #expect(preferences.providerOrder == PacePreferences.defaultProviderOrder)
    }

    @Test
    func `rail scale steps stay ordered and bracket the reference size`() {
        // The silhouette is defined by ratios of the rail's width, so a scale
        // step only changes size. Medium must stay at the reference size so the
        // default keeps the measured proportions exactly.
        #expect(RailScale.medium.multiplier == 1)
        #expect(RailScale.small.multiplier < RailScale.medium.multiplier)
        #expect(RailScale.medium.multiplier < RailScale.large.multiplier)
        for scale in RailScale.allCases {
            #expect(scale.multiplier > 0)
        }

        // The rail is drawn inside a fixed transparent canvas, so a step that
        // scales past it would clip the contour instead of enlarging it.
        for scale in RailScale.allCases {
            #expect(scale.multiplier <= RailScale.maximumMultiplier)
        }
    }

    @Test
    func `the dwell bound keeps hover activation immediate`() {
        // In the reference recording the rail starts opening while the pointer
        // is still travelling toward the edge. A dwell long enough to notice
        // would contradict that, so the bound and the default both stay small.
        #expect(PacePreferences.defaultDwellDelay <= 0.1)
        #expect(PacePreferences.dwellDelayRange.lowerBound <= 0.05)
        #expect(PacePreferences.dwellDelayRange.contains(PacePreferences.defaultDwellDelay))
    }

    @Test
    func `normalizes provider order and bounded delays`() {
        let customProvider = ProviderID(rawValue: "custom")
        let preferences = PacePreferences(
            dwellDelay: .infinity,
            dismissalDelay: 10,
            providerOrder: [.cursor, .claude, .cursor, customProvider],
        )

        // An out-of-range dwell clamps to the lower bound, which is small
        // enough that the rail still answers the pointer immediately.
        #expect(preferences.dwellDelay == PacePreferences.dwellDelayRange.lowerBound)
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
        #expect(preferences.railScale == .medium)
        #expect(preferences.surfaceMode == .menuBar)
        #expect(preferences.activationMode == .dwellHover)
        #expect(preferences.dwellDelay == PacePreferences.defaultDwellDelay)
        #expect(preferences.activationModifier == .shift)
        #expect(preferences.notificationPolicy == .disabled)
    }

    @Test
    func `migrates the prototype modifier hover default to plain hover`() throws {
        let data = Data("""
        {
          "activationMode": "modifierHover",
          "dismissalDelay": 0.4,
          "dwellDelay": 0.6,
          "version": 1
        }
        """.utf8)

        let preferences = try JSONDecoder().decode(PacePreferences.self, from: data)

        #expect(preferences.version == PacePreferences.currentVersion)
        #expect(preferences.activationMode == .dwellHover)
        #expect(preferences.dwellDelay == PacePreferences.defaultDwellDelay)
    }

    @Test
    func `round-trips notification rules and quiet hours`() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Kolkata"))
        let policy = try PaceNotificationPolicy(
            usageThreshold: 0.85,
            resetReminderLeadTime: 2 * 60 * 60,
            warnsWhenDataBecomesStale: true,
            quietHours: NotificationQuietHours(
                startMinutesAfterMidnight: 22 * 60,
                endMinutesAfterMidnight: 8 * 60,
                timeZone: timeZone,
            ),
        )
        let preferences = PacePreferences(notificationPolicy: policy)

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(PacePreferences.self, from: data)

        #expect(decoded.notificationPolicy == policy)
    }

    @Test
    func `rejects invalid persisted notification rules`() throws {
        let invalidThreshold = Data("""
        {
          "notificationPolicy": {
            "usageThreshold": 1.2,
            "warnsWhenDataBecomesStale": false
          },
          "version": 1
        }
        """.utf8)
        let quietHours = try NotificationQuietHours(
            startMinutesAfterMidnight: 22 * 60,
            endMinutesAfterMidnight: 8 * 60,
            timeZone: #require(TimeZone(identifier: "Asia/Kolkata")),
        )
        let policy = try PaceNotificationPolicy(quietHours: quietHours)
        let validData = try JSONEncoder().encode(PacePreferences(notificationPolicy: policy))
        var root = try #require(
            JSONSerialization.jsonObject(with: validData) as? [String: Any],
        )
        var storedPolicy = try #require(root["notificationPolicy"] as? [String: Any])
        var storedQuietHours = try #require(storedPolicy["quietHours"] as? [String: Any])
        storedQuietHours["startMinutesAfterMidnight"] = 8 * 60
        storedPolicy["quietHours"] = storedQuietHours
        root["notificationPolicy"] = storedPolicy
        let invalidQuietHours = try JSONSerialization.data(withJSONObject: root)

        #expect(throws: PaceNotificationPolicyError.invalidUsageThreshold(1.2)) {
            _ = try JSONDecoder().decode(PacePreferences.self, from: invalidThreshold)
        }
        #expect(throws: NotificationQuietHoursError.identicalStartAndEnd) {
            _ = try JSONDecoder().decode(PacePreferences.self, from: invalidQuietHours)
        }
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

import Foundation
@testable import PaceCore
import Testing

@Suite("Menu bar presentation")
struct MenuBarPresentationTests {
    @Test
    func `keeps at most two slots`() {
        // The status item is drawn beside the clock, so a third reading would
        // widen it past what a menu bar can spare.
        let presentation = MenuBarPresentation(slots: [
            MenuBarUsageSlot(providerID: .claude),
            MenuBarUsageSlot(providerID: .codex),
            MenuBarUsageSlot(providerID: .cursor),
        ])

        #expect(presentation.slots.count == 2)
        #expect(presentation.slots.map(\.providerID) == [.claude, .codex])
    }

    @Test
    func `defaults to showing no reading`() {
        // Pace cannot guess which quota matters, so it shows a plain gauge
        // until the user names one.
        #expect(MenuBarPresentation().slots.isEmpty)
    }

    @Test
    func `preferences stored before the menu bar existed still load`() throws {
        // The field was added after release, so an older file has no entry for
        // it and must not fail to decode.
        let stored = """
        {"version": 2, "surfaceMode": "menuBar"}
        """
        let preferences = try JSONDecoder().decode(
            PacePreferences.self,
            from: Data(stored.utf8),
        )

        #expect(preferences.menuBar.slots.isEmpty)
        #expect(preferences.menuBar.showsPercentSign == false)
    }

    @Test
    func `defaults to matching the menu bar rather than brand colours`() {
        // The status item sits among the system's own items, which are all
        // monochrome and tinted by macOS. Standing out is opt-in.
        #expect(MenuBarPresentation().tint == .monochrome)
    }

    @Test
    func `preferences stored before the tint existed keep the monochrome default`() throws {
        let stored = """
        {"slots": [{"providerID": "claude"}], "showsPercentSign": true}
        """
        let presentation = try JSONDecoder().decode(
            MenuBarPresentation.self,
            from: Data(stored.utf8),
        )

        #expect(presentation.tint == .monochrome)
        #expect(presentation.showsPercentSign)
    }

    @Test
    func `account addresses are shown unless hiding is turned on`() {
        // Hiding is for screenshots and screen sharing, so it must be a
        // deliberate choice rather than something Pace decides.
        #expect(PacePreferences().hidesAccountIdentity == false)
    }

    @Test
    func `preferences stored before identity hiding existed still load`() throws {
        let stored = """
        {"version": 2, "surfaceMode": "menuBar"}
        """
        let preferences = try JSONDecoder().decode(
            PacePreferences.self,
            from: Data(stored.utf8),
        )

        #expect(preferences.hidesAccountIdentity == false)
    }

    @Test
    func `a slot round trips through storage`() throws {
        let preferences = PacePreferences(
            menuBar: MenuBarPresentation(
                slots: [
                    MenuBarUsageSlot(
                        providerID: .claude,
                        bucketID: BucketID(rawValue: "current-session"),
                    ),
                ],
                showsPercentSign: true,
            ),
        )

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(PacePreferences.self, from: data)

        #expect(decoded.menuBar == preferences.menuBar)
        #expect(decoded.menuBar.slots.first?.bucketID?.rawValue == "current-session")
    }
}

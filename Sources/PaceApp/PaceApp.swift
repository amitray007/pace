import SwiftUI

@main
struct PaceApp: App {
    @NSApplicationDelegateAdaptor(PaceAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PaceSettingsView(model: appDelegate.model)
        }
    }
}

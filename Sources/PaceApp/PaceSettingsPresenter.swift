import Foundation

@MainActor
enum PaceSettingsPresenter {
    static func show() {
        NotificationCenter.default.post(name: .paceOpenSettings, object: nil)
    }
}

extension Notification.Name {
    static let paceOpenSettings = Notification.Name("PaceOpenSettings")
}

import AppKit

@MainActor
final class PaceAppDelegate: NSObject, NSApplicationDelegate {
    let model = PacePresentationModel()

    private var edgePanelController: EdgePanelController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_: Notification) {
        statusItemController = StatusItemController(model: model)
        edgePanelController = EdgePanelController(model: model)

        Task {
            await model.start()
        }
    }
}

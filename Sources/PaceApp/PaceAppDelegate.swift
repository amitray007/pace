import AppKit
import PaceCore

@MainActor
final class PaceAppDelegate: NSObject, NSApplicationDelegate {
    let model = PacePresentationModel(
        preferencesPersistence: FilePacePreferencesPersistence(
            fileURL: PaceApplicationPaths.preferencesURL,
        ),
        statePersistence: FilePaceStatePersistence(
            fileURL: PaceApplicationPaths.stateURL,
        ),
    )

    private var edgePanelController: EdgePanelController?
    private var terminationTask: Task<Void, Never>?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_: Notification) {
        statusItemController = StatusItemController(model: model)
        edgePanelController = EdgePanelController(model: model)

        Task {
            await model.start()
            model.startAutomaticRefresh()
        }
        if ProcessInfo.processInfo.environment["PACE_REFERENCE_MOTION"] == "1" {
            scheduleReferenceMotionSequence()
        }
        if ProcessInfo.processInfo.environment["PACE_REFERENCE_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                PaceSettingsPresenter.show()
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        model.stopAutomaticRefresh()
        model.stopProviderUpdates()
    }

    func applicationDidBecomeActive(_: Notification) {
        model.refreshLaunchAtLoginStatus()
        Task {
            await model.refreshNotificationAuthorizationStatus()
        }
    }

    func applicationShouldTerminate(
        _ sender: NSApplication,
    ) -> NSApplication.TerminateReply {
        guard terminationTask == nil else {
            return .terminateLater
        }
        terminationTask = Task { [model] in
            await model.shutdownProviderRuntime()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func scheduleReferenceMotionSequence() {
        let startDelay = ProcessInfo.processInfo.environment["PACE_REFERENCE_MOTION_DELAY"]
            .flatMap(TimeInterval.init) ?? 2
        let steps: [(offset: TimeInterval, state: RailPreviewState)] = [
            (0, .cursor),
            (2, .claude),
            (4, .codex),
            (5, .cursor),
            (5.12, .claude),
            (5.24, .cursor),
            (7, .mini),
        ]
        for step in steps {
            DispatchQueue.main
                .asyncAfter(deadline: .now() + startDelay + step.offset) { [weak self] in
                    self?.model.railPreviewState = step.state
                }
        }
    }
}

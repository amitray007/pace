@testable import PaceCore
import Testing

@MainActor
@Suite("Launch at login")
struct LaunchAtLoginTests {
    @Test
    func `enables and disables only after an explicit change`() {
        let service = StubLaunchAtLoginService(status: .disabled)
        let setting = LaunchAtLoginSetting(service: service)

        #expect(!setting.isRegistered)
        #expect(service.registerCount == 0)

        setting.setEnabled(true)
        #expect(setting.status == .enabled)
        #expect(setting.isRegistered)
        #expect(service.registerCount == 1)

        setting.setEnabled(false)
        #expect(setting.status == .disabled)
        #expect(service.unregisterCount == 1)
        #expect(!setting.lastOperationFailed)
    }

    @Test
    func `requires a separate user action for revoked approval`() {
        let service = StubLaunchAtLoginService(status: .requiresApproval)
        let setting = LaunchAtLoginSetting(service: service)

        #expect(setting.isRegistered)
        setting.setEnabled(true)
        #expect(setting.status == .requiresApproval)
        #expect(service.registerCount == 0)
        #expect(service.openSettingsCount == 0)

        setting.openSystemSettings()
        #expect(service.openSettingsCount == 1)

        setting.setEnabled(false)
        #expect(setting.status == .disabled)
        #expect(service.unregisterCount == 1)
    }

    @Test
    func `reports a failed operation and adopts the service status`() {
        let service = StubLaunchAtLoginService(status: .disabled, shouldFail: true)
        let setting = LaunchAtLoginSetting(service: service)

        setting.setEnabled(true)

        #expect(setting.status == .disabled)
        #expect(setting.lastOperationFailed)
        #expect(service.registerCount == 1)
    }

    @Test
    func `refresh adopts a change made in System Settings`() {
        let service = StubLaunchAtLoginService(status: .disabled)
        let setting = LaunchAtLoginSetting(service: service)

        service.status = .requiresApproval
        setting.refresh()

        #expect(setting.status == .requiresApproval)
        #expect(setting.isRegistered)
    }

    @Test
    func `does not mutate an unavailable service`() {
        let service = StubLaunchAtLoginService(status: .unavailable)
        let setting = LaunchAtLoginSetting(service: service)

        setting.setEnabled(true)
        setting.setEnabled(false)

        #expect(setting.status == .unavailable)
        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)
    }
}

@MainActor
private final class StubLaunchAtLoginService: LaunchAtLoginService {
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0
    var status: LaunchAtLoginStatus
    let shouldFail: Bool

    init(status: LaunchAtLoginStatus, shouldFail: Bool = false) {
        self.status = status
        self.shouldFail = shouldFail
    }

    func register() throws {
        registerCount += 1
        if shouldFail {
            throw StubError.failed
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if shouldFail {
            throw StubError.failed
        }
        status = .disabled
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }

    private enum StubError: Error {
        case failed
    }
}

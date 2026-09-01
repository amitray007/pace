@MainActor
public protocol LaunchAtLoginService: AnyObject {
    var status: LaunchAtLoginStatus { get }

    func register() throws
    func unregister() throws
    func openSystemSettings()
}

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
public final class LaunchAtLoginSetting {
    public private(set) var status: LaunchAtLoginStatus
    public private(set) var lastOperationFailed = false

    private let service: any LaunchAtLoginService

    public init(service: any LaunchAtLoginService) {
        self.service = service
        status = service.status
    }

    public var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    public func refresh() {
        status = service.status
    }

    public func setEnabled(_ isEnabled: Bool) {
        lastOperationFailed = false
        do {
            switch (isEnabled, status) {
            case (true, .disabled):
                try service.register()
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            case (true, .enabled), (true, .requiresApproval), (_, .unavailable),
                 (false, .disabled):
                break
            }
            status = service.status
        } catch {
            status = service.status
            lastOperationFailed = true
        }
    }

    public func openSystemSettings() {
        service.openSystemSettings()
    }
}

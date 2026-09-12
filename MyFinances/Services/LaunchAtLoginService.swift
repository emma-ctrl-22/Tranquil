import Foundation
import ServiceManagement

/// Launch at login, so scheduled notifications actually fire.
///
/// `SMAppService` registers the app with the system directly — no helper bundle, no
/// login-items hackery, and the user can revoke it in System Settings at any time.
enum LaunchAtLoginService {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// The user disabled it in System Settings; the app should not fight them over it.
    static var isBlockedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard !isEnabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard isEnabled else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "Tranquil opens when you log in."
        case .requiresApproval: "Approval is needed in System Settings → General → Login Items."
        case .notFound: "Not registered."
        case .notRegistered: "Tranquil does not open at login. Scheduled reminders may not fire."
        @unknown default: "Unknown."
        }
    }
}

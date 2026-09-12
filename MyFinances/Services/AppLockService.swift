import Foundation
import LocalAuthentication

/// Optional Touch ID or password lock on launch and on wake.
///
/// Authentication is handled entirely by the system. The app never sees, stores, or
/// transmits a credential.
@MainActor
@Observable
final class AppLockService {
    static let shared = AppLockService()

    private(set) var isLocked = false
    private(set) var lastError: String?

    private init() {}

    /// Whether this Mac can do it at all.
    var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(
            .deviceOwnerAuthentication, error: &error
        )
    }

    var biometryDescription: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .faceID: return "Face ID"
        default: return "your password"
        }
    }

    func lock() { isLocked = true }

    /// Falls back to the account password when biometrics are unavailable, so the lock
    /// can never make the app unopenable.
    func unlock() async {
        let context = LAContext()
        context.localizedFallbackTitle = "Use password"
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Tranquil"
            )
            if success {
                isLocked = false
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Called at launch and on wake, when the setting is on.
    func lockIfNeeded(settings: AppSettings?, reason: LockReason) {
        guard let settings else { return }
        switch reason {
        case .launch where settings.requireUnlockOnLaunch,
             .wake where settings.requireUnlockOnWake:
            lock()
        default:
            break
        }
    }

    enum LockReason: Sendable {
        case launch, wake
    }
}

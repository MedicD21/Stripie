import Foundation
import LocalAuthentication

/// Thin wrapper around `LocalAuthentication` for Face ID / Touch ID unlock
/// (App Review requirement 1.7). Falls back to the device passcode.
struct BiometricService: Sendable {

    /// Whether the device can evaluate biometrics or a passcode right now.
    var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Human label for the available biometry ("Face ID" / "Touch ID" / "passcode").
    var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:       return "passcode"
        }
    }

    /// Prompts for biometrics (or passcode). Returns true on success.
    func authenticate(reason: String = "Unlock Stripie to take payments") async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

import Foundation

/// Build-environment-aware configuration. Never hardcode secrets here —
/// use environment variables injected at build time or at runtime from Keychain.
struct AppConfiguration: Sendable {
    static let shared = AppConfiguration()

    let apiBaseURL: URL
    let stripePublishableKey: String

    /// Fatal-error message used when required config is missing/invalid.
    /// Failing fast at launch is preferable to constructing an invalid client.
    private static func requireURL(_ raw: String?, fallback: String?) -> URL {
        let value = raw ?? fallback ?? ""
        guard !value.isEmpty, let url = URL(string: value) else {
            fatalError("Invalid or missing STRIPIE_API_URL. Set it in the Xcode scheme's environment variables.")
        }
        return url
    }

    private init() {
        let env = ProcessInfo.processInfo.environment
        #if DEBUG
        apiBaseURL = Self.requireURL(env["STRIPIE_API_URL"], fallback: "http://localhost:8000")
        stripePublishableKey = env["STRIPE_PUBLISHABLE_KEY_TEST"] ?? ""
        #else
        apiBaseURL = Self.requireURL(env["STRIPIE_API_URL"], fallback: nil)
        stripePublishableKey = env["STRIPE_PUBLISHABLE_KEY_LIVE"] ?? ""
        #endif
    }
}

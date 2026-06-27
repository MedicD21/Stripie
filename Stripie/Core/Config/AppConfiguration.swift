import Foundation

/// Build-environment-aware configuration. Never hardcode secrets here —
/// use environment variables injected at build time or at runtime from Keychain.
struct AppConfiguration: Sendable {
    static let shared = AppConfiguration()

    let apiBaseURL: URL
    let stripePublishableKey: String

    private init() {
        #if DEBUG
        let rawURL = ProcessInfo.processInfo.environment["STRIPIE_API_URL"] ?? "http://localhost:8000"
        apiBaseURL = URL(string: rawURL)!
        stripePublishableKey = ProcessInfo.processInfo.environment["STRIPE_PUBLISHABLE_KEY_TEST"] ?? ""
        #else
        let rawURL = ProcessInfo.processInfo.environment["STRIPIE_API_URL"] ?? ""
        apiBaseURL = URL(string: rawURL)!
        stripePublishableKey = ProcessInfo.processInfo.environment["STRIPE_PUBLISHABLE_KEY_LIVE"] ?? ""
        #endif
    }
}

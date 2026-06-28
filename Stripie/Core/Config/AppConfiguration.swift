import Foundation

/// Build-environment-aware configuration. Never hardcode secrets here —
/// use environment variables injected at build time or at runtime from Keychain.
struct AppConfiguration: Sendable {
    static let shared = AppConfiguration()

    let apiBaseURL: URL
    let stripePublishableKey: String
    let apiKey: String

    /// Reads a config value. In DEBUG, prefers Xcode scheme environment variables
    /// (for local/simulator runs); in Release it reads from the app's Info.plist,
    /// because scheme env vars do NOT ship in Archive/TestFlight/App Store builds.
    /// Info.plist values are injected at build time via `INFOPLIST_KEY_*` in project.yml.
    private static func value(env: String, plist: String) -> String? {
        #if DEBUG
        if let v = ProcessInfo.processInfo.environment[env], !v.isEmpty { return v }
        #endif
        if let v = Bundle.main.object(forInfoDictionaryKey: plist) as? String, !v.isEmpty {
            return v
        }
        return nil
    }

    private static func requireURL(_ raw: String?, fallback: String?) -> URL {
        let value = raw ?? fallback ?? ""
        guard !value.isEmpty, let url = URL(string: value) else {
            fatalError("Invalid or missing STRIPIE_API_URL. Set STRIPIE_API_URL in the scheme (DEBUG) or the StripieAPIURL Info.plist key (Release, via project.yml).")
        }
        return url
    }

    private init() {
        #if DEBUG
        let urlFallback = "http://localhost:8000"
        let publishableKey = Self.value(env: "STRIPE_PUBLISHABLE_KEY_TEST", plist: "StripiePublishableKey") ?? ""
        #else
        let urlFallback: String? = nil
        let publishableKey = Self.value(env: "STRIPE_PUBLISHABLE_KEY_LIVE", plist: "StripiePublishableKey") ?? ""
        #endif

        apiBaseURL = Self.requireURL(Self.value(env: "STRIPIE_API_URL", plist: "StripieAPIURL"), fallback: urlFallback)
        stripePublishableKey = publishableKey
        apiKey = Self.value(env: "STRIPIE_API_KEY", plist: "StripieAPIKey") ?? ""
    }
}

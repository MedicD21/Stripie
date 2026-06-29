import SwiftUI
import OSLog

/// Owns admin authentication state for the whole app. The session token lives in
/// the Keychain and the last-known profile is cached in UserDefaults, so the user
/// stays signed in across launches. There is **no auto-logout**: a stored token
/// only clears when the server explicitly rejects it (401/403) or the user signs
/// out. Transient network failures keep the user signed in (optimistically).
@Observable
@MainActor
final class AuthSessionStore {

    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(AdminProfile)
    }

    private(set) var state: State = .loading
    /// Surfaced on the login screen.
    var error: AppError?

    private let service: any AuthServicing
    private let keychain: KeychainStore
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.stripie", category: "AuthSessionStore")

    private var token: String?

    private enum Key { static let profile = "auth.cachedProfile" }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var profile: AdminProfile? {
        if case .signedIn(let p) = state { return p }
        return nil
    }

    init(
        service: any AuthServicing = AuthService(),
        keychain: KeychainStore = KeychainStore(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.keychain = keychain
        self.defaults = defaults
    }

    // MARK: - Lifecycle

    /// Restores any saved session, then validates it in the background.
    func bootstrap() async {
        guard let stored = keychain.read(), !stored.isEmpty else {
            state = .signedOut
            return
        }
        token = stored

        // Show the app immediately using the cached profile (no auto-logout).
        state = .signedIn(cachedProfile() ?? AdminProfile(email: ""))

        do {
            let profile = try await service.fetchProfile(token: stored)
            cache(profile)
            state = .signedIn(profile)
        } catch AppError.network(.httpError(let code, _)) where code == 401 || code == 403 {
            // Token genuinely invalid/expired — require sign-in again.
            logger.info("Stored session rejected (\(code)); signing out")
            clearSession()
        } catch {
            // Transient failure — keep the user signed in with the cached profile.
            logger.error("Session validation failed (kept signed in): \(error.localizedDescription)")
        }
    }

    // MARK: - Login flow

    /// Step 1: request an emailed login code. Returns true on success.
    func requestCode(email: String) async -> Bool {
        error = nil
        do {
            try await service.requestLoginCode(email: normalize(email))
            return true
        } catch {
            setError(error)
            return false
        }
    }

    /// Step 2: verify the emailed code and sign in.
    func verify(email: String, code: String) async {
        error = nil
        do {
            let token = try await service.verifyLoginCode(email: normalize(email), code: code.trimmingCharacters(in: .whitespaces))
            let profile = try await service.fetchProfile(token: token)
            self.token = token
            keychain.save(token)
            cache(profile)
            state = .signedIn(profile)
        } catch {
            setError(error)
        }
    }

    func signOut() async {
        if let token {
            try? await service.logout(token: token)
        }
        clearSession()
    }

    // MARK: - Helpers

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func setError(_ error: Error) {
        self.error = (error as? AppError) ?? .generic(error.localizedDescription)
    }

    private func clearSession() {
        token = nil
        keychain.delete()
        defaults.removeObject(forKey: Key.profile)
        state = .signedOut
    }

    private func cache(_ profile: AdminProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Key.profile)
    }

    private func cachedProfile() -> AdminProfile? {
        guard let data = defaults.data(forKey: Key.profile) else { return nil }
        return try? JSONDecoder().decode(AdminProfile.self, from: data)
    }
}

#if DEBUG
extension AuthSessionStore {
    /// A store with a no-op service in a fixed state, for previews.
    static func preview(_ state: State = .signedOut) -> AuthSessionStore {
        let store = AuthSessionStore(service: PreviewAuthService())
        store.state = state
        return store
    }
}
#endif

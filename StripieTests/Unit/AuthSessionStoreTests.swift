import Testing
import Foundation
@testable import Stripie

@MainActor
@Suite("AuthSessionStore")
struct AuthSessionStoreTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeKeychain() -> KeychainStore {
        let keychain = KeychainStore(service: "test." + UUID().uuidString, account: "token")
        keychain.delete()
        return keychain
    }

    @Test("bootstrap with no stored token signs out")
    func testBootstrapNoToken() async {
        let store = AuthSessionStore(service: MockAuthService(), keychain: makeKeychain(), defaults: makeDefaults())
        await store.bootstrap()
        #expect(store.state == .signedOut)
        #expect(!store.isSignedIn)
    }

    @Test("verify signs in, loads profile, and persists token")
    func testVerifySignsIn() async {
        let mock = MockAuthService()
        await mock.setProfileResult(.success(AdminProfile(email: "a@b.com", isSuperAdmin: true)))
        let keychain = makeKeychain()
        let store = AuthSessionStore(service: mock, keychain: keychain, defaults: makeDefaults())

        await store.verify(email: "A@B.com", code: "123456")

        #expect(store.isSignedIn)
        #expect(store.profile?.email == "a@b.com")
        #expect(store.profile?.isSuperAdmin == true)
        #expect(keychain.read() == "test-token")
        let codes = await mock.verifiedCodes
        #expect(codes.first?.email == "a@b.com")  // normalized to lowercase
    }

    @Test("verify surfaces an error on a bad code and stays signed out")
    func testVerifyError() async {
        let mock = MockAuthService()
        await mock.setVerifyResult(.failure(AppError.network(.httpError(statusCode: 400, message: "Invalid or expired code."))))
        let store = AuthSessionStore(service: mock, keychain: makeKeychain(), defaults: makeDefaults())

        await store.verify(email: "a@b.com", code: "000000")

        #expect(!store.isSignedIn)
        #expect(store.error != nil)
    }

    @Test("requestCode returns false and sets error when not authorized")
    func testRequestCodeNotAuthorized() async {
        let mock = MockAuthService()
        await mock.setRequestCodeError(AppError.network(.httpError(statusCode: 403, message: "Email is not authorized for admin access.")))
        let store = AuthSessionStore(service: mock, keychain: makeKeychain(), defaults: makeDefaults())

        let ok = await store.requestCode(email: "x@y.com")
        #expect(!ok)
        #expect(store.error != nil)
    }

    @Test("bootstrap clears the session when the server rejects the token")
    func testBootstrapRejectedToken() async {
        let mock = MockAuthService()
        await mock.setProfileResult(.failure(AppError.network(.httpError(statusCode: 401, message: nil))))
        let keychain = makeKeychain()
        keychain.save("stale-token")
        let store = AuthSessionStore(service: mock, keychain: keychain, defaults: makeDefaults())

        await store.bootstrap()

        #expect(store.state == .signedOut)
        #expect(keychain.read() == nil)
    }

    @Test("bootstrap keeps the user signed in on a transient network error")
    func testBootstrapTransientError() async {
        let mock = MockAuthService()
        await mock.setProfileResult(.failure(AppError.network(.timeout)))
        let keychain = makeKeychain()
        keychain.save("good-token")
        let defaults = makeDefaults()
        let cached = AdminProfile(email: "cached@x.com")
        defaults.set(try! JSONEncoder().encode(cached), forKey: "auth.cachedProfile")
        let store = AuthSessionStore(service: mock, keychain: keychain, defaults: defaults)

        await store.bootstrap()

        #expect(store.isSignedIn)
        #expect(store.profile?.email == "cached@x.com")
        #expect(keychain.read() == "good-token")  // not cleared
    }

    @Test("signOut clears the token and revokes the session server-side")
    func testSignOut() async {
        let mock = MockAuthService()
        let keychain = makeKeychain()
        let store = AuthSessionStore(service: mock, keychain: keychain, defaults: makeDefaults())
        await store.verify(email: "a@b.com", code: "123456")
        #expect(store.isSignedIn)

        await store.signOut()

        #expect(store.state == .signedOut)
        #expect(keychain.read() == nil)
        let loggedOut = await mock.loggedOutTokens
        #expect(loggedOut.contains("test-token"))
    }
}

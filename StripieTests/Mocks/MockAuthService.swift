import Foundation
@testable import Stripie

/// In-memory stub for `AuthServicing`. Configure outcomes per call and inspect
/// the recorded actions.
actor MockAuthService: AuthServicing {
    var requestCodeError: Error?
    var verifyResult: Result<String, Error> = .success("test-token")
    var profileResult: Result<AdminProfile, Error> = .success(AdminProfile(email: "admin@thegoodkitchen.org"))
    var logoutError: Error?

    private(set) var requestedEmails: [String] = []
    private(set) var verifiedCodes: [(email: String, code: String)] = []
    private(set) var fetchedTokens: [String] = []
    private(set) var loggedOutTokens: [String] = []

    func setVerifyResult(_ result: Result<String, Error>) { verifyResult = result }
    func setProfileResult(_ result: Result<AdminProfile, Error>) { profileResult = result }
    func setRequestCodeError(_ error: Error?) { requestCodeError = error }

    func requestLoginCode(email: String) async throws {
        requestedEmails.append(email)
        if let requestCodeError { throw requestCodeError }
    }

    func verifyLoginCode(email: String, code: String) async throws -> String {
        verifiedCodes.append((email, code))
        return try verifyResult.get()
    }

    func fetchProfile(token: String) async throws -> AdminProfile {
        fetchedTokens.append(token)
        return try profileResult.get()
    }

    func logout(token: String) async throws {
        loggedOutTokens.append(token)
        if let logoutError { throw logoutError }
    }
}

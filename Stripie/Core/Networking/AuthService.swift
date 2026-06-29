import Foundation
import OSLog

/// Talks to the Good Kitchen `admin-portal-auth` Netlify function to run the
/// passwordless email + 6-digit-code admin login used by the website.
protocol AuthServicing: Sendable {
    /// Emails a 6-digit login code to `email` (only if it's an authorized admin).
    func requestLoginCode(email: String) async throws
    /// Exchanges an emailed code for a session token.
    func verifyLoginCode(email: String, code: String) async throws -> String
    /// Validates a token and returns the current admin profile (incl. super-admin).
    func fetchProfile(token: String) async throws -> AdminProfile
    /// Revokes the session server-side. Best-effort.
    func logout(token: String) async throws
}

actor AuthService: AuthServicing {

    private let session: URLSession
    private let endpoint: URL
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.stripie", category: "AuthService")

    init(configuration: AppConfiguration = .shared) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.endpoint = configuration.authBaseURL
            .appendingPathComponent(".netlify/functions/admin-portal-auth")
        self.decoder = {
            let d = JSONDecoder()
            d.keyDecodingStrategy = .convertFromSnakeCase
            return d
        }()
    }

    // MARK: - API

    func requestLoginCode(email: String) async throws {
        _ = try await post(["action": "request_code", "email": email], token: nil)
    }

    func verifyLoginCode(email: String, code: String) async throws -> String {
        let envelope = try await post(
            ["action": "verify_code", "email": email, "code": code],
            token: nil
        )
        guard let token = envelope.token, !token.isEmpty else {
            throw AppError.network(.invalidResponse)
        }
        return token
    }

    func fetchProfile(token: String) async throws -> AdminProfile {
        let envelope = try await post(["action": "status"], token: token)
        guard let profile = envelope.profile else {
            throw AppError.network(.invalidResponse)
        }
        return profile
    }

    func logout(token: String) async throws {
        _ = try await post(["action": "logout"], token: token)
    }

    // MARK: - Transport

    private func post(_ body: [String: String], token: String?) async throws -> AuthEnvelope {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.debug("→ auth \(body["action"] ?? "?")")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AppError.network(.timeout)
        } catch {
            throw AppError.network(.invalidResponse)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.network(.invalidResponse)
        }

        let envelope = try? decoder.decode(AuthEnvelope.self, from: data)

        switch http.statusCode {
        case 200...299:
            return envelope ?? AuthEnvelope(ok: true, token: nil, profile: nil, error: nil, errorMessage: nil)
        default:
            let message = envelope?.error ?? envelope?.errorMessage
            throw AppError.network(.httpError(statusCode: http.statusCode, message: message))
        }
    }
}

// MARK: - Wire envelope

/// The JSON shape `admin-portal-auth` returns for every action.
private struct AuthEnvelope: Decodable {
    let ok: Bool?
    let token: String?
    let profile: AdminProfile?
    let error: String?
    let errorMessage: String?
}

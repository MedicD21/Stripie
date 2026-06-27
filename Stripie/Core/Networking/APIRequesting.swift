import Foundation

/// Abstraction over the HTTP client so view models and services can be tested
/// against an in-memory stub instead of the live `APIClient`.
protocol APIRequesting: Sendable {
    func request<T: Decodable & Sendable>(_ endpoint: APIEndpoint) async throws -> T
}

extension APIClient: APIRequesting {}

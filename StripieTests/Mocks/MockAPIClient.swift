import Foundation
@testable import Stripie

/// In-memory stub for APIClient. Configure `responses` keyed by endpoint path.
actor MockAPIClient {
    typealias ResponseBuilder = (APIEndpoint) throws -> Any

    var responseBuilder: ResponseBuilder?
    var requestLog: [APIEndpoint] = []

    func stub(_ builder: @escaping ResponseBuilder) {
        responseBuilder = builder
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        requestLog.append(endpoint)
        guard let builder = responseBuilder else {
            throw NetworkError.invalidResponse
        }
        guard let result = try builder(endpoint) as? T else {
            throw NetworkError.decodingFailed("Stub returned wrong type for \(T.self)")
        }
        return result
    }
}

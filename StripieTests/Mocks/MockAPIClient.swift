import Foundation
@testable import Stripie

/// In-memory stub for `APIRequesting`. Configure a response builder that maps an
/// endpoint to a stubbed value; inspect `requestLog` to assert the calls made.
actor MockAPIClient: APIRequesting {
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

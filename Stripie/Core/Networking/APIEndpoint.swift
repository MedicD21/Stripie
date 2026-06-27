import Foundation

enum APIEndpoint {
    case connectionToken
    case createPaymentIntent(CreatePaymentIntentRequest)
    case capturePaymentIntent(id: String)
    case transactions(limit: Int, startingAfter: String?)

    var path: String {
        switch self {
        case .connectionToken:
            return "/terminal/connection_token"
        case .createPaymentIntent:
            return "/payment_intents"
        case .capturePaymentIntent(let id):
            return "/payment_intents/\(id)/capture"
        case .transactions:
            return "/transactions"
        }
    }

    var method: String {
        switch self {
        case .connectionToken, .createPaymentIntent, .capturePaymentIntent:
            return "POST"
        case .transactions:
            return "GET"
        }
    }

    var body: (any Encodable)? {
        switch self {
        case .createPaymentIntent(let req): return req
        default: return nil
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .transactions(let limit, let startingAfter):
            var items = [URLQueryItem(name: "limit", value: "\(limit)")]
            if let cursor = startingAfter {
                items.append(URLQueryItem(name: "starting_after", value: cursor))
            }
            return items
        default:
            return nil
        }
    }
}

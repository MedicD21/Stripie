import Foundation

// MARK: - Connection Token

struct ConnectionTokenResponse: Decodable, Sendable {
    let secret: String
}

// MARK: - Payment Intent

struct CreatePaymentIntentRequest: Encodable, Sendable {
    let amount: Int       // in cents
    let currency: String  // ISO 4217 lowercase, e.g. "usd"
    let description: String?

    init(amount: Int, currency: String = "usd", description: String? = nil) {
        self.amount = amount
        self.currency = currency
        self.description = description
    }
}

struct PaymentIntentResponse: Decodable, Sendable {
    let id: String
    let clientSecret: String
    let amount: Int
    let currency: String
    let status: String
}

struct CapturePaymentIntentResponse: Decodable, Sendable {
    let id: String
    let status: String
    let amount: Int
    let currency: String
    let createdAt: String?
}

// MARK: - Receipt

/// Customer contact captured at checkout so the backend can send a digital
/// receipt (Stripe emails when `email` is set) and store it in the payments DB.
struct SendReceiptRequest: Encodable, Sendable {
    let email: String?
    let phone: String?
}

struct SendReceiptResponse: Decodable, Sendable {
    let ok: Bool
}

// MARK: - Transaction List

struct TransactionListResponse: Decodable, Sendable {
    let transactions: [TransactionRecord]
    let hasMore: Bool
}

struct TransactionRecord: Decodable, Identifiable, Sendable {
    let id: String
    let amount: Int
    let currency: String
    let status: String
    let description: String?
    let createdAt: String
}

// MARK: - Error

struct APIErrorResponse: Decodable, Sendable {
    let detail: String?
    let message: String?

    var displayMessage: String {
        detail ?? message ?? "An unexpected error occurred."
    }
}

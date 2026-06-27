import Foundation

struct Transaction: Identifiable, Equatable, Sendable {
    let id: String
    let amount: Int       // in cents
    let currency: String
    let status: TransactionStatus
    let description: String?
    let createdAt: Date

    var formattedAmount: String {
        (Double(amount) / 100.0).formatted(.currency(code: currency.uppercased()))
    }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Mapping from API

    init(record: TransactionRecord) {
        self.id = record.id
        self.amount = record.amount
        self.currency = record.currency
        self.status = TransactionStatus(rawValue: record.status) ?? .unknown
        self.description = record.description

        let formatter = ISO8601DateFormatter()
        self.createdAt = formatter.date(from: record.createdAt) ?? Date(timeIntervalSince1970: 0)
    }
}

enum TransactionStatus: String, Equatable, Sendable {
    case succeeded
    case processing
    case requiresCapture  = "requires_capture"
    case cancelled
    case failed
    case unknown

    var displayName: String {
        switch self {
        case .succeeded:       return "Succeeded"
        case .processing:      return "Processing"
        case .requiresCapture: return "Pending"
        case .cancelled:       return "Cancelled"
        case .failed:          return "Failed"
        case .unknown:         return "Unknown"
        }
    }

    var isTerminal: Bool {
        self == .succeeded || self == .cancelled || self == .failed
    }
}

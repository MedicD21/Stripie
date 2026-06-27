import Foundation

enum PaymentState: Equatable {
    case idle
    case creatingIntent
    case collectingPayment
    case confirming
    case capturing
    case succeeded(amount: Int, currency: String)
    case failed(String)

    var isProcessing: Bool {
        switch self {
        case .creatingIntent, .collectingPayment, .confirming, .capturing:
            return true
        default:
            return false
        }
    }

    var statusMessage: String {
        switch self {
        case .idle:               return ""
        case .creatingIntent:     return "Preparing payment…"
        case .collectingPayment:  return "Present your card or device"
        case .confirming:         return "Confirming…"
        case .capturing:          return "Completing payment…"
        case .succeeded:          return "Payment successful"
        case .failed(let msg):    return msg
        }
    }
}

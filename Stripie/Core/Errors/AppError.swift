import Foundation

enum AppError: LocalizedError, Equatable {
    case network(NetworkError)
    case terminal(TerminalError)
    case location(LocationError)
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .network(let e):   return e.localizedDescription
        case .terminal(let e):  return e.localizedDescription
        case .location(let e):  return e.localizedDescription
        case .generic(let msg): return msg
        }
    }
}

enum NetworkError: LocalizedError, Equatable {
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingFailed(String)
    case unauthorized
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .httpError(let code, let msg):
            return msg ?? "HTTP error \(code)."
        case .decodingFailed(let detail):
            return "Failed to parse response: \(detail)"
        case .unauthorized:
            return "Authentication required. Please sign in again."
        case .timeout:
            return "The request timed out. Check your connection and try again."
        }
    }
}

enum TerminalError: LocalizedError, Equatable {
    case notInitialized
    case readerNotConnected
    case paymentFailed(String)
    case discoveryFailed(String)
    case connectionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Stripe Terminal is not initialized."
        case .readerNotConnected:
            return "No reader is connected. Please connect a reader first."
        case .paymentFailed(let msg):
            return "Payment failed: \(msg)"
        case .discoveryFailed(let msg):
            return "Reader discovery failed: \(msg)"
        case .connectionFailed(let msg):
            return "Reader connection failed: \(msg)"
        case .cancelled:
            return "The operation was cancelled."
        }
    }
}

enum LocationError: LocalizedError, Equatable {
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location access is required for Tap to Pay. Enable it in Settings."
        case .unavailable:
            return "Location services are unavailable on this device."
        }
    }
}

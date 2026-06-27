// Preview-only factory methods. Never import or use these in production code.
#if DEBUG
import Foundation

extension PaymentViewModel {
    static func preview() -> PaymentViewModel {
        let client = APIClient()
        let terminal = TerminalService(apiClient: client)
        return PaymentViewModel(terminal: terminal, apiClient: client)
    }
}

extension ReaderViewModel {
    static func preview() -> ReaderViewModel {
        let client = APIClient()
        let terminal = TerminalService(apiClient: client)
        let location = LocationService()
        return ReaderViewModel(terminal: terminal, location: location)
    }
}

extension TransactionListViewModel {
    static func preview() -> TransactionListViewModel {
        TransactionListViewModel(apiClient: APIClient())
    }
}

#endif

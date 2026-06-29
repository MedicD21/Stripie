// Preview-only factory methods. Never import or use these in production code.
#if DEBUG
import Foundation

extension PaymentViewModel {
    static func preview() -> PaymentViewModel {
        let client = APIClient()
        let terminal = TerminalService(apiClient: client)
        return PaymentViewModel(terminal: terminal, apiClient: client, location: LocationService())
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

/// No-op auth service so previews never touch the network.
struct PreviewAuthService: AuthServicing {
    var profile = AdminProfile(email: "admin@thegoodkitchen.org", displayName: "Test Admin")
    func requestLoginCode(email: String) async throws {}
    func verifyLoginCode(email: String, code: String) async throws -> String { "preview-token" }
    func fetchProfile(token: String) async throws -> AdminProfile { profile }
    func logout(token: String) async throws {}
}

#endif

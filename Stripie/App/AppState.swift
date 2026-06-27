import SwiftUI
import OSLog

/// Root application state — owns the dependency graph and exposes it via @Environment.
@Observable
@MainActor
final class AppState {

    let apiClient: APIClient
    let terminalService: TerminalService
    let locationService: LocationService

    private let logger = Logger(subsystem: "com.stripie", category: "AppState")

    init() {
        let client = APIClient()
        self.apiClient = client
        self.locationService = LocationService()
        self.terminalService = TerminalService(apiClient: client)
    }

    func onAppear() {
        terminalService.initialize()
        logger.info("App ready")
    }
}

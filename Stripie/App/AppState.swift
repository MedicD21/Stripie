import SwiftUI
import OSLog

/// Root application state — owns the dependency graph and exposes it via @Environment.
@Observable
@MainActor
final class AppState {

    let apiClient: APIClient
    let terminalService: TerminalService
    let locationService: LocationService
    let settingsStore: SettingsStore
    let authSession: AuthSessionStore

    private let logger = Logger(subsystem: "com.stripie", category: "AppState")

    init() {
        let client = APIClient()
        self.apiClient = client
        self.locationService = LocationService()
        self.terminalService = TerminalService(apiClient: client)
        self.settingsStore = SettingsStore()
        self.authSession = AuthSessionStore()
    }

    func onAppear() {
        terminalService.initialize()
        logger.info("App ready")
    }
}

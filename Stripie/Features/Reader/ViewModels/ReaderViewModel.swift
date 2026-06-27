import SwiftUI
import StripeTerminal
import OSLog

@Observable
@MainActor
final class ReaderViewModel {

    // MARK: - State

    private(set) var isLoading = false
    var error: AppError?

    // MARK: - Dependencies

    private let terminal: TerminalService
    private let location: LocationService
    private let logger = Logger(subsystem: "com.stripie", category: "ReaderViewModel")

    // MARK: - Computed

    var connectionState: ReaderConnectionState { terminal.connectionState }
    var discoveredReaders: [Reader] { terminal.discoveredReaders }
    var isDiscovering: Bool { terminal.isDiscovering }
    var updateProgress: Float? { terminal.readerUpdateProgress }

    // MARK: - Init

    init(terminal: TerminalService, location: LocationService) {
        self.terminal = terminal
        self.location = location
    }

    // MARK: - Actions

    func startDiscovery() async {
        guard await ensureLocationPermission() else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await terminal.startDiscovery()
        } catch {
            self.error = .terminal(error as? TerminalError ?? .discoveryFailed(error.localizedDescription))
            logger.error("Discovery failed: \(error.localizedDescription)")
        }
    }

    func stopDiscovery() {
        terminal.stopDiscovery()
    }

    func connect(to reader: Reader) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await terminal.connect(to: reader)
            logger.info("Connected to \(reader.label ?? "reader")")
        } catch {
            self.error = .terminal(error as? TerminalError ?? .connectionFailed(error.localizedDescription))
            logger.error("Connection failed: \(error.localizedDescription)")
        }
    }

    func disconnect() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await terminal.disconnect()
        } catch {
            self.error = .terminal(error as? TerminalError ?? .connectionFailed(error.localizedDescription))
        }
    }

    func dismissError() {
        error = nil
    }

    // MARK: - Private

    private func ensureLocationPermission() async -> Bool {
        let status = await location.requestAuthorization()
        guard location.isAuthorized else {
            error = .location(.permissionDenied)
            return false
        }
        return true
    }
}

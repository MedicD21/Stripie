// Requires: stripe-terminal-ios (https://github.com/stripe/stripe-terminal-ios)
// SPM: .package(url: "https://github.com/stripe/stripe-terminal-ios", .upToNextMinor(from: "4.0.0"))
// Xcode entitlements required:
//   - com.apple.developer.proximity-reader.payment.acceptance (Tap to Pay)
//   - NSLocationWhenInUseUsageDescription in Info.plist
import Foundation
import StripeTerminalSDK
import OSLog

/// Central service managing the Stripe Terminal SDK lifecycle.
///
/// Owns reader discovery, connection, and payment collection.
/// All state mutations are @MainActor-isolated and observable by SwiftUI.
@Observable
@MainActor
final class TerminalService: NSObject {

    // MARK: - Observable State

    private(set) var isInitialized = false
    private(set) var connectedReader: Reader?
    private(set) var connectionState: ReaderConnectionState = .disconnected
    private(set) var discoveredReaders: [Reader] = []
    private(set) var isDiscovering = false
    private(set) var readerUpdateProgress: Float?

    // MARK: - Private

    private let apiClient: any APIRequesting
    private var discoveryCancelable: Cancelable?
    private let logger = Logger(subsystem: "com.stripie", category: "TerminalService")

    // MARK: - Init

    init(apiClient: any APIRequesting) {
        self.apiClient = apiClient
    }

    // MARK: - Initialization

    func initialize() {
        guard !isInitialized else { return }

        let tokenProvider = BackendConnectionTokenProvider(apiClient: apiClient)
        let config = TerminalConfiguration()
        Terminal.initialize(configuration: config, tokenProvider: tokenProvider, delegate: self)
        isInitialized = true
        logger.info("Stripe Terminal initialized")
    }

    // MARK: - Discovery

    func startDiscovery() async throws {
        guard isInitialized else { throw TerminalError.notInitialized }

        stopDiscovery()
        isDiscovering = true
        discoveredReaders = []
        connectionState = .discovering

        let discoveryConfig = LocalMobileDiscoveryConfiguration(simulated: false)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            discoveryCancelable = Terminal.shared.discoverReaders(
                config: discoveryConfig,
                delegate: self
            ) { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isDiscovering = false
                    if let error {
                        if self.connectionState == .discovering {
                            self.connectionState = .disconnected
                        }
                        continuation.resume(throwing: TerminalError.discoveryFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func stopDiscovery() {
        discoveryCancelable?.cancel()
        discoveryCancelable = nil
        isDiscovering = false
        if case .discovering = connectionState {
            connectionState = .disconnected
        }
    }

    // MARK: - Connection

    func connect(to reader: Reader) async throws {
        guard isInitialized else { throw TerminalError.notInitialized }

        connectionState = .connecting

        let params = LocalMobileConnectionConfiguration(
            locationId: reader.location?.stripeId ?? "",
            enableAutoReconnect: true,
            autoReconnectDelegate: nil
        )

        let connected: Reader = try await withCheckedThrowingContinuation { continuation in
            Terminal.shared.connectLocalMobileReader(
                reader: reader,
                delegate: self,
                connectionConfig: params
            ) { [weak self] connectedReader, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.connectionState = .disconnected
                        continuation.resume(throwing: TerminalError.connectionFailed(error.localizedDescription))
                    } else if let connectedReader {
                        continuation.resume(returning: connectedReader)
                    } else {
                        continuation.resume(throwing: TerminalError.connectionFailed("No reader returned from connection"))
                    }
                }
            }
        }

        connectedReader = connected
        connectionState = .connected(connected)
        logger.info("Connected to reader: \(connected.label ?? "unknown")")
    }

    func disconnect() async throws {
        guard connectedReader != nil else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Terminal.shared.disconnectReader { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        continuation.resume(throwing: TerminalError.connectionFailed(error.localizedDescription))
                    } else {
                        self.connectedReader = nil
                        self.connectionState = .disconnected
                        self.logger.info("Reader disconnected")
                        continuation.resume()
                    }
                }
            }
        }
    }

    // MARK: - Payment Collection

    /// Collects and confirms a payment for the given PaymentIntent (created by the backend).
    /// After this returns, call the backend `/capture` endpoint.
    ///
    /// - Parameter onConfirming: Invoked after the payment method is collected and just
    ///   before the SDK confirms the intent, so the UI can reflect the `.confirming` state.
    func collectPayment(
        paymentIntentClientSecret: String,
        onConfirming: @MainActor () -> Void = {}
    ) async throws -> PaymentIntent {
        guard connectedReader != nil else { throw TerminalError.readerNotConnected }

        let intent: PaymentIntent = try await withCheckedThrowingContinuation { continuation in
            Terminal.shared.retrievePaymentIntent(clientSecret: paymentIntentClientSecret) { intent, error in
                Task { @MainActor in
                    if let error {
                        continuation.resume(throwing: TerminalError.paymentFailed(error.localizedDescription))
                    } else if let intent {
                        continuation.resume(returning: intent)
                    } else {
                        continuation.resume(throwing: TerminalError.paymentFailed("Could not retrieve PaymentIntent"))
                    }
                }
            }
        }

        let collected: PaymentIntent = try await withCheckedThrowingContinuation { continuation in
            Terminal.shared.collectPaymentMethod(intent) { collectedIntent, error in
                Task { @MainActor in
                    if let error {
                        continuation.resume(throwing: TerminalError.paymentFailed(error.localizedDescription))
                    } else if let collectedIntent {
                        continuation.resume(returning: collectedIntent)
                    } else {
                        continuation.resume(throwing: TerminalError.paymentFailed("Collection returned no intent"))
                    }
                }
            }
        }

        onConfirming()
        return try await confirm(paymentIntent: collected)
    }

    private func confirm(paymentIntent: PaymentIntent) async throws -> PaymentIntent {
        try await withCheckedThrowingContinuation { continuation in
            Terminal.shared.confirmPaymentIntent(paymentIntent) { confirmedIntent, error in
                Task { @MainActor in
                    if let error {
                        continuation.resume(throwing: TerminalError.paymentFailed(error.localizedDescription))
                    } else if let confirmedIntent {
                        continuation.resume(returning: confirmedIntent)
                    } else {
                        continuation.resume(throwing: TerminalError.paymentFailed("Confirmation returned no intent"))
                    }
                }
            }
        }
    }
}

// MARK: - TerminalDelegate

extension TerminalService: TerminalDelegate {
    nonisolated func terminal(_ terminal: Terminal, didReportUnexpectedReaderDisconnect reader: Reader) {
        Task { @MainActor in
            logger.warning("Unexpected disconnect: \(reader.label ?? "unknown")")
            connectedReader = nil
            connectionState = .disconnected
        }
    }

    nonisolated func terminal(_ terminal: Terminal, didChangeConnectionStatus status: ConnectionStatus) {
        logger.debug("Connection status: \(String(describing: status))")
    }
}

// MARK: - DiscoveryDelegate

extension TerminalService: DiscoveryDelegate {
    nonisolated func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        Task { @MainActor in
            discoveredReaders = readers
            logger.debug("Discovered \(readers.count) reader(s)")
        }
    }
}

// MARK: - LocalMobileReaderDelegate

extension TerminalService: LocalMobileReaderDelegate {
    nonisolated func localMobileReader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
        Task { @MainActor in
            readerUpdateProgress = 0
            logger.info("Reader software update started")
        }
    }

    nonisolated func localMobileReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {
        Task { @MainActor in
            readerUpdateProgress = progress
        }
    }

    nonisolated func localMobileReader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {
        Task { @MainActor in
            readerUpdateProgress = nil
            if let error {
                logger.error("Reader update failed: \(error.localizedDescription)")
            } else {
                logger.info("Reader software update complete")
            }
        }
    }

    nonisolated func localMobileReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {
        logger.debug("Reader input requested: \(String(describing: inputOptions))")
    }

    nonisolated func localMobileReader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {
        logger.debug("Reader display message: \(String(describing: displayMessage))")
    }
}

// MARK: - Connection Token Provider

/// Fetches ephemeral Terminal connection tokens from the Stripie backend.
private final class BackendConnectionTokenProvider: NSObject, ConnectionTokenProvider, @unchecked Sendable {
    private let apiClient: any APIRequesting
    private let logger = Logger(subsystem: "com.stripie", category: "TokenProvider")

    init(apiClient: any APIRequesting) {
        self.apiClient = apiClient
    }

    func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        Task {
            do {
                let response: ConnectionTokenResponse = try await apiClient.request(.connectionToken)
                completion(response.secret, nil)
                self.logger.debug("Connection token fetched successfully")
            } catch {
                self.logger.error("Failed to fetch connection token: \(error.localizedDescription)")
                completion(nil, error)
            }
        }
    }
}

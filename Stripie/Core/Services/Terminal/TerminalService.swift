// Requires: stripe-terminal-ios (https://github.com/stripe/stripe-terminal-ios)
// SPM: .package(url: "https://github.com/stripe/stripe-terminal-ios", .upToNextMinor(from: "4.0.0"))
// Xcode entitlements required:
//   - com.apple.developer.proximity-reader.payment.acceptance (Tap to Pay)
//   - NSLocationWhenInUseUsageDescription in Info.plist
import Foundation
import StripeTerminal
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
    private let tokenProvider: BackendConnectionTokenProvider
    private var discoveryCancelable: Cancelable?
    private let logger = Logger(subsystem: "com.stripie", category: "TerminalService")

    // MARK: - Init

    init(apiClient: any APIRequesting) {
        self.apiClient = apiClient
        self.tokenProvider = BackendConnectionTokenProvider(apiClient: apiClient)
    }

    // MARK: - Initialization

    func initialize() {
        guard !isInitialized else { return }

        // In v4 the token provider must be set before `Terminal.shared` is first
        // accessed; the delegate is assigned on the shared instance afterward.
        if !Terminal.hasTokenProvider() {
            Terminal.setTokenProvider(tokenProvider)
        }
        Terminal.shared.delegate = self
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

        let discoveryConfig = try TapToPayDiscoveryConfigurationBuilder()
            .setSimulated(false)
            .build()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            discoveryCancelable = Terminal.shared.discoverReaders(
                discoveryConfig,
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
        discoveryCancelable?.cancel { [logger] error in
            if let error {
                logger.debug("Cancel discovery failed: \(error.localizedDescription)")
            }
        }
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

        let params = try TapToPayConnectionConfigurationBuilder(
            delegate: self,
            locationId: reader.location?.stripeId ?? ""
        ).build()

        let connected: Reader
        do {
            connected = try await withCheckedThrowingContinuation { continuation in
                Terminal.shared.connectReader(
                    reader,
                    connectionConfig: params
                ) { connectedReader, error in
                    if let error {
                        continuation.resume(throwing: TerminalError.connectionFailed(error.localizedDescription))
                    } else if let connectedReader {
                        continuation.resume(returning: connectedReader)
                    } else {
                        continuation.resume(throwing: TerminalError.connectionFailed("No reader returned from connection"))
                    }
                }
            }
        } catch {
            connectionState = .disconnected
            throw error
        }

        connectedReader = connected
        connectionState = .connected(connected)
        logger.info("Connected to reader: \(connected.label ?? "unknown")")
    }

    func disconnect() async throws {
        guard connectedReader != nil else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Terminal.shared.disconnectReader { error in
                if let error {
                    continuation.resume(throwing: TerminalError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }

        connectedReader = nil
        connectionState = .disconnected
        logger.info("Reader disconnected")
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
                if let error {
                    continuation.resume(throwing: TerminalError.paymentFailed(error.localizedDescription))
                } else if let intent {
                    continuation.resume(returning: intent)
                } else {
                    continuation.resume(throwing: TerminalError.paymentFailed("Could not retrieve PaymentIntent"))
                }
            }
        }

        let collected: PaymentIntent = try await withCheckedThrowingContinuation { continuation in
            Terminal.shared.collectPaymentMethod(intent) { collectedIntent, error in
                if let error {
                    continuation.resume(throwing: TerminalError.paymentFailed(error.localizedDescription))
                } else if let collectedIntent {
                    continuation.resume(returning: collectedIntent)
                } else {
                    continuation.resume(throwing: TerminalError.paymentFailed("Collection returned no intent"))
                }
            }
        }

        onConfirming()
        return try await confirm(paymentIntent: collected)
    }

    private func confirm(paymentIntent: PaymentIntent) async throws -> PaymentIntent {
        try await withCheckedThrowingContinuation { continuation in
            Terminal.shared.confirmPaymentIntent(paymentIntent) { confirmedIntent, error in
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

// MARK: - TerminalDelegate

extension TerminalService: TerminalDelegate {
    nonisolated func terminal(_ terminal: Terminal, didChangeConnectionStatus status: ConnectionStatus) {
        MainActor.assumeIsolated {
            logger.debug("Connection status: \(String(describing: status))")
            // In v4, an unexpected reader disconnect surfaces here as a
            // transition to `.notConnected` rather than a dedicated callback.
            if status == .notConnected, connectedReader != nil {
                logger.warning("Reader disconnected unexpectedly")
                connectedReader = nil
                connectionState = .disconnected
            }
        }
    }
}

// MARK: - DiscoveryDelegate

extension TerminalService: DiscoveryDelegate {
    nonisolated func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        // The Stripe Terminal SDK delivers delegate callbacks on the main thread,
        // so we can safely assume MainActor isolation here. This avoids hopping the
        // non-Sendable `[Reader]` across a Task boundary (Swift 6 region isolation).
        MainActor.assumeIsolated {
            discoveredReaders = readers
            logger.debug("Discovered \(readers.count) reader(s)")
        }
    }
}

// MARK: - TapToPayReaderDelegate

extension TerminalService: TapToPayReaderDelegate {
    nonisolated func tapToPayReader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
        MainActor.assumeIsolated {
            readerUpdateProgress = 0
            logger.info("Reader software update started")
        }
    }

    nonisolated func tapToPayReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {
        MainActor.assumeIsolated {
            readerUpdateProgress = progress
        }
    }

    nonisolated func tapToPayReader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {
        MainActor.assumeIsolated {
            readerUpdateProgress = nil
            if let error {
                logger.error("Reader update failed: \(error.localizedDescription)")
            } else {
                logger.info("Reader software update complete")
            }
        }
    }

    nonisolated func tapToPayReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {
        logger.debug("Reader input requested: \(String(describing: inputOptions))")
    }

    nonisolated func tapToPayReader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {
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
        Task { [apiClient, logger] in
            do {
                let response: ConnectionTokenResponse = try await apiClient.request(.connectionToken)
                logger.debug("Connection token fetched successfully")
                completion(response.secret, nil)
            } catch {
                // Re-wrap as a locally-constructed NSError so a non-Sendable error
                // from the request layer doesn't cross into the SDK completion.
                let message = error.localizedDescription
                logger.error("Failed to fetch connection token: \(message)")
                let wrapped = NSError(
                    domain: "com.stripie.TokenProvider",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
                completion(nil, wrapped)
            }
        }
    }
}

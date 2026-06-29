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
    /// Optional explicit location override from configuration.
    private let configuredLocationId: String

    /// When true, discovery uses Stripe's simulated Tap to Pay reader so the full
    /// charge flow can be exercised on the Simulator (no NFC hardware needed).
    /// Real Tap to Pay requires a physical iPhone, so this defaults on only in
    /// DEBUG builds and is always false in release.
    private let simulated: Bool

    // MARK: - Init

    init(apiClient: any APIRequesting, simulated: Bool? = nil, configuration: AppConfiguration = .shared) {
        self.apiClient = apiClient
        self.tokenProvider = BackendConnectionTokenProvider(apiClient: apiClient)
        self.configuredLocationId = configuration.locationId
        #if DEBUG
        self.simulated = simulated ?? true
        #else
        self.simulated = simulated ?? false
        #endif
    }

    // MARK: - OS support (App Review requirement 1.4)

    /// Minimum iOS version Apple requires for full Tap to Pay on iPhone support.
    private static let minimumOSVersion = OperatingSystemVersion(majorVersion: 17, minorVersion: 6, patchVersion: 0)

    /// False on devices older than iOS 17.6 (where the SDK reports
    /// `osVersionNotSupported`). Always true for the simulated reader so the
    /// Simulator can still exercise the flow.
    var isOSVersionSupported: Bool {
        if simulated { return true }
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(Self.minimumOSVersion)
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
        if simulated {
            // A successful Visa is returned for the simulated tap during collection.
            Terminal.shared.simulatorConfiguration.simulatedCard = SimulatedCard(type: .visa)
            logger.info("Stripe Terminal initialized (SIMULATED reader)")
        } else {
            logger.info("Stripe Terminal initialized")
        }
        isInitialized = true
    }

    // MARK: - Discovery

    func startDiscovery() async throws {
        guard isInitialized else { throw TerminalError.notInitialized }

        stopDiscovery()
        isDiscovering = true
        discoveredReaders = []
        connectionState = .discovering

        let discoveryConfig = try TapToPayDiscoveryConfigurationBuilder()
            .setSimulated(simulated)
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

        // Tap to Pay requires a valid Stripe Terminal Location. Resolve it from
        // (1) the reader, (2) an explicit config override, then (3) the account's
        // first location via the SDK. The simulated reader carries its own.
        let resolvedLocationId: String
        if let readerLoc = reader.location?.stripeId, !readerLoc.isEmpty {
            resolvedLocationId = readerLoc
        } else if !configuredLocationId.isEmpty {
            resolvedLocationId = configuredLocationId
        } else if let fetched = await firstAvailableLocationId(), !fetched.isEmpty {
            resolvedLocationId = fetched
        } else {
            connectionState = .disconnected
            throw TerminalError.connectionFailed("No Stripe Terminal location found. Create one in your Stripe dashboard under Terminal → Locations.")
        }

        let params = try TapToPayConnectionConfigurationBuilder(
            delegate: self,
            locationId: resolvedLocationId
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

    /// Fetches the account's first Stripe Terminal Location id via the SDK, so we
    /// don't have to hardcode it. Returns nil if none exist or on error.
    private func firstAvailableLocationId() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let params = try? ListLocationsParametersBuilder().build()
            Terminal.shared.listLocations(parameters: params) { [logger] locations, _, error in
                if let error {
                    logger.error("listLocations failed: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: locations?.first?.stripeId)
                }
            }
        }
    }

    /// Best-effort warm-up so Tap to Pay is ready before checkout (App Review
    /// requirements 1.5 and 5.6). Runs discovery and connects to the first
    /// available reader. Silently no-ops if already connected or on failure —
    /// the Reader screen remains the explicit fallback for granting permission.
    func warmUp() async {
        guard isInitialized, isOSVersionSupported,
              connectedReader == nil, !isDiscovering,
              case .disconnected = connectionState else { return }
        do {
            try await startDiscovery()
            // Discovery delivers readers asynchronously via the delegate.
            for _ in 0..<20 {
                if let reader = discoveredReaders.first {
                    stopDiscovery()
                    try await connect(to: reader)
                    return
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            stopDiscovery()
        } catch {
            logger.debug("Tap to Pay warm-up skipped: \(error.localizedDescription)")
        }
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

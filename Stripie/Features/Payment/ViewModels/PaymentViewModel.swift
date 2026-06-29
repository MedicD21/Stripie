import SwiftUI
import StripeTerminal
import OSLog

@Observable
@MainActor
final class PaymentViewModel {

    // MARK: - State

    private(set) var paymentState: PaymentState = .idle
    var enteredAmountCents: Int = 0   // amount in cents
    var description: String = ""
    var error: AppError?

    /// The most recent successfully-captured PaymentIntent id, used to attach a
    /// receipt after the charge completes.
    private(set) var lastPaymentIntentId: String?

    // MARK: - Dependencies

    private let terminal: TerminalService
    private let location: LocationService
    private let apiClient: any APIRequesting
    private let logger = Logger(subsystem: "com.stripie", category: "PaymentViewModel")

    /// True while we're connecting/warming up the reader on demand (when the user
    /// taps Charge before Tap to Pay is ready). Drives the "Preparing…" indicator.
    private(set) var isPreparingReader = false

    // MARK: - Computed

    var readerConnectionState: ReaderConnectionState { terminal.connectionState }
    var isReaderConnected: Bool { terminal.connectionState.isConnected }
    var isTapToPaySupported: Bool { terminal.isOSVersionSupported }
    var readerUpdateProgress: Float? { terminal.readerUpdateProgress }
    var canCharge: Bool {
        enteredAmountCents > 0 && isReaderConnected && isTapToPaySupported && !paymentState.isProcessing
    }
    /// Whether the Tap to Pay button should be tappable. Deliberately does NOT
    /// require a connected reader (App Review 5.3: the button is never greyed out
    /// for that reason) — tapping connects on demand.
    var canStartCharge: Bool {
        enteredAmountCents > 0 && isTapToPaySupported && !paymentState.isProcessing && !isPreparingReader
    }

    var formattedAmount: String {
        let dollars = Double(enteredAmountCents) / 100.0
        return dollars.formatted(.currency(code: "USD"))
    }

    // MARK: - Init

    init(terminal: TerminalService, apiClient: any APIRequesting, location: LocationService) {
        self.terminal = terminal
        self.apiClient = apiClient
        self.location = location
    }

    // MARK: - Actions

    /// UI entry point for the Charge button and quick-charge chips. If Tap to Pay
    /// isn't connected yet, it prepares the reader first (which presents Apple's
    /// T&C on first use), then charges — so the button is never a dead end.
    func startCharge() async {
        guard canStartCharge else { return }
        if !isReaderConnected {
            await ensureReaderReady()
            guard isReaderConnected else { return }  // error already surfaced
        }
        await charge()
    }

    /// Sets the amount from a quick-charge preset and immediately starts the flow.
    func startQuickCharge(cents: Int) async {
        enteredAmountCents = cents
        await startCharge()
    }

    private func ensureReaderReady() async {
        isPreparingReader = true
        defer { isPreparingReader = false }

        _ = await location.requestAuthorization()
        guard location.isAuthorized else {
            error = .location(.permissionDenied)
            return
        }
        await terminal.warmUp()
        if !isReaderConnected {
            error = .terminal(.readerNotConnected)
        }
    }

    func charge() async {
        guard canCharge else { return }

        do {
            // 1. Create PaymentIntent on backend
            paymentState = .creatingIntent
            let request = CreatePaymentIntentRequest(
                amount: enteredAmountCents,
                currency: "usd",
                description: description.isEmpty ? nil : description
            )
            let intentResponse: PaymentIntentResponse = try await apiClient.request(.createPaymentIntent(request))
            logger.info("PaymentIntent created: \(intentResponse.id)")

            // 2. Collect payment method via Terminal (Tap to Pay), then confirm.
            paymentState = .collectingPayment
            let confirmedIntent = try await terminal.collectPayment(
                paymentIntentClientSecret: intentResponse.clientSecret,
                onConfirming: { [weak self] in self?.paymentState = .confirming }
            )
            logger.info("Payment collected and confirmed: \(confirmedIntent.stripeId ?? "")")

            // 3. Capture on backend (completes the charge)
            paymentState = .capturing
            let _: CapturePaymentIntentResponse = try await apiClient.request(
                .capturePaymentIntent(id: intentResponse.id)
            )

            lastPaymentIntentId = intentResponse.id
            paymentState = .succeeded(amount: enteredAmountCents, currency: "usd")
            logger.info("Payment captured: \(intentResponse.id)")

        } catch let appError as AppError {
            paymentState = .failed(appError.localizedDescription)
            error = appError
            logger.error("Payment failed: \(appError.localizedDescription)")

        } catch let terminalError as TerminalError {
            let message = terminalError.localizedDescription
            paymentState = .failed(message)
            error = .terminal(terminalError)
            logger.error("Terminal error: \(message)")

        } catch {
            paymentState = .failed(error.localizedDescription)
            self.error = .generic(error.localizedDescription)
            logger.error("Unexpected error: \(error.localizedDescription)")
        }
    }

    /// Sends a digital receipt for the last captured payment. The backend emails
    /// it (via Stripe `receipt_email`) and stores the contact in the payments DB.
    /// At least one of `email`/`phone` must be non-empty.
    func sendReceipt(email: String?, phone: String?) async throws {
        guard let id = lastPaymentIntentId else { throw AppError.generic("No payment to receipt.") }
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = SendReceiptRequest(
            email: (trimmedEmail?.isEmpty == false) ? trimmedEmail : nil,
            phone: (trimmedPhone?.isEmpty == false) ? trimmedPhone : nil
        )
        guard request.email != nil || request.phone != nil else {
            throw AppError.generic("Enter an email or phone number.")
        }
        let _: SendReceiptResponse = try await apiClient.request(.sendReceipt(id: id, request))
        logger.info("Receipt sent for \(id)")
    }

    func reset() {
        paymentState = .idle
        enteredAmountCents = 0
        description = ""
        error = nil
        lastPaymentIntentId = nil
    }

    func dismissError() {
        error = nil
        if case .failed = paymentState {
            paymentState = .idle
        }
    }

    // MARK: - Keypad Input

    func appendDigit(_ digit: Int) {
        guard !paymentState.isProcessing else { return }
        let next = enteredAmountCents * 10 + digit
        guard next <= 99_999_99 else { return } // cap at $999,999.99
        enteredAmountCents = next
    }

    func deleteLastDigit() {
        guard !paymentState.isProcessing else { return }
        enteredAmountCents /= 10
    }
}

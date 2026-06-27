import SwiftUI
import StripeTerminalSDK
import OSLog

@Observable
@MainActor
final class PaymentViewModel {

    // MARK: - State

    private(set) var paymentState: PaymentState = .idle
    var enteredAmountCents: Int = 0   // amount in cents
    var description: String = ""
    var error: AppError?

    // MARK: - Dependencies

    private let terminal: TerminalService
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "com.stripie", category: "PaymentViewModel")

    // MARK: - Computed

    var readerConnectionState: ReaderConnectionState { terminal.connectionState }
    var isReaderConnected: Bool { terminal.connectionState.isConnected }
    var canCharge: Bool { enteredAmountCents > 0 && isReaderConnected && !paymentState.isProcessing }

    var formattedAmount: String {
        let dollars = Double(enteredAmountCents) / 100.0
        return dollars.formatted(.currency(code: "USD"))
    }

    // MARK: - Init

    init(terminal: TerminalService, apiClient: APIClient) {
        self.terminal = terminal
        self.apiClient = apiClient
    }

    // MARK: - Actions

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

            // 2. Collect payment method via Terminal (Tap to Pay)
            paymentState = .collectingPayment
            let confirmedIntent = try await terminal.collectPayment(
                paymentIntentClientSecret: intentResponse.clientSecret
            )
            logger.info("Payment collected and confirmed: \(confirmedIntent.stripeId ?? "")")

            // 3. Capture on backend (completes the charge)
            paymentState = .capturing
            let _: CapturePaymentIntentResponse = try await apiClient.request(
                .capturePaymentIntent(id: intentResponse.id)
            )

            paymentState = .succeeded(amount: enteredAmountCents, currency: "usd")
            logger.info("Payment captured: \(intentResponse.id)")

        } catch let appError as AppError {
            paymentState = .failed(appError.localizedDescription ?? "Payment failed")
            error = appError
            logger.error("Payment failed: \(appError.localizedDescription ?? "")")

        } catch let terminalError as TerminalError {
            let message = terminalError.localizedDescription ?? "Payment failed"
            paymentState = .failed(message)
            error = .terminal(terminalError)
            logger.error("Terminal error: \(message)")

        } catch {
            paymentState = .failed(error.localizedDescription)
            self.error = .generic(error.localizedDescription)
            logger.error("Unexpected error: \(error.localizedDescription)")
        }
    }

    func reset() {
        paymentState = .idle
        enteredAmountCents = 0
        description = ""
        error = nil
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

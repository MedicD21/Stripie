import Testing
import Foundation
@testable import Stripie

@Suite("Receipt")
struct ReceiptTests {

    @Test("Formats amount as currency")
    func testFormattedAmount() {
        #expect(Receipt(amountCents: 2450, currency: "usd").formattedAmount == "$24.50")
        #expect(Receipt(amountCents: 1000, currency: "usd").formattedAmount == "$10.00")
    }

    @Test("Receipt text includes merchant and amount")
    func testReceiptText() {
        let text = Receipt(amountCents: 2450, currency: "usd").text
        #expect(text.contains("The Good Kitchen"))
        #expect(text.contains("$24.50"))
        #expect(text.contains("Tap to Pay"))
    }
}

@Suite("TerminalError")
struct TerminalErrorTests {

    @Test("osVersionNotSupported has an actionable message")
    func testOSVersionMessage() {
        let message = TerminalError.osVersionNotSupported.localizedDescription
        #expect(message.contains("17.6"))
        #expect(message.lowercased().contains("update"))
    }
}

@MainActor
@Suite("PaymentViewModel receipts")
struct PaymentReceiptTests {

    @Test("sendReceipt with no contact info throws and makes no request")
    func testSendReceiptRequiresContact() async {
        let mock = MockAPIClient()
        let terminal = TerminalService(apiClient: mock)
        let vm = PaymentViewModel(terminal: terminal, apiClient: mock, location: LocationService())
        // No lastPaymentIntentId yet → should throw before any request.
        await #expect(throws: AppError.self) {
            try await vm.sendReceipt(email: "  ", phone: "")
        }
        let calls = await mock.requestLog
        #expect(calls.isEmpty)
    }
}

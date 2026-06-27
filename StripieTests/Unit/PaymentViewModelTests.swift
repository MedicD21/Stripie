import Testing
import Foundation
@testable import Stripie

@MainActor
@Suite("PaymentViewModel")
struct PaymentViewModelTests {

    // MARK: - Amount Input

    @Test("Appending digits builds correct cent amount")
    func testDigitInput() {
        let vm = PaymentViewModel.makeTestInstance()
        vm.appendDigit(2)
        vm.appendDigit(4)
        vm.appendDigit(5)
        vm.appendDigit(0)
        #expect(vm.enteredAmountCents == 2450)
        #expect(vm.formattedAmount == "$24.50")
    }

    @Test("Delete removes last digit")
    func testDeleteLastDigit() {
        let vm = PaymentViewModel.makeTestInstance()
        vm.appendDigit(1)
        vm.appendDigit(0)
        vm.deleteLastDigit()
        #expect(vm.enteredAmountCents == 1)
    }

    @Test("Cannot exceed maximum amount")
    func testMaximumAmount() {
        let vm = PaymentViewModel.makeTestInstance()
        for _ in 0..<10 { vm.appendDigit(9) }
        #expect(vm.enteredAmountCents <= 9_999_999)
    }

    // MARK: - State

    @Test("Reset clears all state")
    func testReset() {
        let vm = PaymentViewModel.makeTestInstance()
        vm.appendDigit(5)
        vm.appendDigit(0)
        vm.reset()
        #expect(vm.enteredAmountCents == 0)
        #expect(vm.paymentState == .idle)
    }

    @Test("canCharge is false when amount is zero")
    func testCanChargeRequiresAmount() {
        let vm = PaymentViewModel.makeTestInstance()
        #expect(!vm.canCharge)
    }
}

// MARK: - Test Factory

private extension PaymentViewModel {
    static func makeTestInstance() -> PaymentViewModel {
        let client = APIClient()
        let terminal = TerminalService(apiClient: client)
        return PaymentViewModel(terminal: terminal, apiClient: client)
    }
}

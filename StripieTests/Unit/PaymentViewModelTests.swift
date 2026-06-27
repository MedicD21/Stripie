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

    // MARK: - Charge Flow

    // `charge()` is guarded by `canCharge`, which requires a connected Stripe
    // Terminal reader. A reader can only be obtained from the live SDK, so the
    // full collect/confirm/capture path is covered by integration testing on a
    // device. Here we verify the guard: with no reader connected, `charge()`
    // makes no backend calls and leaves state untouched.
    @Test("charge does nothing when no reader is connected")
    func testChargeRequiresConnectedReader() async {
        let mock = MockAPIClient()
        await mock.stub { _ in throw NetworkError.invalidResponse }
        let vm = PaymentViewModel.makeTestInstance(apiClient: mock)
        vm.appendDigit(5)
        vm.appendDigit(0) // $0.50 entered, but no reader connected.

        #expect(!vm.canCharge)
        await vm.charge()

        let calls = await mock.requestLog
        #expect(calls.isEmpty)
        #expect(vm.paymentState == .idle)
    }
}

// MARK: - Test Factory

private extension PaymentViewModel {
    static func makeTestInstance(
        apiClient: any APIRequesting = MockAPIClient()
    ) -> PaymentViewModel {
        let terminal = TerminalService(apiClient: apiClient)
        return PaymentViewModel(terminal: terminal, apiClient: apiClient)
    }
}

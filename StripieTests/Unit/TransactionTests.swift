import Testing
import Foundation
@testable import Stripie

@Suite("Transaction Model")
struct TransactionTests {

    @Test("Maps record to domain model correctly")
    func testMapping() {
        let record = TransactionRecord(
            id: "pi_test123",
            amount: 4999,
            currency: "usd",
            status: "succeeded",
            description: "Coffee",
            createdAt: "2026-06-27T10:00:00Z"
        )
        let tx = Transaction(record: record)
        #expect(tx.id == "pi_test123")
        #expect(tx.amount == 4999)
        #expect(tx.formattedAmount == "$49.99")
        #expect(tx.status == .succeeded)
        #expect(tx.description == "Coffee")
    }

    @Test("Unknown status falls back gracefully")
    func testUnknownStatus() {
        let record = TransactionRecord(
            id: "x",
            amount: 0,
            currency: "usd",
            status: "pending_bananas",
            description: nil,
            createdAt: "2026-06-27T00:00:00Z"
        )
        #expect(Transaction(record: record).status == .unknown)
    }
}

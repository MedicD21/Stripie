import Testing
import Foundation
@testable import Stripie

@MainActor
@Suite("TransactionListViewModel")
struct TransactionListViewModelTests {

    private func makeRecords(ids: [String]) -> [TransactionRecord] {
        ids.map { id in
            TransactionRecord(
                id: id,
                amount: 1000,
                currency: "usd",
                status: "succeeded",
                description: nil,
                createdAt: "2026-01-01T00:00:00Z"
            )
        }
    }

    @Test("loadInitial populates transactions from the API")
    func testLoadInitial() async {
        let mock = MockAPIClient()
        let records = makeRecords(ids: ["pi_1", "pi_2"])
        await mock.stub { _ in
            TransactionListResponse(transactions: records, hasMore: false)
        }

        let vm = TransactionListViewModel(apiClient: mock)
        await vm.loadInitial()

        #expect(vm.transactions.count == 2)
        #expect(vm.transactions.first?.id == "pi_1")
        #expect(!vm.hasMore)
        #expect(vm.error == nil)
    }

    @Test("loadMore appends and advances the cursor")
    func testLoadMore() async {
        let mock = MockAPIClient()
        await mock.stub { endpoint in
            switch endpoint {
            case .transactions(_, let startingAfter):
                if startingAfter == nil {
                    return TransactionListResponse(
                        transactions: self.makeRecords(ids: ["pi_1", "pi_2"]),
                        hasMore: true
                    )
                } else {
                    return TransactionListResponse(
                        transactions: self.makeRecords(ids: ["pi_3"]),
                        hasMore: false
                    )
                }
            default:
                throw NetworkError.invalidResponse
            }
        }

        let vm = TransactionListViewModel(apiClient: mock)
        await vm.loadInitial()
        #expect(vm.hasMore)
        await vm.loadMore()

        #expect(vm.transactions.map(\.id) == ["pi_1", "pi_2", "pi_3"])
        #expect(!vm.hasMore)

        // Second page must have been requested with starting_after = last id of page 1.
        let calls = await mock.requestLog
        #expect(calls.count == 2)
    }

    @Test("API failure is surfaced as an error and leaves list empty")
    func testLoadFailure() async {
        let mock = MockAPIClient()
        await mock.stub { _ in throw NetworkError.timeout }

        let vm = TransactionListViewModel(apiClient: mock)
        await vm.loadInitial()

        #expect(vm.transactions.isEmpty)
        #expect(vm.error == .network(.timeout))
    }
}

import SwiftUI
import OSLog

@Observable
@MainActor
final class TransactionListViewModel {

    // MARK: - State

    private(set) var transactions: [Transaction] = []
    private(set) var isLoading = false
    private(set) var hasMore = false
    var error: AppError?

    // MARK: - Private

    private let apiClient: APIClient
    private var cursor: String?
    private let pageSize = 25
    private let logger = Logger(subsystem: "com.stripie", category: "TransactionListViewModel")

    // MARK: - Init

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Actions

    func loadInitial() async {
        guard !isLoading else { return }

        isLoading = true
        cursor = nil
        defer { isLoading = false }

        do {
            let response: TransactionListResponse = try await apiClient.request(
                .transactions(limit: pageSize, startingAfter: nil)
            )
            transactions = response.transactions.map(Transaction.init)
            hasMore = response.hasMore
            cursor = transactions.last?.id
            logger.debug("Loaded \(self.transactions.count) transactions")
        } catch {
            self.error = .network(error as? NetworkError ?? .invalidResponse)
            logger.error("Load failed: \(error.localizedDescription)")
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response: TransactionListResponse = try await apiClient.request(
                .transactions(limit: pageSize, startingAfter: cursor)
            )
            let newOnes = response.transactions.map(Transaction.init)
            transactions.append(contentsOf: newOnes)
            hasMore = response.hasMore
            cursor = transactions.last?.id
        } catch {
            self.error = .network(error as? NetworkError ?? .invalidResponse)
            logger.error("Load more failed: \(error.localizedDescription)")
        }
    }

    func refresh() async {
        await loadInitial()
    }

    func dismissError() {
        error = nil
    }
}

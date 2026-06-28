import SwiftUI

struct TransactionListView: View {
    @State private var viewModel: TransactionListViewModel

    init(viewModel: TransactionListViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.transactions.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "creditcard",
                        description: Text("Your payment history will appear here.")
                    )
                } else {
                    transactionList
                }
            }
            .navigationTitle("Transactions")
            .refreshable { await viewModel.refresh() }
            .errorBanner($viewModel.error)
            .task { await viewModel.loadInitial() }
        }
    }

    private var transactionList: some View {
        List {
            ForEach(viewModel.transactions) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRowView(transaction: transaction)
                }
                .onAppear {
                    if transaction.id == viewModel.transactions.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
            }

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Detail

struct TransactionDetailView: View {
    let transaction: Transaction

    var body: some View {
        List {
            Section {
                detailRow("Amount", value: transaction.formattedAmount)
                detailRow("Status", value: transaction.status.displayName)
                detailRow("Date", value: transaction.formattedDate)
                detailRow("ID", value: transaction.id)
                if let desc = transaction.description {
                    detailRow("Description", value: desc)
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Row

struct TransactionRowView: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description ?? "Payment")
                    .font(.body)
                Text(transaction.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(transaction.formattedAmount)
                .font(.body.weight(.medium))
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(iconBackground)
            Image(systemName: iconName)
                .foregroundStyle(iconForeground)
                .font(.system(size: 16, weight: .medium))
        }
    }

    private var iconName: String {
        switch transaction.status {
        case .succeeded:       return "checkmark"
        case .processing:      return "clock"
        case .requiresCapture: return "clock.badge.exclamationmark"
        case .cancelled:       return "xmark"
        case .failed:          return "exclamationmark"
        case .unknown:         return "questionmark"
        }
    }

    private var iconBackground: Color {
        switch transaction.status {
        case .succeeded: return .green.opacity(0.15)
        case .failed:    return .red.opacity(0.15)
        default:         return .orange.opacity(0.15)
        }
    }

    private var iconForeground: Color {
        switch transaction.status {
        case .succeeded: return .green
        case .failed:    return .red
        default:         return .orange
        }
    }
}

#if DEBUG
#Preview {
    TransactionListView(viewModel: .preview())
}
#endif

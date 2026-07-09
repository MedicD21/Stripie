import SwiftUI

/// iPad-only "Charge" tab content: `PaymentView` and `TransactionListView` side
/// by side, since iPad has room for both at once instead of separate tabs.
struct PaymentSplitView: View {
    let paymentViewModel: PaymentViewModel
    let transactionsViewModel: TransactionListViewModel

    var body: some View {
        HStack(spacing: 0) {
            PaymentView(viewModel: paymentViewModel)

            Divider()

            // Nudge the pane's content off the divider — the nav bar's large
            // title otherwise sits flush against it.
            TransactionListView(viewModel: transactionsViewModel)
                .padding(.leading, 8)
        }
    }
}

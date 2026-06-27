import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            Tab("Charge", systemImage: "creditcard.fill") {
                PaymentView(
                    viewModel: PaymentViewModel(
                        terminal: appState.terminalService,
                        apiClient: appState.apiClient
                    )
                )
            }

            Tab("Transactions", systemImage: "list.bullet.rectangle") {
                TransactionListView(
                    viewModel: TransactionListViewModel(apiClient: appState.apiClient)
                )
            }

            Tab("Reader", systemImage: "iphone.radiowaves.left.and.right") {
                ReaderConnectionView(
                    viewModel: ReaderViewModel(
                        terminal: appState.terminalService,
                        location: appState.locationService
                    )
                )
            }
        }
        .task { appState.onAppear() }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}

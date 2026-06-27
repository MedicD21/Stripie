import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            PaymentView(
                viewModel: PaymentViewModel(
                    terminal: appState.terminalService,
                    apiClient: appState.apiClient
                )
            )
            .tabItem { Label("Charge", systemImage: "creditcard.fill") }

            TransactionListView(
                viewModel: TransactionListViewModel(apiClient: appState.apiClient)
            )
            .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }

            ReaderConnectionView(
                viewModel: ReaderViewModel(
                    terminal: appState.terminalService,
                    location: appState.locationService
                )
            )
            .tabItem { Label("Reader", systemImage: "iphone.radiowaves.left.and.right") }
        }
        .task { appState.onAppear() }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}

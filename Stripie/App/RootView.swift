import SwiftUI

struct RootView: View {
    @Environment(AuthSessionStore.self) private var auth
    @State private var splashFinished = false

    var body: some View {
        ZStack {
            content

            if !splashFinished {
                SplashVideoView {
                    guard !splashFinished else { return }
                    withAnimation(.easeOut(duration: 0.4)) { splashFinished = true }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .task { await auth.bootstrap() }
    }

    @ViewBuilder
    private var content: some View {
        switch auth.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tgkPage.ignoresSafeArea())
        case .signedOut:
            LoginView()
        case .signedIn:
            MainTabView()
        }
    }
}

/// The signed-in app: the main tab bar. Terminal initialization happens here
/// (after sign-in) so the login screen never triggers Bluetooth/location prompts.
struct MainTabView: View {
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

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.tgkPrimary)
        .task { appState.onAppear() }
    }
}

#if DEBUG
#Preview("Signed in") {
    let appState = AppState()
    return RootView()
        .environment(appState)
        .environment(appState.settingsStore)
        .environment(AuthSessionStore.preview(.signedIn(AdminProfile(email: "admin@thegoodkitchen.org"))))
}

#Preview("Signed out") {
    let appState = AppState()
    return RootView()
        .environment(appState)
        .environment(appState.settingsStore)
        .environment(AuthSessionStore.preview(.signedOut))
}
#endif

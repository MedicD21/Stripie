import SwiftUI

struct RootView: View {
    @Environment(AuthSessionStore.self) private var auth
    @Environment(SettingsStore.self) private var settings
    @State private var splashFinished = false
    @State private var biometricUnlocked = false
    private let biometrics = BiometricService()

    var body: some View {
        ZStack {
            content

            if !splashFinished {
                SplashView {
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
            if settings.biometricLockEnabled && biometrics.isAvailable && !biometricUnlocked {
                BiometricLockView(biometryLabel: biometrics.biometryLabel) {
                    let ok = await biometrics.authenticate()
                    if ok { biometricUnlocked = true }
                    return ok
                }
            } else {
                MainTabView()
            }
        }
    }
}

/// The signed-in app: the main tab bar. Terminal initialization happens here
/// (after sign-in) so the login screen never triggers Bluetooth/location prompts.
struct MainTabView: View {
    @Environment(AppState.self) private var appState

    /// iPad has room to show Charge and Transactions side by side, so they
    /// collapse into one tab there instead of two.
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        TabView {
            if isPad {
                PaymentSplitView(
                    paymentViewModel: PaymentViewModel(
                        terminal: appState.terminalService,
                        apiClient: appState.apiClient,
                        location: appState.locationService
                    ),
                    transactionsViewModel: TransactionListViewModel(apiClient: appState.apiClient)
                )
                .tabItem { Label("Charge", systemImage: "creditcard.fill") }
            } else {
                PaymentView(
                    viewModel: PaymentViewModel(
                        terminal: appState.terminalService,
                        apiClient: appState.apiClient,
                        location: appState.locationService
                    )
                )
                .tabItem { Label("Charge", systemImage: "creditcard.fill") }

                TransactionListView(
                    viewModel: TransactionListViewModel(apiClient: appState.apiClient)
                )
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
            }

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
        .task {
            appState.onAppear()
            // Warm up Tap to Pay so it's ready at checkout (reqs 1.5 / 5.6).
            await appState.terminalService.warmUp()
        }
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

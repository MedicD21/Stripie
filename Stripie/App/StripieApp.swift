import SwiftUI

@main
struct StripieApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(appState.settingsStore)
                .environment(appState.authSession)
                .preferredColorScheme(appState.settingsStore.themePreference.colorScheme)
        }
    }
}

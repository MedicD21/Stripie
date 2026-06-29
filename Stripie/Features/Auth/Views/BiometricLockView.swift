import SwiftUI

/// Full-screen lock shown when biometric unlock is enabled and the app needs to
/// be unlocked (App Review requirement 1.7). Keeps the signed-in session intact;
/// the user just re-authenticates with Face ID / Touch ID.
struct BiometricLockView: View {
    let biometryLabel: String
    let onUnlock: () async -> Bool

    @State private var isAuthenticating = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: StripieTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.tgkPrimary)
            Text("Stripie is locked")
                .font(StripieTheme.Font.heading)
                .foregroundStyle(Color.tgkText)
            Text("Unlock with \(biometryLabel) to continue.")
                .font(.subheadline)
                .foregroundStyle(Color.tgkTextMuted)
            Spacer()
            PrimaryButton("Unlock", systemImage: "faceid", isLoading: isAuthenticating) {
                Task { await attempt() }
            }
            .padding(.horizontal)
            .padding(.bottom, StripieTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tgkPage.ignoresSafeArea())
        .task { await attempt() }   // auto-prompt on appear
    }

    private func attempt() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        let ok = await onUnlock()
        isAuthenticating = false
        failed = !ok
    }
}

#if DEBUG
#Preview {
    BiometricLockView(biometryLabel: "Face ID") { true }
}
#endif

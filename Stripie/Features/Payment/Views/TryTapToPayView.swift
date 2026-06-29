import SwiftUI

/// One-time invitation shown the first time Tap to Pay becomes ready, after the
/// user accepts Apple's Terms & Conditions (App Review requirement 3.9).
struct TryTapToPayView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: StripieTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.tgkPrimary)
                .symbolEffect(.bounce, value: true)

            VStack(spacing: StripieTheme.Spacing.xs) {
                Text("You're ready to take payments!")
                    .font(StripieTheme.Font.heading)
                    .multilineTextAlignment(.center)
                Text("Enter an amount, tap Charge, and hold the customer's card or phone to the top of your iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Color.tgkTextMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, StripieTheme.Spacing.lg)

            Spacer()

            PrimaryButton("Take a payment", systemImage: "wave.3.right.circle.fill", action: onStart)
                .padding(.horizontal)
                .padding(.bottom, StripieTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tgkPage.ignoresSafeArea())
    }
}

#if DEBUG
#Preview {
    TryTapToPayView {}
}
#endif

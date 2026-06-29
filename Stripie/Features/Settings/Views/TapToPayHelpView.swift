import SwiftUI

/// Merchant education for Tap to Pay on iPhone, reachable any time from Settings
/// (App Review requirement 4.3). Explains how to accept contactless cards and
/// digital wallets, device requirements, and how to enable Tap to Pay.
struct TapToPayHelpView: View {
    var body: some View {
        List {
            Section {
                helpRow(
                    icon: "wave.3.right.circle.fill",
                    title: "Accept contactless cards",
                    detail: "Tap “Charge”, then ask the customer to hold their contactless card flat against the top of your iPhone until you see the checkmark."
                )
                helpRow(
                    icon: "applelogo",
                    title: "Accept Apple Pay & digital wallets",
                    detail: "Customers can also pay with Apple Pay, Google Pay, or any contactless wallet on their phone or watch — hold it near the top of your iPhone."
                )
            } header: {
                Text("Taking a payment")
            }

            Section {
                helpRow(
                    icon: "iphone",
                    title: "Supported devices",
                    detail: "Tap to Pay on iPhone works on iPhone XS and later running iOS 17.6 or newer."
                )
                helpRow(
                    icon: "checkmark.shield.fill",
                    title: "Enabling Tap to Pay",
                    detail: "An admin signs in and connects the reader on the Reader tab. The first time, Apple presents Tap to Pay Terms & Conditions to accept."
                )
                helpRow(
                    icon: "lock.fill",
                    title: "Secure by design",
                    detail: "Card data is encrypted by Apple and never stored on the device or shared with the merchant."
                )
            } header: {
                Text("Setup & requirements")
            }
        }
        .navigationTitle("Tap to Pay Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: StripieTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.tgkPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.footnote).foregroundStyle(Color.tgkTextMuted)
            }
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
#Preview {
    NavigationStack { TapToPayHelpView() }
}
#endif

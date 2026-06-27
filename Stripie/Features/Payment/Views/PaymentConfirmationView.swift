import SwiftUI

struct PaymentConfirmationView: View {
    let state: PaymentState
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            iconSection

            Spacer().frame(height: 32)

            textSection

            Spacer()

            PrimaryButton("New Payment", action: onDone)
                .padding(.horizontal)
                .padding(.bottom, 48)
        }
        .navigationBarBackButtonHidden()
        .navigationTitle("")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var iconSection: some View {
        switch state {
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: true)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var textSection: some View {
        switch state {
        case .succeeded(let amount, let currency):
            VStack(spacing: 8) {
                Text("Payment Successful")
                    .font(.title2.weight(.semibold))
                let formatted = (Double(amount) / 100.0).formatted(.currency(code: currency.uppercased()))
                Text(formatted)
                    .font(.system(size: 40, weight: .thin, design: .rounded))
                    .monospacedDigit()
            }
        case .failed(let message):
            VStack(spacing: 8) {
                Text("Payment Failed")
                    .font(.title2.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        default:
            EmptyView()
        }
    }
}

#Preview("Success") {
    NavigationStack {
        PaymentConfirmationView(state: .succeeded(amount: 2450, currency: "usd")) {}
    }
}

#Preview("Failure") {
    NavigationStack {
        PaymentConfirmationView(state: .failed("Card declined")) {}
    }
}

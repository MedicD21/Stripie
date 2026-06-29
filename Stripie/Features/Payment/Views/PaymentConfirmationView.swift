import SwiftUI

struct PaymentConfirmationView: View {
    let state: PaymentState
    /// Sends a digital receipt to the given email/phone; throws on failure.
    var onSendReceipt: (_ email: String?, _ phone: String?) async throws -> Void = { _, _ in }
    let onDone: () -> Void

    @State private var email = ""
    @State private var phone = ""
    @State private var receiptState: ReceiptState = .idle

    private enum ReceiptState: Equatable {
        case idle, sending, sent, failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            iconSection

            Spacer().frame(height: 24)

            textSection

            if case .succeeded = state {
                receiptSection
                    .padding(.top, 24)
            }

            Spacer()

            PrimaryButton("New Payment", action: onDone)
                .padding(.horizontal)
                .padding(.bottom, 48)
        }
        .navigationBarBackButtonHidden()
        .navigationTitle("")
    }

    // MARK: - Outcome

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
                Text(Receipt(amountCents: amount, currency: currency).formattedAmount)
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

    // MARK: - Receipt (App Review requirement 5.10)

    @ViewBuilder
    private var receiptSection: some View {
        VStack(spacing: StripieTheme.Spacing.sm) {
            switch receiptState {
            case .sent:
                Label("Receipt sent", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.tgkSuccess)
            default:
                Text("Send a receipt")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.tgkTextMuted)

                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .receiptFieldStyle()

                TextField("Mobile number", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .receiptFieldStyle()

                if case .failed(let message) = receiptState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Color.tgkDanger)
                }

                HStack(spacing: StripieTheme.Spacing.sm) {
                    PrimaryButton(
                        "Send Receipt",
                        isLoading: receiptState == .sending,
                        isDisabled: !canSendReceipt
                    ) {
                        Task { await sendReceipt() }
                    }

                    if let shareText {
                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                                .frame(width: 54, height: 54)
                                .background(Color.tgkChipBg)
                                .foregroundStyle(Color.tgkText)
                                .clipShape(RoundedRectangle(cornerRadius: StripieTheme.CornerRadius.md))
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.2), value: receiptState)
    }

    private var canSendReceipt: Bool {
        guard receiptState != .sending else { return false }
        return !email.trimmingCharacters(in: .whitespaces).isEmpty
            || !phone.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var shareText: String? {
        guard case .succeeded(let amount, let currency) = state else { return nil }
        return Receipt(amountCents: amount, currency: currency).text
    }

    private func sendReceipt() async {
        receiptState = .sending
        do {
            try await onSendReceipt(email, phone)
            receiptState = .sent
        } catch {
            let message = (error as? AppError)?.localizedDescription ?? error.localizedDescription
            receiptState = .failed(message)
        }
    }
}

private extension View {
    func receiptFieldStyle() -> some View {
        self
            .padding(12)
            .background(Color.tgkInputBg, in: RoundedRectangle(cornerRadius: StripieTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: StripieTheme.CornerRadius.md)
                    .stroke(Color.tgkInputBorder, lineWidth: 1)
            )
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

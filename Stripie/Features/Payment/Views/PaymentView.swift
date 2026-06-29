import SwiftUI

struct PaymentView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var viewModel: PaymentViewModel
    @State private var showConfirmation = false

    init(viewModel: PaymentViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                readerStatusBar

                amountDisplay
                    .padding(.top, 32)

                Spacer()

                if !settings.quickCharges.isEmpty {
                    quickChargeBar
                        .padding(.bottom, 12)
                }

                KeypadView(
                    onDigit: viewModel.appendDigit,
                    onDelete: viewModel.deleteLastDigit,
                    disabled: viewModel.paymentState.isProcessing
                )

                chargeButton
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
            }
            .navigationTitle("Charge")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showConfirmation) {
                PaymentConfirmationView(state: viewModel.paymentState) {
                    viewModel.reset()
                    showConfirmation = false
                }
            }
            .errorBanner($viewModel.error)
            .onChange(of: viewModel.paymentState) { _, newState in
                if case .succeeded = newState {
                    showConfirmation = true
                }
            }
        }
    }

    // MARK: - Subviews

    private var readerStatusBar: some View {
        HStack {
            ReaderStatusBadge(state: viewModel.readerConnectionState)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var amountDisplay: some View {
        VStack(spacing: 8) {
            Text(viewModel.formattedAmount)
                .font(.system(size: 56, weight: .thin, design: .rounded))
                .monospacedDigit()
                .animation(.spring(response: 0.2), value: viewModel.enteredAmountCents)
                .contentTransition(.numericText())

            if viewModel.paymentState.isProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(viewModel.paymentState.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.paymentState.isProcessing)
    }

    private var quickChargeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: StripieTheme.Spacing.sm) {
                ForEach(settings.quickCharges) { charge in
                    Button {
                        startQuickCharge(charge)
                    } label: {
                        VStack(spacing: 2) {
                            Text(charge.formattedAmount)
                                .font(.headline)
                                .monospacedDigit()
                            if !charge.label.isEmpty {
                                Text(charge.label)
                                    .font(.caption2)
                                    .foregroundStyle(Color.tgkTextMuted)
                            }
                        }
                        .padding(.horizontal, StripieTheme.Spacing.md)
                        .padding(.vertical, StripieTheme.Spacing.sm)
                        .background(Color.tgkChipBg)
                        .foregroundStyle(Color.tgkText)
                        .clipShape(Capsule())
                        .opacity(viewModel.isReaderConnected ? 1 : 0.4)
                    }
                    .disabled(viewModel.paymentState.isProcessing || !viewModel.isReaderConnected)
                }
            }
            .padding(.horizontal)
        }
    }

    /// Sets the amount from a preset and immediately starts the Tap to Pay flow.
    private func startQuickCharge(_ charge: QuickCharge) {
        viewModel.enteredAmountCents = charge.amountCents
        Task { await viewModel.charge() }
    }

    private var chargeButton: some View {
        PrimaryButton(
            viewModel.paymentState.isProcessing ? viewModel.paymentState.statusMessage : "Charge \(viewModel.formattedAmount)",
            isLoading: viewModel.paymentState.isProcessing,
            isDisabled: !viewModel.canCharge
        ) {
            Task { await viewModel.charge() }
        }
    }
}

#if DEBUG
#Preview {
    PaymentView(viewModel: .preview())
        .environment(SettingsStore())
}
#endif

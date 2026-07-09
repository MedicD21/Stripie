import SwiftUI

struct PaymentView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var viewModel: PaymentViewModel
    @State private var showConfirmation = false
    @State private var showTryItOut = false

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
            // Caps the column to a phone-like width so the keypad doesn't
            // stretch edge-to-edge in the iPad split view; a no-op on iPhone
            // since the screen is already narrower than the cap.
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .navigationTitle("Charge")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showConfirmation) {
                PaymentConfirmationView(
                    state: viewModel.paymentState,
                    onSendReceipt: { email, phone in
                        try await viewModel.sendReceipt(email: email, phone: phone)
                    },
                    onDone: {
                        viewModel.reset()
                        showConfirmation = false
                    }
                )
            }
            .errorBanner($viewModel.error)
            .onChange(of: viewModel.paymentState) { _, newState in
                if case .succeeded = newState {
                    showConfirmation = true
                }
            }
            // First time Tap to Pay becomes ready (after T&C), invite them to try it.
            .onChange(of: viewModel.isReaderConnected) { _, connected in
                if connected && !settings.hasCompletedTapToPayIntro {
                    showTryItOut = true
                }
            }
            .sheet(isPresented: $showTryItOut, onDismiss: { settings.hasCompletedTapToPayIntro = true }) {
                TryTapToPayView { showTryItOut = false }
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
            } else if viewModel.isPreparingReader {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.8)
                        Text("Preparing Tap to Pay…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let progress = viewModel.readerUpdateProgress {
                        ProgressView(value: progress)
                            .frame(maxWidth: 200)
                    }
                    Text("Tap to Pay isn't ready yet.")
                        .font(.caption)
                        .foregroundStyle(Color.tgkTextMuted)
                }
                .transition(.opacity)
            } else if !viewModel.isTapToPaySupported {
                Label(TerminalError.osVersionNotSupported.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.tgkWarning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, StripieTheme.Spacing.lg)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.paymentState.isProcessing)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPreparingReader)
    }

    private var quickChargeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: StripieTheme.Spacing.sm) {
                ForEach(settings.quickCharges) { charge in
                    Button {
                        Task { await viewModel.startQuickCharge(cents: charge.amountCents) }
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
                    }
                    // Never greyed out for reader state (App Review 5.3); tapping
                    // connects on demand.
                    .disabled(viewModel.paymentState.isProcessing || viewModel.isPreparingReader || !viewModel.isTapToPaySupported)
                }
            }
            .padding(.horizontal)
        }
    }

    private var chargeButton: some View {
        PrimaryButton(
            chargeButtonTitle,
            // SF Symbol required by App Review requirement 5.5 for Tap to Pay.
            systemImage: (viewModel.paymentState.isProcessing || viewModel.isPreparingReader) ? nil : "wave.3.right.circle.fill",
            isLoading: viewModel.paymentState.isProcessing || viewModel.isPreparingReader,
            // Disabled only for amount/OS/processing — never for reader state (5.3).
            isDisabled: !viewModel.canStartCharge
        ) {
            Task { await viewModel.startCharge() }
        }
    }

    private var chargeButtonTitle: String {
        if viewModel.paymentState.isProcessing { return viewModel.paymentState.statusMessage }
        if viewModel.isPreparingReader { return "Preparing Tap to Pay…" }
        return "Charge \(viewModel.formattedAmount)"
    }
}

#if DEBUG
#Preview {
    PaymentView(viewModel: .preview())
        .environment(SettingsStore())
}
#endif

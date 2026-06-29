import SwiftUI

/// Passwordless admin sign-in: email → emailed 6-digit code → session.
/// Only emails flagged as admin (or super-admin) on the Good Kitchen backend
/// can complete the flow.
struct LoginView: View {
    @Environment(AuthSessionStore.self) private var auth

    private enum Phase { case email, code }

    @State private var phase: Phase = .email
    @State private var email = ""
    @State private var code = ""
    @State private var isWorking = false
    @FocusState private var focused: Field?

    private enum Field { case email, code }

    var body: some View {
        @Bindable var auth = auth

        VStack(spacing: StripieTheme.Spacing.xl) {
            Spacer()
            header

            switch phase {
            case .email: emailStep
            case .code:  codeStep
            }

            Spacer()
            footer
        }
        .padding(.horizontal, StripieTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tgkPage.ignoresSafeArea())
        .errorBanner($auth.error)
    }

    // MARK: - Steps

    private var header: some View {
        VStack(spacing: StripieTheme.Spacing.md) {
            Image("TGKLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240, maxHeight: 140)
                .accessibilityLabel("The Good Kitchen")
            Text("Admin sign-in")
                .font(.subheadline)
                .foregroundStyle(Color.tgkTextMuted)
        }
    }

    private var emailStep: some View {
        VStack(spacing: StripieTheme.Spacing.md) {
            TextField("Admin email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.send)
                .onSubmit { Task { await sendCode() } }
                .padding()
                .background(Color.tgkInputBg, in: RoundedRectangle(cornerRadius: StripieTheme.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: StripieTheme.CornerRadius.md)
                        .stroke(Color.tgkInputBorder, lineWidth: 1)
                )

            PrimaryButton("Send Code", isLoading: isWorking, isDisabled: !isValidEmail) {
                Task { await sendCode() }
            }
        }
        .onAppear { focused = .email }
    }

    private var codeStep: some View {
        VStack(spacing: StripieTheme.Spacing.md) {
            Text("Enter the 6-digit code sent to\n\(email)")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.tgkTextMuted)

            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .monospacedDigit()
                .focused($focused, equals: .code)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter(\.isNumber).prefix(6))
                    if code.count == 6 { Task { await verify() } }
                }
                .padding()
                .background(Color.tgkInputBg, in: RoundedRectangle(cornerRadius: StripieTheme.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: StripieTheme.CornerRadius.md)
                        .stroke(Color.tgkInputBorder, lineWidth: 1)
                )

            PrimaryButton("Verify & Sign In", isLoading: isWorking, isDisabled: code.count != 6) {
                Task { await verify() }
            }

            Button("Use a different email") {
                code = ""
                auth.error = nil
                phase = .email
            }
            .font(.subheadline)
            .foregroundStyle(Color.tgkTextMuted)
        }
        .onAppear { focused = .code }
    }

    private var footer: some View {
        Text("Access is limited to approved admins.")
            .font(.caption)
            .foregroundStyle(Color.tgkTextMuted)
    }

    // MARK: - Actions

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private func sendCode() async {
        guard isValidEmail, !isWorking else { return }
        isWorking = true
        let ok = await auth.requestCode(email: email)
        isWorking = false
        if ok {
            code = ""
            phase = .code
        }
    }

    private func verify() async {
        guard code.count == 6, !isWorking else { return }
        isWorking = true
        await auth.verify(email: email, code: code)
        isWorking = false
        if auth.error != nil { code = "" } // wrong code — let them retry
    }
}

#if DEBUG
#Preview {
    LoginView()
        .environment(AuthSessionStore.preview())
}
#endif

import SwiftUI

extension View {
    /// Displays an error banner anchored to the bottom of the view when the binding is non-nil.
    func errorBanner(_ error: Binding<AppError?>) -> some View {
        modifier(ErrorBannerModifier(error: error))
    }
}

// MARK: - Error Banner Modifier

private struct ErrorBannerModifier: ViewModifier {
    @Binding var error: AppError?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let error {
                    ErrorBannerView(message: error.localizedDescription) {
                        self.error = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: error != nil)
    }
}

// MARK: - Error Banner View

private struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

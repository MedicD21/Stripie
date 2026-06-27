import SwiftUI

struct PrimaryButton: View {
    private let title: String
    private let isLoading: Bool
    private let isDisabled: Bool
    private let action: () -> Void

    init(_ title: String, isLoading: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.85)
                }
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isDisabled ? Color.accentColor.opacity(0.4) : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: StripieTheme.CornerRadius.md))
        }
        .disabled(isDisabled || isLoading)
        .animation(.easeInOut(duration: 0.15), value: isLoading)
    }
}

struct SecondaryButton: View {
    private let title: String
    private let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(.secondarySystemBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: StripieTheme.CornerRadius.md))
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton("Charge $24.50") {}
        PrimaryButton("Processing…", isLoading: true) {}
        PrimaryButton("Charge", isDisabled: true) {}
        SecondaryButton("Disconnect") {}
    }
    .padding()
}

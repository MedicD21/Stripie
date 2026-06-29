import SwiftUI

struct PrimaryButton: View {
    private let title: String
    private let systemImage: String?
    private let isLoading: Bool
    private let isDisabled: Bool
    private let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isLoading: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
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
                        .tint(Color.tgkPrimaryText)
                        .scaleEffect(0.85)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isDisabled ? Color.tgkPrimary.opacity(0.4) : Color.tgkPrimary)
            .foregroundStyle(Color.tgkPrimaryText)
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
                .background(Color.tgkChipBg)
                .foregroundStyle(Color.tgkText)
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

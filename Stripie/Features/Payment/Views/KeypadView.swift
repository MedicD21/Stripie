import SwiftUI

struct KeypadView: View {
    let onDigit: (Int) -> Void
    let onDelete: () -> Void
    let disabled: Bool

    private let keys: [[KeypadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.empty,    .digit(0), .delete],
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        KeyCell(key: key, disabled: disabled) {
                            switch key {
                            case .digit(let d): onDigit(d)
                            case .delete:       onDelete()
                            case .empty:        break
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Models

private enum KeypadKey: Hashable {
    case digit(Int)
    case delete
    case empty
}

// MARK: - Cell

private struct KeyCell: View {
    let key: KeypadKey
    let disabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)

                switch key {
                case .digit(let d):
                    Text("\(d)")
                        .font(.title.weight(.regular))
                        .foregroundStyle(Color.tgkText)
                case .delete:
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .foregroundStyle(Color.tgkText)
                case .empty:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.6, contentMode: .fit)
        .disabled(disabled || key == .empty)
        .buttonStyle(.plain)
        .opacity(key == .empty ? 0 : 1)
    }

    private var backgroundColor: Color {
        switch key {
        case .empty:  return .clear
        default:      return Color.tgkChipBg
        }
    }
}

#Preview {
    KeypadView(onDigit: { _ in }, onDelete: {}, disabled: false)
}

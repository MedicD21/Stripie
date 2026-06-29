import SwiftUI

/// Add or edit a quick charge. Reuses `KeypadView` so amount entry feels
/// identical to the main Charge screen.
struct QuickChargeEditorView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private let editingCharge: QuickCharge?
    @State private var amountCents: Int
    @State private var label: String

    init(target: QuickChargeEditorTarget) {
        switch target {
        case .add:
            self.editingCharge = nil
            _amountCents = State(initialValue: 0)
            _label = State(initialValue: "")
        case .edit(let charge):
            self.editingCharge = charge
            _amountCents = State(initialValue: charge.amountCents)
            _label = State(initialValue: charge.label)
        }
    }

    private var isEditing: Bool { editingCharge != nil }
    private var canSave: Bool { amountCents > 0 }

    private var formattedAmount: String {
        (Double(amountCents) / 100.0).formatted(.currency(code: "USD"))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: StripieTheme.Spacing.lg) {
                Text(formattedAmount)
                    .font(.system(size: 56, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.2), value: amountCents)
                    .padding(.top, StripieTheme.Spacing.lg)

                TextField("Label (optional)", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Spacer()

                KeypadView(
                    onDigit: { amountCents = min(amountCents * 10 + $0, 9_999_999) },
                    onDelete: { amountCents /= 10 },
                    disabled: false
                )

                PrimaryButton(isEditing ? "Save" : "Add Quick Charge", isDisabled: !canSave) {
                    save()
                }
                .padding(.horizontal)
                .padding(.bottom, StripieTheme.Spacing.lg)
            }
            .navigationTitle(isEditing ? "Edit Quick Charge" : "New Quick Charge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if let editing = editingCharge {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Delete", role: .destructive) {
                            settings.deleteQuickCharge(editing)
                            dismiss()
                        }
                        .foregroundStyle(Color.tgkDanger)
                    }
                }
            }
        }
    }

    private func save() {
        if let editing = editingCharge {
            settings.updateQuickCharge(
                QuickCharge(id: editing.id, amountCents: amountCents, label: label)
            )
        } else {
            settings.addQuickCharge(amountCents: amountCents, label: label)
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    QuickChargeEditorView(target: .add)
        .environment(SettingsStore())
}
#endif

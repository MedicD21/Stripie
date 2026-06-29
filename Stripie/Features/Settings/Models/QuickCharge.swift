import Foundation

/// A preset amount the user can tap on the Charge screen to start a payment
/// instantly. Stored locally on-device via `SettingsStore` (UserDefaults).
struct QuickCharge: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var amountCents: Int
    var label: String

    init(id: UUID = UUID(), amountCents: Int, label: String = "") {
        self.id = id
        self.amountCents = amountCents
        self.label = label
    }

    /// Currency-formatted amount, e.g. "$10.00".
    var formattedAmount: String {
        (Double(amountCents) / 100.0).formatted(.currency(code: "USD"))
    }

    /// The label if one is set, otherwise the formatted amount.
    var displayName: String {
        label.isEmpty ? formattedAmount : label
    }
}

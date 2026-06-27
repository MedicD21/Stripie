import Foundation

extension Int {
    /// Formats an integer cent amount as a localized currency string.
    func formattedAsCurrency(code: String = "USD") -> String {
        (Double(self) / 100.0).formatted(.currency(code: code))
    }
}

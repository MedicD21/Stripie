import Foundation

/// A digital receipt for a completed Tap to Pay charge. Used for the in-app
/// Share/Activity receipt; email/SMS delivery is handled by the backend.
struct Receipt: Equatable {
    let amountCents: Int
    let currency: String
    var merchant: String = "The Good Kitchen"
    var date: Date = Date()

    var formattedAmount: String {
        (Double(amountCents) / 100.0).formatted(.currency(code: currency.uppercased()))
    }

    /// Plain-text receipt suitable for the iOS share sheet.
    var text: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return """
        \(merchant)
        Payment Receipt

        Amount: \(formattedAmount)
        Date: \(formatter.string(from: date))

        Paid with Tap to Pay on iPhone.
        Thank you!
        """
    }
}

import SwiftUI
import OSLog

/// Persists user preferences — appearance and quick charges — locally on-device
/// via `UserDefaults`. Owned by `AppState` and injected through `@Environment`.
@Observable
@MainActor
final class SettingsStore {

    /// Selected appearance. Defaults to `.dark` on first launch.
    var themePreference: ThemePreference {
        didSet { persistTheme() }
    }

    /// User-defined quick charge presets, in display order.
    private(set) var quickCharges: [QuickCharge] {
        didSet { persistQuickCharges() }
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.stripie", category: "SettingsStore")

    private enum Key {
        static let theme = "settings.themePreference"
        static let quickCharges = "settings.quickCharges"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Default to dark theme when nothing has been persisted yet.
        if let raw = defaults.string(forKey: Key.theme),
           let stored = ThemePreference(rawValue: raw) {
            self.themePreference = stored
        } else {
            self.themePreference = .dark
        }

        if let data = defaults.data(forKey: Key.quickCharges),
           let decoded = try? JSONDecoder().decode([QuickCharge].self, from: data) {
            self.quickCharges = decoded
        } else {
            self.quickCharges = SettingsStore.defaultQuickCharges
        }
    }

    // MARK: - Quick Charge mutations

    func addQuickCharge(amountCents: Int, label: String = "") {
        guard amountCents > 0 else { return }
        quickCharges.append(QuickCharge(amountCents: amountCents, label: label))
    }

    func updateQuickCharge(_ charge: QuickCharge) {
        guard let index = quickCharges.firstIndex(where: { $0.id == charge.id }) else { return }
        quickCharges[index] = charge
    }

    func deleteQuickCharge(_ charge: QuickCharge) {
        quickCharges.removeAll { $0.id == charge.id }
    }

    func deleteQuickCharges(at offsets: IndexSet) {
        quickCharges.remove(atOffsets: offsets)
    }

    func moveQuickCharges(from source: IndexSet, to destination: Int) {
        quickCharges.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Persistence

    private func persistTheme() {
        defaults.set(themePreference.rawValue, forKey: Key.theme)
    }

    private func persistQuickCharges() {
        guard let data = try? JSONEncoder().encode(quickCharges) else {
            logger.error("Failed to encode quick charges for persistence")
            return
        }
        defaults.set(data, forKey: Key.quickCharges)
    }

    /// Seed presets so the Charge screen has something useful on first launch.
    private static let defaultQuickCharges: [QuickCharge] = [
        QuickCharge(amountCents: 500),
        QuickCharge(amountCents: 1000),
        QuickCharge(amountCents: 2000),
    ]
}

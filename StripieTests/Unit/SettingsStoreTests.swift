import Testing
import Foundation
@testable import Stripie

@MainActor
@Suite("SettingsStore")
struct SettingsStoreTests {

    /// A throwaway UserDefaults suite so each test starts from a clean slate.
    private func makeDefaults() -> UserDefaults {
        let suite = "test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Defaults to dark theme on first launch")
    func testDefaultDarkTheme() {
        let store = SettingsStore(defaults: makeDefaults())
        #expect(store.themePreference == .dark)
    }

    @Test("Theme preference persists across reloads")
    func testThemePersists() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.themePreference = .light
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.themePreference == .light)
    }

    @Test("Add quick charge appends and persists")
    func testAddQuickCharge() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        let initial = store.quickCharges.count

        store.addQuickCharge(amountCents: 1500, label: "Lunch")
        #expect(store.quickCharges.count == initial + 1)
        #expect(store.quickCharges.last?.amountCents == 1500)
        #expect(store.quickCharges.last?.label == "Lunch")

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.quickCharges.last?.amountCents == 1500)
        #expect(reloaded.quickCharges.last?.label == "Lunch")
    }

    @Test("Add ignores non-positive amounts")
    func testAddRejectsZero() {
        let store = SettingsStore(defaults: makeDefaults())
        let initial = store.quickCharges.count
        store.addQuickCharge(amountCents: 0)
        #expect(store.quickCharges.count == initial)
    }

    @Test("Update mutates the matching charge")
    func testUpdateQuickCharge() {
        let store = SettingsStore(defaults: makeDefaults())
        store.addQuickCharge(amountCents: 1000)
        var charge = store.quickCharges.last!
        charge.amountCents = 2500
        charge.label = "Dinner"

        store.updateQuickCharge(charge)
        let updated = store.quickCharges.first { $0.id == charge.id }
        #expect(updated?.amountCents == 2500)
        #expect(updated?.label == "Dinner")
    }

    @Test("Delete removes the charge")
    func testDeleteQuickCharge() {
        let store = SettingsStore(defaults: makeDefaults())
        store.addQuickCharge(amountCents: 1000, label: "Temp")
        let charge = store.quickCharges.last!

        store.deleteQuickCharge(charge)
        #expect(!store.quickCharges.contains { $0.id == charge.id })
    }
}

@Suite("QuickCharge")
struct QuickChargeTests {

    @Test("Formats amount as currency")
    func testFormattedAmount() {
        #expect(QuickCharge(amountCents: 1000).formattedAmount == "$10.00")
        #expect(QuickCharge(amountCents: 2550).formattedAmount == "$25.50")
    }

    @Test("displayName prefers label, falls back to amount")
    func testDisplayName() {
        #expect(QuickCharge(amountCents: 1000, label: "Tip").displayName == "Tip")
        #expect(QuickCharge(amountCents: 1000).displayName == "$10.00")
    }
}

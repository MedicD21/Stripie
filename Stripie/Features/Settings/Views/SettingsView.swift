import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AuthSessionStore.self) private var auth
    @State private var editorTarget: QuickChargeEditorTarget?
    @State private var isSigningOut = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                if let profile = auth.profile {
                    Section("Account") {
                        HStack(spacing: StripieTheme.Spacing.sm) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.tgkPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayLabel)
                                    .font(.body.weight(.medium))
                                Text(profile.roleLabel)
                                    .font(.caption)
                                    .foregroundStyle(Color.tgkTextMuted)
                            }
                        }

                        Button(role: .destructive) {
                            isSigningOut = true
                            Task {
                                await auth.signOut()
                                isSigningOut = false
                            }
                        } label: {
                            HStack {
                                Text("Sign Out")
                                if isSigningOut {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSigningOut)
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.themePreference) {
                        ForEach(ThemePreference.allCases) { pref in
                            Text(pref.displayName).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if settings.quickCharges.isEmpty {
                        Text("No quick charges yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(settings.quickCharges) { charge in
                        Button {
                            editorTarget = .edit(charge)
                        } label: {
                            HStack {
                                Text(charge.formattedAmount)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color.tgkText)
                                if !charge.label.isEmpty {
                                    Text(charge.label)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { settings.deleteQuickCharges(at: $0) }
                    .onMove { settings.moveQuickCharges(from: $0, to: $1) }

                    Button {
                        editorTarget = .add
                    } label: {
                        Label("Add Quick Charge", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Quick Charges")
                } footer: {
                    Text("Tap a quick charge on the Charge screen to instantly start a Tap to Pay payment.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                if !settings.quickCharges.isEmpty {
                    EditButton()
                }
            }
            .sheet(item: $editorTarget) { target in
                QuickChargeEditorView(target: target)
            }
        }
    }
}

/// What the quick-charge editor sheet is currently editing.
enum QuickChargeEditorTarget: Identifiable {
    case add
    case edit(QuickCharge)

    var id: String {
        switch self {
        case .add:            return "add"
        case .edit(let c):    return c.id.uuidString
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environment(SettingsStore())
        .environment(AuthSessionStore.preview(.signedIn(AdminProfile(email: "admin@thegoodkitchen.org", displayName: "Test Admin", isSuperAdmin: true))))
}
#endif

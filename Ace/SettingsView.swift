import SwiftUI

/// Stores the Anthropic API key in the device Keychain. The key never leaves
/// the device except in requests to api.anthropic.com.
struct SettingsView: View {
    @State private var keyField = ""
    @State private var hasStoredKey = Keychain.read(Keychain.anthropicAPIKey) != nil
    @State private var saved = false
    @State private var saveFailed = false

    var body: some View {
        Form {
            Section {
                SecureField("Anthropic API key", text: $keyField)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Button("Save key") {
                    let trimmed = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if Keychain.save(trimmed, for: Keychain.anthropicAPIKey) {
                        keyField = ""
                        hasStoredKey = Keychain.read(Keychain.anthropicAPIKey) != nil
                        saveFailed = false
                        saved.toggle()
                    } else {
                        saveFailed = true
                    }
                }
                .disabled(keyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Anthropic")
            } footer: {
                if saveFailed {
                    Text("The key could not be saved to this device's Keychain. On a Mac, the app must be signed with your Apple team in Xcode.")
                } else {
                    Text(hasStoredKey
                         ? "A key is stored on this device."
                         : "No key stored. Paste the key from console.anthropic.com and tap Save key.")
                }
            }

            if hasStoredKey {
                Section {
                    Button("Remove key", role: .destructive) {
                        Keychain.delete(Keychain.anthropicAPIKey)
                        hasStoredKey = false
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("API key")
        .sensoryFeedback(.success, trigger: saved)
    }
}

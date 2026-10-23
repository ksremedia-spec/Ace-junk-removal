import SwiftUI

/// Settings › Sync: the server address and the business's sync code,
/// entered once per device. The code is kept in the Keychain.
struct SyncSettingsSection: View {
    @State private var sync = SyncEngine.shared
    @State private var address = UserDefaults.standard.string(forKey: SyncEngine.urlKey) ?? ""
    @State private var code = ""
    @State private var hasCode = Keychain.read(SyncEngine.codeAccount) != nil
    @State private var confirmDeletions = false

    var body: some View {
        Section {
            TextField("Server address", text: $address, prompt: Text("https://…"))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .onSubmit(saveAddress)
            SecureField("Sync code", text: $code, prompt: Text(hasCode ? "Stored" : "Not set"))
                .onSubmit(saveCode)
            LabeledContent("Status", value: status)
            if sync.heldDeletions > 0 {
                Button("Delete \(sync.heldDeletions) records on every device…", role: .destructive) { confirmDeletions = true }
                    .confirmationDialog("Delete \(sync.heldDeletions) records on every device?", isPresented: $confirmDeletions, titleVisibility: .visible) {
                        Button("Delete on Every Device", role: .destructive) { Task { await sync.sendHeldDeletions() } }
                    } message: {
                        Text("They were deleted on this device. Ace held them back because that many at once can mean something went wrong.")
                    }
            }
            Button(sync.isSyncing ? "Syncing…" : "Sync Now") {
                saveAddress()
                saveCode()
                Task { await sync.syncNow(manual: true) }
            }
            .disabled(sync.isSyncing)
        } header: {
            Text("Sync")
        } footer: {
            Text("Keeps this device and the others in step. Enter the same server address and sync code on each device.")
        }
    }

    private var status: String {
        if let problem = sync.problem { return problem }
        if sync.isSyncing { return "Syncing" }
        guard sync.isSetUp else { return "Not set up" }
        guard let last = sync.lastSynced else { return "Not synced yet" }
        return "Synced " + last.formatted(.relative(presentation: .named))
    }

    private func saveAddress() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed.isEmpty ? nil : trimmed, forKey: SyncEngine.urlKey)
    }

    private func saveCode() {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasCode = Keychain.save(trimmed, for: SyncEngine.codeAccount)
        code = ""
    }
}

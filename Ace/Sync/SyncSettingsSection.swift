import SwiftUI

/// Settings › Sync: the server address and the business's sync code,
/// entered once per device, unless they are built into this copy. The code
/// is kept in the Keychain.
struct SyncSettingsSection: View {
    @State private var sync = SyncEngine.shared
    @State private var address = UserDefaults.standard.string(forKey: SyncEngine.urlKey) ?? ""
    @State private var code = ""
    @State private var hasCode = Keychain.read(SyncEngine.codeAccount) != nil
    @State private var confirmDeletions = false
    @State private var confirmSendHeld = false
    @State private var confirmRemoveHeld = false

    /// The business's server is built into this copy and nothing typed here
    /// overrides it, so there is nothing to enter (audit Oct 24, findings
    /// 12 and 74). Typing an address would only risk cutting the device off.
    private var builtIn: Bool {
        SyncEngine.builtIn != nil && address.isEmpty && !hasCode
    }

    var body: some View {
        Section {
            if builtIn {
                LabeledContent("Server", value: "Built in")
            } else {
                TextField("Server address", text: $address, prompt: Text("https://…"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit(saveAddress)
                SecureField("Sync code", text: $code, prompt: Text(hasCode ? "Stored" : "Not set"))
                    .onSubmit(saveCode)
            }
            LabeledContent("Status", value: status)
            if sync.heldDeletions > 0 {
                Button("Delete \(sync.heldDeletions) records on every device…", role: .destructive) { confirmDeletions = true }
                    .confirmationDialog("Delete \(sync.heldDeletions) records on every device and from the Google Sheet?", isPresented: $confirmDeletions, titleVisibility: .visible) {
                        Button("Delete on Every Device", role: .destructive) { Task { await sync.sendHeldDeletions() } }
                    } message: {
                        Text("They were deleted on this device. Ace held them back because that many at once can mean something went wrong.")
                    }
            }
            if sync.heldRecords > 0 {
                // Records from before this device moved to this server
                // (audit Oct 24, finding 5).
                Label(sync.heldRecordsText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Tint.warning)
                Button("Send to Every Device…") { confirmSendHeld = true }
                    .confirmationDialog("Send \(Plural.text(sync.heldRecords, "record")) to every device?", isPresented: $confirmSendHeld, titleVisibility: .visible) {
                        Button("Send to Every Device") { Task { await sync.sendHeldRecords() } }
                    } message: {
                        Text("They were on this device before it was connected to this sync server. They go to every device, and jobs among them go into the Google Sheet.")
                    }
                Button("Remove from This Device…", role: .destructive) { confirmRemoveHeld = true }
                    .confirmationDialog("Remove \(Plural.text(sync.heldRecords, "record")) from this device?", isPresented: $confirmRemoveHeld, titleVisibility: .visible) {
                        Button("Remove from This Device", role: .destructive) { Task { await sync.removeHeldRecords() } }
                    } message: {
                        Text("They are not on the sync server, so this cannot be undone. Everything on the server stays and is brought down again.")
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
            Text(builtIn
                 ? "Keeps this device and the others in step. Set up for Ace Junk Removal."
                 : "Keeps this device and the others in step. Enter the same server address and sync code on each device.")
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

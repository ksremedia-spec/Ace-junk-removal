import SwiftUI

/// Settings › Google Sheet: connects Ashley's job sheet so it and Ace stay
/// in step (docs/google-sheet-sync.md). Connecting happens on the Mac: it
/// opens Google's sign-in in the browser, where she picks the sheet. The
/// server does the rest every minute; the phones only show the status.
struct SheetLinkSection: View {
    @Environment(\.openURL) private var openURL
    @State private var sync = SyncEngine.shared
    @State private var status: SyncEngine.SheetStatus?
    @State private var waiting = false
    @State private var message: String?
    @State private var confirmDisconnect = false
    @State private var confirmResume = false

    var body: some View {
        if sync.isSetUp {
            Section {
                if let status, status.connected {
                    LabeledContent("Sheet", value: status.sheetName ?? "Connected")
                    if let paused = status.paused, !paused.isEmpty {
                        Label(paused, systemImage: "pause.circle")
                            .foregroundStyle(Tint.warning)
                        // On the Mac only, after a plain warning: the next
                        // check skips every safety stop (audit Oct 24, finding 30).
                        #if os(macOS)
                        Button("Resume…") { confirmResume = true }
                            .confirmationDialog("Resume the Google Sheet link?", isPresented: $confirmResume, titleVisibility: .visible) {
                                Button("Resume") { act("resume") }
                            } message: {
                                Text(paused + "\n\nThe next check runs without these safety stops: jobs whose rows are gone from the sheet are deleted on every device, changed rows replace what Ace has, and Ace writes all its own changes into the sheet.")
                            }
                        #endif
                    } else if let error = status.lastError, !error.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Tint.warning)
                        // Google's text says to connect again (finding 35).
                        #if os(macOS)
                        Button(waiting ? "Waiting for Google…" : "Connect Again…") { connect() }
                            .disabled(waiting)
                        #endif
                    } else {
                        LabeledContent("Checked", value: status.lastChecked.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet")
                    }
                    #if os(macOS)
                    Button("Disconnect…", role: .destructive) { confirmDisconnect = true }
                    #endif
                } else {
                    LabeledContent("Sheet", value: status == nil ? "Checking…" : "Not connected")
                    #if os(macOS)
                    Button(waiting ? "Waiting for Google…" : "Connect Google Sheet…") { connect() }
                        .disabled(waiting || status?.configured == false)
                    #endif
                }
                if let message {
                    Text(message).foregroundStyle(.secondary)
                }
            } header: {
                Text("Google Sheet")
            } footer: {
                #if os(macOS)
                Text(status?.configured == false
                     ? "Google sign-in is not set up on the sync server yet."
                     : "Keeps the job sheet and Ace in step, about once a minute. Connecting opens Google in the browser: sign in, click Allow, and pick the job sheet.")
                #else
                Text("Connect the job sheet from Ace on the Mac. Changes in either place show up in both within a minute or two.")
                #endif
            }
            .task { await refresh() }
            .confirmationDialog("Disconnect the Google Sheet?", isPresented: $confirmDisconnect) {
                Button("Disconnect", role: .destructive) { act("disconnect") }
            } message: {
                Text("Ace and the sheet stop keeping in step. Nothing is deleted in either.")
            }
        }
    }

    private func refresh() async {
        status = await sync.sheet("status")
        if status == nil { message = "Could not reach the sync server." }
    }

    /// Resume or Disconnect. The status stays as it was if the server
    /// can't be reached.
    private func act(_ action: String) {
        message = nil
        Task {
            if let now = await sync.sheet(action) {
                status = now
            } else {
                message = "Could not reach the sync server."
            }
        }
    }

    private func connect() {
        message = nil
        Task {
            guard let reply = await sync.sheet("start") else {
                message = "Could not reach the sync server."
                return
            }
            if let error = reply.error { message = error; return }
            guard let text = reply.url, let url = URL(string: text) else {
                message = "Could not start the Google sign-in."
                return
            }
            // Connecting again: the old link shows as connected until the
            // new one replaces it.
            let before = status?.connected == true ? status?.connectedAt : nil
            openURL(url)
            // Wait for the sign-in to come back (up to five minutes).
            waiting = true
            defer { waiting = false }
            for _ in 0..<100 {
                try? await Task.sleep(for: .seconds(3))
                if let now = await sync.sheet("status"), now.connected, before == nil || now.connectedAt != before {
                    status = now
                    message = "Connected. The first check runs within a minute."
                    _ = await sync.sheet("run")
                    status = await sync.sheet("status")
                    await sync.syncNow(manual: true)
                    return
                }
            }
            message = "Google did not come back. Try Connect again."
        }
    }
}

import SwiftUI

/// Step 1 of the build order: the app is only a settings screen with a hidden
/// Debug section. The real tabs (Today, Jobs, Customers, Dumpsters) come later.
struct RootView: View {
    /// Lives as long as the window, so a loaded speech model is kept when the
    /// user leaves the Speech test screen and comes back.
    @State private var engine = WhisperKitEngine()

    var body: some View {
        NavigationStack {
            Form {
                Section("Assistant") {
                    NavigationLink("API key") {
                        SettingsView()
                    }
                }

                Section {
                    NavigationLink("Speech test") {
                        SpeechTestView(engine: engine)
                    }
                    NavigationLink("Claude test") {
                        ClaudeTestView()
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("These screens compare speech engines and Claude models. They are for testing only and will not be in the finished app.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Ace")
        }
    }
}

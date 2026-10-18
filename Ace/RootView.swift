import SwiftUI

/// Step 1 of the build order: the app is only a settings screen with a hidden
/// Debug section. The real tabs (Today, Jobs, Customers, Dumpsters) come later.
struct RootView: View {
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
                        SpeechTestView()
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

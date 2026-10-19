import SwiftUI

/// Step 1 of the build order: the app is only a settings screen with a hidden
/// Debug section. The real tabs (Today, Jobs, Customers, Dumpsters) come later.
struct RootView: View {
    enum Screen: String, Hashable {
        case apiKey = "apikey"
        case speech
        case claude
    }

    /// Lives as long as the window, so a loaded speech model is kept when the
    /// user leaves the Speech test screen and comes back.
    @State private var engine = WhisperKitEngine()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Assistant") {
                    NavigationLink("API key", value: Screen.apiKey)
                }

                Section {
                    NavigationLink("Speech test", value: Screen.speech)
                    NavigationLink("Claude test", value: Screen.claude)
                } header: {
                    Text("Debug")
                } footer: {
                    Text("These screens compare speech engines and Claude models. They are for testing only and will not be in the finished app.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Ace")
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .apiKey:
                    SettingsView()
                case .speech:
                    SpeechTestView(engine: engine)
                case .claude:
                    ClaudeTestView()
                }
            }
            .onAppear(perform: openScreenFromLaunchArguments)
        }
    }

    /// Testing aid: launching with `-open speech` (or `apikey`, `claude`)
    /// opens that screen straight away, so screenshots can be taken without
    /// tapping. Normal launches have no such argument and ignore this.
    private func openScreenFromLaunchArguments() {
        guard path.isEmpty else { return }
        let args = ProcessInfo.processInfo.arguments
        var name: String?
        if let index = args.firstIndex(of: "-open"), index + 1 < args.count {
            name = args[index + 1]
        } else if let arg = args.first(where: { $0.hasPrefix("-open=") }) {
            name = String(arg.dropFirst("-open=".count))
        }
        if let name, let screen = Screen(rawValue: name.lowercased()) {
            path.append(screen)
        }
    }
}

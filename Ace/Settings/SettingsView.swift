import SwiftData
import SwiftUI

/// Settings, reached from the gear on the Today screen.
struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(AppSettings.claudeModelKey) private var claudeModelRaw = ClaudeModel.haiku.rawValue
    @AppStorage(AppSettings.effortKey) private var effortRaw = ClaudeEffort.medium.rawValue
    @AppStorage(AppSettings.speechModelKey) private var speechModel = AppSettings.defaultSpeechModel
    @AppStorage(AppSettings.overweightRateKey) private var ratePerTon = AppSettings.defaultOverweightRate

    @State private var hasKey = Keychain.read(Keychain.anthropicAPIKey) != nil
    @State private var rateText = ""
    @State private var confirmSample = false
    @State private var confirmClear = false
    @State private var done = 0

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                NavigationLink(value: MainView.Screen.apikey) {
                    LabeledContent("API key", value: hasKey ? "Stored" : "Not set")
                }
                Picker("Claude model", selection: $claudeModelRaw) {
                    ForEach(ClaudeModel.allCases) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
                Picker("Effort", selection: $effortRaw) {
                    ForEach(ClaudeEffort.allCases) { effort in
                        Text(effort.rawValue.capitalized).tag(effort.rawValue)
                    }
                }
                Picker("Speech model", selection: $speechModel) {
                    ForEach(WhisperKitEngine.modelChoices) { choice in
                        Text(choice.shortName).tag(choice.name)
                    }
                }
            } header: {
                Text("Assistant")
            } footer: {
                Text("Haiku is quicker and cheaper; Sonnet is the switch for testing. The speech model downloads once, the first time the Assistant is used.")
            }

            Section {
                LabeledContent("Rate per ton over") {
                    TextField("Dollars", text: $rateText, prompt: Text("Dollars"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                        .onChange(of: rateText) { _, newValue in
                            // Saved on every keystroke that reads as a number,
                            // so nothing depends on a Return key.
                            if let value = Parse.money(newValue), value > 0 {
                                ratePerTon = value
                            }
                        }
                }
            } header: {
                Text("Dumpsters")
            } footer: {
                Text("Charged for each ton over the agreed weight at pickup. Partial tons are charged in proportion.")
            }

            Section {
                NavigationLink("Speech test", value: MainView.Screen.speech)
                NavigationLink("Claude test", value: MainView.Screen.claude)
                Button("Load sample data") { confirmSample = true }
                Button("Clear all data", role: .destructive) { confirmClear = true }
            } header: {
                Text("Debug")
            } footer: {
                Text("Sample data replaces everything with example customers, jobs and dumpsters, for showing the app.")
            }

            Section("About") {
                LabeledContent("Version", value: version)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            // Refreshes after coming back from the API key screen.
            hasKey = Keychain.read(Keychain.anthropicAPIKey) != nil
            if rateText.isEmpty {
                rateText = Parse.moneyText(ratePerTon)
            }
        }
        .confirmationDialog("Replace all data with sample data?", isPresented: $confirmSample, titleVisibility: .visible) {
            Button("Replace with sample data", role: .destructive) {
                SampleData.clear(context: context)
                SampleData.load(into: context)
                done += 1
            }
        }
        .confirmationDialog("Delete every customer, job and dumpster record?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                SampleData.clear(context: context)
                done += 1
            }
        }
        .sensoryFeedback(.success, trigger: done)
    }
}

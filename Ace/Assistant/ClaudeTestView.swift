import SwiftUI

/// Debug panel 2: send one transcript to Haiku and Sonnet at the same time
/// and show the two filled-in forms side by side, with timing.
struct ClaudeTestView: View {
    @AppStorage("debug.transcript") private var transcript = ""
    @AppStorage("debug.effort") private var effortRaw = ClaudeEffort.medium.rawValue

    @State private var outcomes: [ClaudeModel: Outcome] = [:]
    @State private var running = false
    @State private var flaggedCount = 0

    private var hasKey: Bool { Keychain.read(Keychain.anthropicAPIKey) != nil }

    enum Outcome {
        case result(ClaudeFormResult)
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $transcript)
                    .frame(minHeight: 120)
            } header: {
                Text("Transcript")
            } footer: {
                Text("Filled in from the Speech test, or type what you would say on the phone.")
            }

            Section {
                Picker("Effort", selection: $effortRaw) {
                    ForEach(ClaudeEffort.allCases) { effort in
                        Text(effort.rawValue.capitalized).tag(effort.rawValue)
                    }
                }
                Button {
                    runBoth()
                } label: {
                    if running {
                        HStack {
                            ProgressView()
                            Text("Asking Haiku and Sonnet")
                        }
                    } else {
                        Text("Fill the form with both models")
                    }
                }
                .disabled(running || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasKey)
                if !hasKey {
                    Text("Add the Anthropic API key under Assistant › API key first.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Effort controls how long Claude thinks before answering. Lower is faster and cheaper.")
            }

            ForEach(ClaudeModel.allCases) { model in
                Section {
                    outcomeView(for: model)
                } header: {
                    Text("\(model.displayName) · \(model.rawValue)")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Claude test")
        .sensoryFeedback(.warning, trigger: flaggedCount)
    }

    @ViewBuilder
    private func outcomeView(for model: ClaudeModel) -> some View {
        switch outcomes[model] {
        case .none:
            Text(running ? "Waiting" : "Not run yet")
                .foregroundStyle(.secondary)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case .result(let result):
            LabeledContent("Time") {
                Text("\(result.seconds, format: .number.precision(.fractionLength(1))) s")
                    .monospacedDigit()
            }
            LabeledContent("Tokens", value: "\(result.inputTokens) in · \(result.outputTokens) out")

            ForEach(result.draft.rows) { row in
                let flagged = result.draft.issues.contains { issue in
                    issue.field.lowercased() == row.field.lowercased()
                }
                LabeledContent(row.label) {
                    Text(row.value.isEmpty ? "—" : row.value)
                        .foregroundStyle(flagged ? Color.orange : (row.value.isEmpty ? Color.secondary : Color.primary))
                        .multilineTextAlignment(.trailing)
                }
                .foregroundStyle(flagged ? Color.orange : Color.primary)
            }

            if !result.draft.issues.isEmpty {
                ForEach(result.draft.issues) { issue in
                    Label(issue.question, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func runBoth() {
        let text = transcript
        let effort = ClaudeEffort(rawValue: effortRaw) ?? .medium
        running = true
        outcomes = [:]
        Task { @MainActor in
            async let haiku = run(model: .haiku, text: text, effort: effort)
            async let sonnet = run(model: .sonnet, text: text, effort: effort)
            let results = await [ClaudeModel.haiku: haiku, ClaudeModel.sonnet: sonnet]
            outcomes = results
            running = false
            let anyFlagged = results.values.contains { outcome in
                if case .result(let r) = outcome { return !r.draft.issues.isEmpty }
                return false
            }
            if anyFlagged { flaggedCount += 1 }
        }
    }

    private func run(model: ClaudeModel, text: String, effort: ClaudeEffort) async -> Outcome {
        do {
            return .result(try await ClaudeClient.fillJobForm(transcript: text, model: model, effort: effort))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

import SwiftData
import SwiftUI

/// Debug panel 2: send one note, with the current records, to Haiku and
/// Sonnet at the same time and show both plans side by side, with timing:
/// the reply, each action with the fields it filled in, and the questions.
struct ClaudeTestView: View {
    @AppStorage("debug.transcript") private var transcript = ""
    @AppStorage("debug.effort") private var effortRaw = ClaudeEffort.medium.rawValue
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]
    @Query(sort: \Quote.quotedOn) private var quotes: [Quote]

    @State private var outcomes: [ClaudeModel: Outcome] = [:]
    @State private var running = false
    @State private var flaggedCount = 0

    private var hasKey: Bool { Keychain.read(Keychain.anthropicAPIKey) != nil }

    struct Run {
        var plan: AssistantPlan
        var seconds: Double
        var inputTokens: Int
        var outputTokens: Int
    }

    enum Outcome {
        case result(Run)
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
                Text("Filled in from the Speech test, or type what you would say on the phone. The current records are sent with it, as the Assistant does.")
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
                        Text("Ask both models")
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
        case .result(let run):
            PlanRows(run: run)
        }
    }

    private func runBoth() {
        let text = transcript
        let effort = ClaudeEffort(rawValue: effortRaw) ?? .medium
        let records = AssistantRecords.build(note: text, customers: customers, jobs: jobs, dumpsters: dumpsters, quotes: quotes, now: Date()).text
        running = true
        outcomes = [:]
        Task { @MainActor in
            async let haiku = run(model: .haiku, text: text, records: records, effort: effort)
            async let sonnet = run(model: .sonnet, text: text, records: records, effort: effort)
            let results = await [ClaudeModel.haiku: haiku, ClaudeModel.sonnet: sonnet]
            outcomes = results
            running = false
            let anyFlagged = results.values.contains { outcome in
                if case .result(let run) = outcome { return !run.plan.issues.isEmpty }
                return false
            }
            if anyFlagged { flaggedCount += 1 }
        }
    }

    private func run(model: ClaudeModel, text: String, records: String, effort: ClaudeEffort) async -> Outcome {
        do {
            let answer = try await ClaudeClient.plan(note: text, records: records, model: model, effort: effort)
            return .result(Run(
                plan: answer.plan,
                seconds: answer.seconds,
                inputTokens: answer.inputTokens,
                outputTokens: answer.outputTokens
            ))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

/// One model's plan as plain rows: time, tokens, the reply, each action's
/// type and the fields it filled in, then the questions.
private struct PlanRows: View {
    let run: ClaudeTestView.Run

    var body: some View {
        LabeledContent("Time") {
            Text("\(run.seconds, format: .number.precision(.fractionLength(1))) s")
                .monospacedDigit()
        }
        LabeledContent("Tokens", value: "\(run.inputTokens) in · \(run.outputTokens) out")
        if !run.plan.reply.isEmpty {
            LabeledContent("Reply") {
                Text(run.plan.reply)
                    .multilineTextAlignment(.trailing)
            }
        }
        if run.plan.actions.isEmpty {
            Text("No actions")
                .foregroundStyle(.secondary)
        }
        ForEach(run.plan.actions) { action in
            ActionRows(action: action)
        }
        ForEach(run.plan.issues) { issue in
            Label("\(issue.action + 1). \(issue.field): \(issue.question)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

private struct ActionRows: View {
    let action: AssistantAction

    var body: some View {
        Text("\(action.index + 1). \(action.type)")
            .font(.headline)
        ForEach(action.filledFields) { field in
            LabeledContent(field.name) {
                Text(field.value)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

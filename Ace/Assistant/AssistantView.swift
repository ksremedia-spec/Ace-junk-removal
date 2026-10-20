import SwiftData
import SwiftUI

/// The voice entry point. Record a note; it is written down on the phone;
/// Claude reads it with the records that matter and answers with a list of
/// actions (a new job, a job done and paid, a dumpster swapped, a text to a
/// customer...), a reply, or both. Each action gets its own confirmation
/// screen, in order ("1 of 3"), with Skip; nothing is saved without a tap.
/// A question gets a plain answer.
struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]
    @Query(sort: \Quote.quotedOn) private var quotes: [Quote]
    @Query(sort: \Worker.name) private var workers: [Worker]

    let engine: WhisperKitEngine

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case asking
        case steps
        case answer
        case finished(String)
        case failed(String)
    }

    @State private var recorder = AudioRecorder()
    @State private var phase: Phase = .idle
    @State private var recordingURL: URL?
    @State private var transcript = ""
    @State private var answerText = ""
    /// A note typed instead of spoken (Oct 20: at a desk, typing is faster
    /// and nothing gets misheard).
    @State private var typedNote = ""
    /// Recording through WhisperKit's live mode, words shown as they come.
    /// Off while the voice model is still loading; then it records to a
    /// file and transcribes afterwards, as before.
    @State private var listeningLive = false
    @FocusState private var typing: Bool
    private var hasKey: Bool { Keychain.read(Keychain.anthropicAPIKey) != nil }

    // The plan being stepped through.
    @State private var reply = ""
    @State private var steps: [AssistantAction] = []
    /// Every log_hours action; they share one screen, at the first one's
    /// place in the steps.
    @State private var laborActions: [AssistantAction] = []
    @State private var stepIndex = 0
    @State private var refs = RecordRefs()
    @State private var issues: [PlanIssue] = []
    @State private var confirmations: [String] = []
    @State private var savedCount = 0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                #if os(iOS)
                // The title and "1 of 3" sit together in the bar.
                .navigationBarTitleDisplayMode(stepCounter == nil ? .automatic : .inline)
                #endif
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .top) { stepBanner }
        }
        .onAppear(perform: loadEngine)
        .sensoryFeedback(.success, trigger: savedCount)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .steps:
            stepView
        case .answer:
            answerView
        case .finished(let text):
            finishedView(text)
        default:
            recordView
        }
    }

    private func loadEngine() {
        // A plain Task, not .task, so closing the sheet does not cancel a
        // model download that is halfway through.
        switch engine.state {
        case .notLoaded, .failed:
            Task { await engine.load(model: AppSettings.speechModel) }
        case .ready where engine.loadedModel != AppSettings.speechModel:
            Task { await engine.load(model: AppSettings.speechModel) }
        default:
            break
        }
    }

    // MARK: Title and toolbar

    private var currentStep: AssistantAction? {
        guard phase == .steps, stepIndex < steps.count else { return nil }
        return steps[stepIndex]
    }

    private var title: String {
        currentStep?.kind?.title ?? "Assistant"
    }

    /// "1 of 3", only when there is more than one step.
    private var stepCounter: String? {
        guard currentStep != nil, steps.count > 1 else { return nil }
        return "\(stepIndex + 1) of \(steps.count)"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if recorder.isRecording { _ = recorder.stop() }
                if listeningLive {
                    listeningLive = false
                    Task { _ = try? await engine.stopListening() }
                }
                dismiss()
            }
        }
        if stepCounter != nil {
            ToolbarItem(placement: skipPlacement) {
                Button("Skip") { advance() }
            }
        }
        #if os(iOS)
        if let counter = stepCounter {
            ToolbarItem(placement: .principal) {
                StepTitle(title: title, counter: counter)
            }
        }
        #endif
    }

    private var skipPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .bottomBar
        #else
        return .cancellationAction
        #endif
    }

    /// The reply above the first step. On the Mac, where a sheet has no
    /// title bar, also the step's title and "1 of 3". Under them, in the
    /// warning color, Claude's questions about a field the screen has no row
    /// for, such as which job was meant.
    @ViewBuilder
    private var stepBanner: some View {
        if !bannerLines.isEmpty || !unshownQuestions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(bannerLines, id: \.self) { line in
                    Text(line)
                        .foregroundStyle(.secondary)
                }
                ForEach(unshownQuestions, id: \.self) { question in
                    Text(question)
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var bannerLines: [String] {
        guard currentStep != nil else { return [] }
        var lines: [String] = []
        #if os(macOS)
        if let counter = stepCounter { lines.append(title + " · " + counter) }
        #endif
        if stepIndex == 0, !reply.isEmpty { lines.append(reply) }
        return lines
    }

    /// The current step's questions about fields its screen does not show.
    private var unshownQuestions: [String] {
        guard let step = currentStep,
              let onScreen = (step.kind ?? .newJob).fieldsOnScreen else { return [] }
        var seen = Set<String>()
        return issues
            .filter { $0.action == step.index && !onScreen.contains(AssistantFlags.key($0.field)) }
            .map(\.question)
            .filter { seen.insert($0).inserted }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepView: some View {
        if let step = currentStep {
            AssistantStepView(
                action: step,
                issues: issues.filter { $0.action == step.index },
                refs: refs,
                customers: customers,
                jobs: jobs,
                dumpsters: dumpsters,
                quotes: quotes,
                onFinish: { finishStep($0) },
                onSkip: { advance() },
                onStartOver: { reset() },
                onStartNewJob: { startNewJobInstead() },
                engine: engine,
                laborActions: laborActions,
                laborIssues: issues.filter { issue in laborActions.contains { $0.index == issue.action } },
                workers: workers
            )
            // A fresh screen for every step, even two of the same kind.
            .id("\(stepIndex) \(step.type)")
        }
    }

    /// One step saved (or, with an empty text, closed without a change).
    private func finishStep(_ confirmation: String) {
        if !confirmation.isEmpty {
            confirmations.append(confirmation)
            savedCount += 1
        }
        advance()
    }

    /// The next step, or the end.
    private func advance() {
        if stepIndex + 1 < steps.count {
            stepIndex += 1
        } else {
            finishAll()
        }
    }

    /// "Job saved." or "3 changes saved.", briefly, then the sheet closes.
    /// With nothing saved it just closes.
    private func finishAll() {
        guard let last = confirmations.last else {
            dismiss()
            return
        }
        phase = .finished(confirmations.count == 1 ? last : "\(confirmations.count) changes saved.")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if case .finished = phase { dismiss() }
        }
    }

    /// "Start a new job instead" on an update that found no job.
    private func startNewJobInstead() {
        guard stepIndex < steps.count else { return }
        steps[stepIndex].type = AssistantAction.ActionType.newJob.rawValue
    }

    private func finishedView(_ text: String) -> some View {
        Form {
            Section {
                Label(text, systemImage: "checkmark.circle")
            }
            Section {
                Button("Done") { dismiss() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Record

    private var recordView: some View {
        Form {
            if !hasKey {
                Section {
                    Label("The Assistant needs your Anthropic API key first. Add it in Settings › API key.", systemImage: "key")
                        .foregroundStyle(Tint.owed)
                }
            }

            Section {
                switch phase {
                case .idle, .recording:
                    HStack(spacing: Space.m) {
                        HoldToTalkButton(
                            isListening: phase == .recording,
                            onStart: startRecording,
                            onEnd: stopRecording
                        )
                        Text(phase == .recording ? "Listening." : "or type it below")
                            .foregroundStyle(.secondary)
                    }
                    if phase == .recording, listeningLive {
                        LiveWords(engine: engine, placeholder: "Start talking. The words show up here.", minHeight: 60)
                            .font(.title3)
                    }
                case .transcribing:
                    HStack {
                        ProgressView()
                        Text("Writing down what you said.")
                            .foregroundStyle(.secondary)
                    }
                case .asking:
                    HStack {
                        ProgressView()
                        Text("Working out what to do.")
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    HStack(spacing: Space.s) {
                        // The note is kept: a network or Claude error no
                        // longer means saying it all again.
                        if !transcript.isEmpty {
                            Button {
                                Task { @MainActor in await ask(transcript) }
                            } label: {
                                Label("Send again", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.action(.accentColor, prominent: true))
                        }
                        Button("Start over") { reset() }
                            .buttonStyle(.action(.secondary))
                    }
                default:
                    EmptyView()
                }
                if case .denied = recorder.state {
                    Text(microphoneOffText)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Hold to talk and let go to send, or tap once to talk hands-free and tap again to send. Say or type it the way you would on the phone. A new job, a quote visit, a job done and paid, a dumpster dropped off or picked up, a customer's new number. Several things can go in one note. Or ask, like \"who lives at 63 Locust Street\" or \"which dumpsters are due back Friday\".")
            }

            Section {
                TextField("Type a note", text: $typedNote, prompt: Text("Johnson, 42 Elm, garage cleanout tomorrow at 9, $300 cash"), axis: .vertical)
                    .lineLimit(2...6)
                    .focused($typing)
                    .onSubmit(sendTyped)
                    #if os(iOS)
                    // On the iPhone the Send button sits under the keyboard,
                    // so the keyboard's Return key sends the note instead of
                    // starting a new line.
                    .submitLabel(.send)
                    .onChange(of: typedNote) { _, text in
                        guard text.contains("\n") else { return }
                        typedNote = text.replacingOccurrences(of: "\n", with: " ")
                        typing = false
                        sendTyped()
                    }
                    #endif
                    .disabled(phase == .recording || phase == .transcribing || phase == .asking)
                HStack {
                    Spacer()
                    Button {
                        sendTyped()
                    } label: {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.action(.accentColor, prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(typedNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .asking)
                }
            } header: {
                Text("Type it")
            }

            Section {
                switch engine.state {
                case .notLoaded:
                    Text("Voice not set up yet.")
                        .foregroundStyle(.secondary)
                case .downloading(let fraction):
                    ProgressView(value: fraction) {
                        Text("Downloading the voice model (first time only)")
                    } currentValueLabel: {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    }
                case .loading:
                    HStack {
                        ProgressView()
                        Text("Getting voice ready. The first time can take a few minutes; typing works now.")
                            .foregroundStyle(.secondary)
                    }
                case .ready:
                    Label("Voice ready.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Try loading again") {
                        Task { await engine.load(model: AppSettings.speechModel) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            #if os(macOS)
            typing = true
            #endif
        }
    }

    private var microphoneOffText: String {
        #if os(macOS)
        return "Microphone access is off. Turn it on in System Settings › Privacy & Security › Microphone, or type the note."
        #else
        return "Microphone access is off. Turn it on in Settings › Privacy & Security › Microphone."
        #endif
    }

    private func sendTyped() {
        let note = typedNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, phase != .asking else { return }
        transcript = note
        Task { @MainActor in await ask(note) }
    }

    private func startRecording() {
        guard phase == .idle else { return }
        Task { @MainActor in
            guard await recorder.requestPermission() else { return }
            if case .ready = engine.state {
                do {
                    try engine.startListening()
                    listeningLive = true
                    phase = .recording
                    return
                } catch {
                    // Falls through to recording a file.
                }
            }
            listeningLive = false
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("assistant-\(UUID().uuidString).wav")
            recordingURL = url
            recorder.start(to: url)
            if recorder.isRecording {
                phase = .recording
            } else if case .failed(let message) = recorder.state {
                phase = .failed(message)
            }
        }
    }

    private func stopRecording() {
        // Let go before the microphone started (a quick tap): nothing to stop.
        guard phase == .recording else { return }
        phase = .transcribing
        if listeningLive {
            listeningLive = false
            Task { @MainActor in
                do {
                    transcript = try await engine.stopListening().text
                } catch {
                    phase = .failed(error.localizedDescription)
                    return
                }
                guard !transcript.isEmpty else {
                    phase = .failed(nothingHeardText)
                    return
                }
                await ask(transcript)
            }
            return
        }
        _ = recorder.stop()
        Task { @MainActor in
            await process()
        }
    }

    private func process() async {
        guard let recordingURL else {
            phase = .failed("No recording was made.")
            return
        }
        do {
            try await waitForEngine()
            let result = try await engine.transcribe(fileURL: recordingURL)
            transcript = result.text
            try? FileManager.default.removeItem(at: recordingURL)
            guard !transcript.isEmpty else {
                phase = .failed(nothingHeardText)
                return
            }
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        await ask(transcript)
    }

    private var nothingHeardText: String {
        #if os(macOS)
        return "Nothing was heard. Try again a little closer to the microphone, or type the note."
        #else
        return "Nothing was heard. Try again, a little closer to the phone."
        #endif
    }

    /// Sends a note, spoken or typed, to Claude with the records.
    private func ask(_ note: String) async {
        do {
            phase = .asking
            let records = AssistantRecords.build(
                note: note,
                customers: customers,
                jobs: jobs,
                dumpsters: dumpsters,
                quotes: quotes,
                workers: workers,
                now: Date()
            )
            var response: (plan: AssistantPlan, seconds: Double, inputTokens: Int, outputTokens: Int)
            if let saved = Self.savedTestAnswer() {
                response = saved
            } else {
                response = try await ClaudeClient.plan(
                    note: note,
                    directory: records.directory,
                    records: records.text,
                    model: AppSettings.claudeModel,
                    effort: AppSettings.effort
                )
            }
            // Safety net: an answer with an empty action, or with questions
            // about actions it left out, is asked again once on Haiku, which
            // filled these notes correctly in every test.
            if response.plan.actions.contains(where: \.isEmptyShell) || response.plan.isMissingActions {
                response = try await ClaudeClient.plan(
                    note: note,
                    directory: records.directory,
                    records: records.text,
                    model: .haiku,
                    effort: .medium
                )
            }
            refs = records.refs
            reply = response.plan.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            issues = response.plan.issues
            if response.plan.actions.isEmpty {
                answerText = reply.isEmpty ? "No answer was found." : reply
                phase = .answer
            } else {
                laborActions = response.plan.actions.filter { $0.kind == .logHours }
                var firstLaborSeen = false
                steps = response.plan.actions.filter { action in
                    guard action.kind == .logHours else { return true }
                    defer { firstLaborSeen = true }
                    return !firstLaborSeen
                }
                stepIndex = 0
                confirmations = []
                phase = .steps
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Debug builds only: `-debug.plan answer.json` answers every note with
    /// that saved answer (a file in the app's temporary folder) instead of
    /// asking Claude, so the screens can be checked in the Simulator, which
    /// has no API key. A normal launch never carries the argument.
    private static func savedTestAnswer() -> (plan: AssistantPlan, seconds: Double, inputTokens: Int, outputTokens: Int)? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-debug.plan"), index + 1 < args.count else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(args[index + 1])
        guard let data = try? Data(contentsOf: url),
              var plan = try? JSONDecoder().decode(AssistantPlan.self, from: data) else { return nil }
        plan.numberActions()
        return (plan, 0, 0, 0)
        #else
        return nil
        #endif
    }

    /// The speech model may still be downloading when the recording ends.
    private func waitForEngine() async throws {
        while true {
            switch engine.state {
            case .ready:
                return
            case .failed(let message):
                throw AssistantError.speechModel(message)
            case .notLoaded:
                await engine.load(model: AppSettings.speechModel)
            default:
                try await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func reset() {
        phase = .idle
        transcript = ""
        typedNote = ""
        answerText = ""
        reply = ""
        steps = []
        laborActions = []
        stepIndex = 0
        refs = RecordRefs()
        issues = []
        confirmations = []
        recordingURL = nil
    }

    // MARK: Answer

    private var answerView: some View {
        Form {
            Section {
                Text(answerText)
                    .textSelection(.enabled)
            }
            Section {
                Button("Ask something else") { reset() }
                Button("Done") { dismiss() }
            }
        }
        .formStyle(.grouped)
    }

    enum AssistantError: LocalizedError {
        case speechModel(String)

        var errorDescription: String? {
            switch self {
            case .speechModel(let message): return "The speech model could not be loaded. \(message)"
            }
        }
    }
}

/// The title with "1 of 3" under it, in the iPhone's title area.
private struct StepTitle: View {
    let title: String
    let counter: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
            Text(counter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

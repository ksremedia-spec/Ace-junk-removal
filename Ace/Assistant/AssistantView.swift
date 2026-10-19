import SwiftData
import SwiftUI

/// The voice entry point. Record a note, it is written down on the phone,
/// Claude fills in the job form, Ashley checks it and saves. A spoken
/// question about the records gets a short answer instead.
struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]

    let engine: WhisperKitEngine

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case asking
        case review
        case answer
        case failed(String)
    }

    @State private var recorder = AudioRecorder()
    @State private var phase: Phase = .idle
    @State private var recordingURL: URL?
    @State private var transcript = ""
    @State private var draft: JobDraft?
    @State private var answerText = ""
    @State private var flagged = 0

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .review:
                    if let draft {
                        JobReviewView(draft: draft, onSaved: { dismiss() }, onStartOver: { reset() })
                    }
                case .answer:
                    answerView
                default:
                    recordView
                }
            }
            .navigationTitle("Assistant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if recorder.isRecording { _ = recorder.stop() }
                        dismiss()
                    }
                }
            }
        }
        .task {
            if engine.state == .notLoaded {
                await engine.load(model: AppSettings.speechModel)
            } else if case .failed = engine.state {
                await engine.load(model: AppSettings.speechModel)
            }
        }
        .sensoryFeedback(.warning, trigger: flagged)
    }

    // MARK: Record

    private var recordView: some View {
        Form {
            Section {
                switch phase {
                case .idle:
                    Button {
                        startRecording()
                    } label: {
                        Label("Record", systemImage: "mic.fill")
                    }
                case .recording:
                    Button {
                        stopRecording()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    Text("Listening.")
                        .foregroundStyle(.secondary)
                case .transcribing:
                    HStack {
                        ProgressView()
                        Text("Writing down what you said.")
                            .foregroundStyle(.secondary)
                    }
                case .asking:
                    HStack {
                        ProgressView()
                        Text("Filling in the form.")
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Try again") { reset() }
                default:
                    EmptyView()
                }
                if case .denied = recorder.state {
                    Text("Microphone access is off. Turn it on in Settings.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Say the job the way you would on the phone: who, where, when, what, and the price. Or ask about the records, like which dumpsters are due back Friday.")
            }

            Section {
                switch engine.state {
                case .notLoaded:
                    Text("Speech model not loaded.")
                        .foregroundStyle(.secondary)
                case .downloading(let fraction):
                    ProgressView(value: fraction) {
                        Text("Downloading the speech model")
                    } currentValueLabel: {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    }
                case .loading:
                    HStack {
                        ProgressView()
                        Text("Preparing the speech model. The first time can take a few minutes.")
                            .foregroundStyle(.secondary)
                    }
                case .ready:
                    Text("Speech model ready.")
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
    }

    private func startRecording() {
        Task { @MainActor in
            guard await recorder.requestPermission() else { return }
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
        _ = recorder.stop()
        phase = .transcribing
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
                phase = .failed("Nothing was heard. Try again, a little closer to the phone.")
                return
            }
            phase = .asking
            let response = try await ClaudeClient.fillJobForm(
                transcript: transcript,
                model: AppSettings.claudeModel,
                effort: AppSettings.effort,
                records: recordsSummary()
            )
            draft = response.draft
            if response.draft.isQuestion {
                answerText = response.draft.answer.isEmpty ? "No answer was found in the records." : response.draft.answer
                phase = .answer
            } else {
                if !response.draft.issues.isEmpty { flagged += 1 }
                phase = .review
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
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
        draft = nil
        answerText = ""
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

    /// A short, plain-text snapshot of the records for answering questions.
    private func recordsSummary() -> String {
        var lines: [String] = []
        lines.append("Dumpsters:")
        for dumpster in dumpsters {
            var line = "- \(dumpster.displayName): \(dumpster.status().rawValue)"
            if dumpster.isOut {
                if let customer = dumpster.customer { line += ", \(customer.name)" }
                if !dumpster.location.isEmpty { line += ", at \(dumpster.location)" }
                if let due = dumpster.dueBackAt { line += ", due back \(due.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))" }
            }
            lines.append(line)
        }
        let calendar = Calendar.current
        let today = Dates.startOfToday()
        let horizon = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        let upcoming = jobs.filter { !$0.isDone && $0.scheduledAt >= today && $0.scheduledAt <= horizon }.prefix(40)
        lines.append("Jobs in the next two weeks:")
        if upcoming.isEmpty { lines.append("- none") }
        for job in upcoming {
            var line = "- \(job.scheduledAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))"
            if job.hasTime { line += " " + job.scheduledAt.formatted(date: .omitted, time: .shortened) }
            line += ": \(job.customer?.name ?? "no customer"), \(job.jobType.rawValue)"
            if let address = job.customer?.address, !address.isEmpty { line += ", \(address)" }
            if !job.priceText.isEmpty { line += ", \(job.priceText) \(job.paymentType.rawValue.lowercased())\(job.isPaid ? ", paid" : ", unpaid")" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
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

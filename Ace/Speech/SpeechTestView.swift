import SwiftUI

/// Debug panel 1: record a short clip, save it with a label, and run it
/// through the speech engine. Shows the transcript and how long it took.
struct SpeechTestView: View {
    @State private var store = RecordingStore()
    @State private var recorder = AudioRecorder()
    @State private var engine = WhisperKitEngine()

    @AppStorage("debug.whisperModel") private var selectedModel = "openai_whisper-base.en"
    @AppStorage("debug.transcript") private var sharedTranscript = ""

    @State private var label = ""
    @State private var pendingFileURL: URL?
    @State private var transcribingID: UUID?
    @State private var errorMessage: String?
    @State private var savedCount = 0

    var body: some View {
        Form {
            modelSection
            recordSection
            recordingsSection
        }
        .formStyle(.grouped)
        .navigationTitle("Speech test")
        .sensoryFeedback(.success, trigger: savedCount)
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Model

    private var modelSection: some View {
        Section {
            Picker("Model", selection: $selectedModel) {
                ForEach(WhisperKitEngine.modelChoices) { choice in
                    Text(choice.shortName)
                        .tag(choice.name)
                }
            }
            if let description = WhisperKitEngine.modelChoices.first(where: { $0.name == selectedModel })?.description {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            switch engine.state {
            case .notLoaded:
                Button("Load model") {
                    Task { await engine.load(model: selectedModel) }
                }
            case .downloading(let fraction):
                ProgressView(value: fraction) {
                    Text("Downloading model")
                } currentValueLabel: {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                }
            case .loading:
                HStack {
                    ProgressView()
                    Text("Preparing model for this device. The first time can take several minutes.")
                        .foregroundStyle(.secondary)
                }
            case .ready:
                LabeledContent("Loaded", value: WhisperKitEngine.shortName(engine.loadedModel))
                if engine.loadedModel != selectedModel {
                    Button("Switch to selected model") {
                        Task { await engine.load(model: selectedModel) }
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await engine.load(model: selectedModel) }
                }
            }
        } header: {
            Text("WhisperKit")
        } footer: {
            Text("The model downloads once (needs internet), then works offline.")
        }
    }

    // MARK: Record

    private var recordSection: some View {
        Section {
            TextField("Label, e.g. truck noise", text: $label)
            Button {
                toggleRecording()
            } label: {
                if recorder.isRecording {
                    Label("Stop", systemImage: "stop.fill")
                } else {
                    Label("Record", systemImage: "mic.fill")
                }
            }
            if case .denied = recorder.state {
                Text("Microphone access is off. Turn it on in Settings.")
                    .foregroundStyle(.secondary)
            }
            if case .failed(let message) = recorder.state {
                Text(message).foregroundStyle(.secondary)
            }
        } header: {
            Text("New recording")
        } footer: {
            Text("Tap Record, say a job the way you would on the phone, then tap Stop. The clip is saved on this device.")
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            let duration = recorder.stop()
            if let url = pendingFileURL {
                store.add(label: label, fileURL: url, durationSeconds: duration)
                label = ""
                savedCount += 1
            }
            pendingFileURL = nil
        } else {
            Task { @MainActor in
                guard await recorder.requestPermission() else { return }
                let url = store.newFileURL()
                pendingFileURL = url
                recorder.start(to: url)
            }
        }
    }

    // MARK: Recordings

    private var recordingsSection: some View {
        Section {
            if store.recordings.isEmpty {
                Text("No recordings yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.recordings) { recording in
                recordingRow(recording)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            store.delete(recording)
                        }
                    }
            }
            .onDelete { offsets in
                store.delete(at: offsets)
            }
        } header: {
            Text("Recordings")
        }
    }

    @ViewBuilder
    private func recordingRow(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recording.label)
                    .font(.headline)
                Spacer()
                Text(recording.durationSeconds, format: .number.precision(.fractionLength(1)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                + Text(" s").foregroundStyle(.secondary)
            }
            Text(recording.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let text = recording.whisperText {
                Divider()
                Text("WhisperKit · \(WhisperKitEngine.shortName(recording.whisperModel)) · \(recording.whisperSeconds ?? 0, format: .number.precision(.fractionLength(1))) s")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(text.isEmpty ? "(nothing recognized)" : text)
                    .textSelection(.enabled)
                Button("Use in Claude test") {
                    sharedTranscript = text
                }
                .font(.footnote)
            }

            Divider()
            Text("Apple SpeechTranscriber · not added yet")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            HStack {
                if transcribingID == recording.id {
                    ProgressView()
                    Text("Transcribing")
                        .foregroundStyle(.secondary)
                } else {
                    Button(recording.whisperText == nil ? "Transcribe" : "Transcribe again") {
                        transcribe(recording)
                    }
                    .disabled(engine.state != .ready || transcribingID != nil)
                }
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }

    private func transcribe(_ recording: Recording) {
        transcribingID = recording.id
        Task { @MainActor in
            defer { transcribingID = nil }
            do {
                let result = try await engine.transcribe(fileURL: recording.fileURL)
                var updated = recording
                updated.whisperModel = engine.loadedModel
                updated.whisperText = result.text
                updated.whisperSeconds = result.seconds
                store.update(updated)
                sharedTranscript = result.text
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

import SwiftUI

/// Debug panel 1: record a short clip, save it with a label, and run it
/// through the speech engine. Shows the transcript and how long it took.
struct SpeechTestView: View {
    /// Owned by RootView so the loaded model survives leaving this screen.
    let engine: SpeechEngine

    @State private var store = RecordingStore()
    @State private var recorder = AudioRecorder()

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

    // MARK: Engine

    private var modelSection: some View {
        Section {
            switch engine.state {
            case .notLoaded:
                Button("Get voice ready") {
                    Task { await engine.load() }
                }
            case .downloading(let fraction):
                ProgressView(value: fraction) {
                    Text("Downloading Apple's English speech model")
                } currentValueLabel: {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                }
            case .loading:
                HStack {
                    ProgressView()
                    Text("Getting voice ready.")
                        .foregroundStyle(.secondary)
                }
            case .ready:
                LabeledContent("Voice", value: "Ready")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await engine.load() }
                }
            }
        } header: {
            Text("Apple speech recognition")
        } footer: {
            Text("Apple's own engine, on this device. If English isn't installed yet it downloads once, then works offline.")
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
                Text("\(recording.whisperModel ?? "Apple") · \(recording.whisperSeconds ?? 0, format: .number.precision(.fractionLength(1))) s")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(text.isEmpty ? "(nothing recognized)" : text)
                    .textSelection(.enabled)
                Button("Use in Claude test") {
                    sharedTranscript = text
                }
                .font(.footnote)
            }


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
        // Without this, tapping anywhere on the row would press every button in it.
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private func transcribe(_ recording: Recording) {
        transcribingID = recording.id
        Task { @MainActor in
            defer { transcribingID = nil }
            do {
                let result = try await engine.transcribe(fileURL: recording.fileURL)
                var updated = recording
                updated.whisperModel = "Apple"
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

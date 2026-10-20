import Foundation
import Observation
import WhisperKit

/// Wraps WhisperKit (Argmax's open-source Whisper for Apple devices).
/// The model files are downloaded once from Hugging Face into the app's
/// Documents folder; after that everything runs on the device, offline.
@MainActor
@Observable
final class WhisperKitEngine {
    enum State: Equatable {
        case notLoaded
        case downloading(Double)   // 0...1
        case loading
        case ready
        case failed(String)
    }

    struct ModelChoice: Identifiable {
        var name: String
        var description: String

        var id: String { name }

        /// The name without the repeated "openai_whisper-" prefix, for display.
        var shortName: String {
            name.replacingOccurrences(of: "openai_whisper-", with: "")
        }
    }

    /// Model folder names in the argmaxinc/whisperkit-coreml repo. The size in
    /// a name is its download size; the others are roughly 75 MB (tiny),
    /// 150 MB (base) and 500 MB (small).
    static let modelChoices: [ModelChoice] = [
        ModelChoice(name: "openai_whisper-tiny.en", description: "Tiny. Fastest, least accurate. Good for checking the plumbing."),
        ModelChoice(name: "openai_whisper-base.en", description: "Base. Small download, quick, fair accuracy."),
        ModelChoice(name: "openai_whisper-small.en", description: "Small. Better accuracy, slower."),
        ModelChoice(name: "openai_whisper-large-v3-v20240930_626MB", description: "Large v3, 626 MB. Argmax's recommended model for accuracy."),
        ModelChoice(name: "openai_whisper-large-v3-v20240930_turbo_632MB", description: "Large v3 turbo, 632 MB. Nearly as accurate, faster."),
    ]

    static func shortName(_ model: String?) -> String {
        (model ?? "").replacingOccurrences(of: "openai_whisper-", with: "")
    }

    private(set) var state: State = .notLoaded
    private(set) var loadedModel: String?
    private var whisperKit: WhisperKit?

    // MARK: Live transcription (Kyle, Oct 20: "live transcription ... when
    // talking into the app ... It should be using the WhisperKit.")

    /// Words WhisperKit has settled on so far while listening.
    private(set) var liveConfirmed = ""
    /// Words still being worked out; they may change as more is heard.
    private(set) var liveTentative = ""
    private(set) var isListening = false
    /// One streamer per loaded model (WhisperKit issue #517: recreating it
    /// repeatedly grows memory).
    private var streamer: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?

    struct Result {
        var text: String
        /// Wall-clock seconds from handing over the file to getting the text back.
        var seconds: Double
        /// Length of the audio, in seconds, as WhisperKit measured it.
        var audioSeconds: Double
    }

    /// Loads the named model. If its files are already on the device it loads
    /// them directly (no network); otherwise it downloads them with progress.
    /// The very first load of a model also fetches a small tokenizer file, so
    /// that one time needs internet.
    func load(model: String) async {
        // Screenshot runs on Macs with no model files: `-debug.speechready`
        // shows the ready state without loading anything. Recording does not
        // work in that mode; a normal launch never carries this argument.
        if ProcessInfo.processInfo.arguments.contains("-debug.speechready") {
            loadedModel = model
            state = .ready
            return
        }
        if loadedModel == model, whisperKit != nil { return }
        whisperKit = nil
        streamer = nil
        loadedModel = nil
        do {
            var folder = Self.localFolder(for: model)
            var kit: WhisperKit?

            if Self.hasModelFiles(folder) {
                state = .loading
                kit = try? await Self.makeKit(folderPath: folder.path(percentEncoded: false))
            }

            if kit == nil {
                // Not downloaded yet, or incomplete: WhisperKit downloads what
                // is missing. This needs internet.
                state = .downloading(0)
                folder = try await Self.download(model: model) { [weak self] fraction in
                    Task { @MainActor in
                        if case .downloading = self?.state {
                            self?.state = .downloading(fraction)
                        }
                    }
                }
                state = .loading
                kit = try await Self.makeKit(folderPath: folder.path(percentEncoded: false))
            }

            whisperKit = kit
            loadedModel = model
            state = .ready
        } catch is CancellationError {
            // The screen that started the load was closed; try again next time.
            state = .notLoaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Starts listening on the microphone and filling `liveConfirmed` and
    /// `liveTentative` as words are recognised. Needs a loaded model.
    func startListening() throws {
        guard let kit = whisperKit, let tokenizer = kit.tokenizer else { throw EngineError.notLoaded }
        guard !isListening else { return }
        liveConfirmed = ""
        liveTentative = ""
        kit.audioProcessor.purgeAudioSamples(keepingLast: 0)
        if streamer == nil {
            streamer = AudioStreamTranscriber(
                audioEncoder: kit.audioEncoder,
                featureExtractor: kit.featureExtractor,
                segmentSeeker: kit.segmentSeeker,
                textDecoder: kit.textDecoder,
                tokenizer: tokenizer,
                audioProcessor: kit.audioProcessor,
                decodingOptions: DecodingOptions(language: "en"),
                stateChangeCallback: { [weak self] _, new in
                    let confirmed = Self.clean(new.confirmedSegments.map(\.text).joined(separator: " "))
                    let tentative = Self.clean(new.unconfirmedSegments.map(\.text).joined(separator: " "))
                    Task { @MainActor in
                        guard let self, self.isListening else { return }
                        self.liveConfirmed = confirmed
                        self.liveTentative = tentative
                    }
                }
            )
        }
        isListening = true
        let active = streamer
        streamTask = Task.detached {
            try? await active?.startStreamTranscription()
        }
    }

    /// Stops listening and transcribes everything that was heard in one
    /// full pass, which is more accurate than the live words.
    func stopListening() async throws -> Result {
        guard let kit = whisperKit else { throw EngineError.notLoaded }
        isListening = false
        await streamer?.stopStreamTranscription()
        streamTask = nil
        let samples = Array(kit.audioProcessor.audioSamples)
        let started = Date()
        let results = try await Self.run(kit, samples: samples)
        let text = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let final = Self.clean(text).isEmpty ? Self.clean(liveConfirmed + " " + liveTentative) : Self.clean(text)
        return Result(text: final, seconds: Date().timeIntervalSince(started), audioSeconds: Double(samples.count) / 16_000)
    }

    /// WhisperKit's segment text can carry its own markers ("<|0.00|>",
    /// "[BLANK_AUDIO]"); people should only see words.
    nonisolated static func clean(_ text: String) -> String {
        text.replacing(/<\|[^|]*\|>/, with: "")
            .replacing(/\[[A-Z_ ]+\]/, with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Transcribes one audio file. WhisperKit reads WAV, M4A and most other
    /// formats and converts to 16 kHz mono itself.
    func transcribe(fileURL: URL) async throws -> Result {
        guard let kit = whisperKit else {
            throw EngineError.notLoaded
        }
        let started = Date()
        let results = try await Self.run(kit, path: fileURL.path(percentEncoded: false))
        let seconds = Date().timeIntervalSince(started)
        let text = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let audioSeconds = results.first?.timings.inputAudioSeconds ?? 0
        return Result(text: text, seconds: seconds, audioSeconds: audioSeconds)
    }

    // MARK: - Where the files live

    /// Where WhisperKit.download puts a model by default:
    /// Documents/huggingface/models/argmaxinc/whisperkit-coreml/<model>.
    private static func localFolder(for model: String) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(model, isDirectory: true)
    }

    /// The same three files WhisperKit itself requires before it will load.
    private static func hasModelFiles(_ folder: URL) -> Bool {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(name).mlmodelc").path)
        }
    }

    // MARK: - Off the main thread

    // WhisperKit 1.1.1 is built so that its async functions run on whichever
    // actor calls them. Called straight from this @MainActor class, its file
    // reading, tokenizer setup and per-token work would run on the main
    // thread. These nonisolated helpers run on a background thread instead,
    // and WhisperKit follows them there.

    nonisolated private static func download(
        model: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await WhisperKit.download(variant: model) { progress($0.fractionCompleted) }
    }

    nonisolated private static func makeKit(folderPath: String) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            modelFolder: folderPath,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        )
        return try await WhisperKit(config)
    }

    nonisolated private static func run(_ kit: WhisperKit, path: String) async throws -> [TranscriptionResult] {
        try await kit.transcribe(audioPath: path, decodeOptions: DecodingOptions(language: "en"))
    }

    nonisolated private static func run(_ kit: WhisperKit, samples: [Float]) async throws -> [TranscriptionResult] {
        try await kit.transcribe(audioArray: samples, decodeOptions: DecodingOptions(language: "en"))
    }

    enum EngineError: LocalizedError {
        case notLoaded

        var errorDescription: String? {
            switch self {
            case .notLoaded: return "Load a model first."
            }
        }
    }
}

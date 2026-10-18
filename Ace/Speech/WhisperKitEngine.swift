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

    struct Result {
        var text: String
        /// Wall-clock seconds from handing over the file to getting the text back.
        var seconds: Double
        /// Length of the audio, in seconds, as WhisperKit measured it.
        var audioSeconds: Double
    }

    /// Downloads the named model (if needed) with progress, then loads it.
    func load(model: String) async {
        if loadedModel == model, whisperKit != nil { return }
        whisperKit = nil
        loadedModel = nil
        state = .downloading(0)
        do {
            // Returns .../Documents/huggingface/models/argmaxinc/whisperkit-coreml/<model>.
            // Skips files that are already there, so a second call is quick.
            let folder = try await WhisperKit.download(
                variant: model,
                progressCallback: { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        self?.state = .downloading(fraction)
                    }
                }
            )
            state = .loading
            let config = WhisperKitConfig(
                modelFolder: folder.path(percentEncoded: false),
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            whisperKit = kit
            loadedModel = model
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Transcribes one audio file. WhisperKit reads WAV, M4A and most other
    /// formats and converts to 16 kHz mono itself.
    func transcribe(fileURL: URL) async throws -> Result {
        guard let kit = whisperKit else {
            throw EngineError.notLoaded
        }
        let started = Date()
        let options = DecodingOptions(language: "en")
        let results = try await kit.transcribe(
            audioPath: fileURL.path(percentEncoded: false),
            decodeOptions: options
        )
        let seconds = Date().timeIntervalSince(started)
        let text = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let audioSeconds = results.first?.timings.inputAudioSeconds ?? 0
        return Result(text: text, seconds: seconds, audioSeconds: audioSeconds)
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

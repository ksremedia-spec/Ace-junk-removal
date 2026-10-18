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

    /// Model names as they appear in the argmaxinc/whisperkit-coreml repo.
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
        var seconds: Double
    }

    /// Downloads (if needed) and loads the named model.
    func load(model: String) async {
        if loadedModel == model, whisperKit != nil { return }
        whisperKit = nil
        loadedModel = nil
        state = .downloading(0)
        do {
            let folder = try await WhisperKit.download(
                variant: model,
                progressCallback: { progress in
                    Task { @MainActor in
                        self.state = .downloading(progress.fractionCompleted)
                    }
                }
            )
            state = .loading
            let config = WhisperKitConfig(
                modelFolder: folder.path,
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

    /// Transcribes one audio file and reports how long the whole thing took.
    func transcribe(fileURL: URL) async throws -> Result {
        guard let kit = whisperKit else {
            throw EngineError.notLoaded
        }
        let started = Date()
        let options = DecodingOptions(language: "en")
        let results = try await kit.transcribe(audioPath: fileURL.path, decodeOptions: options)
        let seconds = Date().timeIntervalSince(started)
        let text = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return Result(text: text, seconds: seconds)
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

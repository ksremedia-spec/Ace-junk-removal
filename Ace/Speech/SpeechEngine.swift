import AVFoundation
import Foundation
import Observation
import Speech

/// Speech to text with Apple's own engine (SpeechAnalyzer and
/// SpeechTranscriber, iOS 26 and macOS 26), on the device. Replaced
/// WhisperKit on Oct 23: Kyle, testing WhisperKit on his own phone in
/// another app, "very heavy and it makes things run like shit"
/// (docs/decisions.md). Not Apple's keyboard dictation engine
/// (DictationTranscriber), which CLAUDE.md rules out.
///
/// The English model is part of the system; a phone without it downloads it
/// once (the "downloading" state), after which everything runs offline.
@MainActor
@Observable
final class SpeechEngine {
    enum State: Equatable {
        case notLoaded
        case downloading(Double)   // 0...1
        case loading
        case ready
        case failed(String)
    }

    struct Result {
        var text: String
        /// Wall-clock seconds from the end of the audio to the text.
        var seconds: Double
        /// Length of the audio, in seconds.
        var audioSeconds: Double
    }

    private(set) var state: State = .notLoaded

    /// Words settled on so far while listening.
    private(set) var liveConfirmed = ""
    /// Words still being worked out; they may change as more is heard.
    private(set) var liveTentative = ""
    private(set) var isListening = false

    private var locale: Locale?
    /// The audio format Apple's engine wants; the microphone's is converted.
    private var analyzerFormat: AVAudioFormat?

    // One listen at a time.
    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var startTask: Task<Void, Error>?
    private var resultsTask: Task<Void, Never>?
    /// Counts listens, so words from an earlier one are not shown.
    private var session = 0
    private var finalText = ""
    private let frames = FrameCounter()

    private static let preferredLocale = Locale(identifier: "en-US")

    // MARK: Getting ready

    /// Checks the device can transcribe English and downloads Apple's
    /// English model if it is not installed yet. Safe to call again.
    func load() async {
        // Screenshot runs: show the ready state without loading anything.
        if ProcessInfo.processInfo.arguments.contains("-debug.speechready") {
            state = .ready
            return
        }
        if state == .ready, locale != nil { return }
        state = .loading
        guard SpeechTranscriber.isAvailable else {
            state = .failed("This device can't run Apple's speech recognition.")
            return
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Self.preferredLocale) else {
            state = .failed("Apple's speech recognition doesn't support English on this device.")
            return
        }
        let transcriber = Self.makeTranscriber(locale)
        do {
            switch await AssetInventory.status(forModules: [transcriber]) {
            case .installed:
                break
            case .unsupported:
                state = .failed("Apple's speech recognition doesn't support English on this device.")
                return
            case .supported, .downloading:
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    state = .downloading(0)
                    let watch = Task { [weak self] in
                        while !Task.isCancelled {
                            let fraction = request.progress.fractionCompleted
                            if case .downloading = self?.state { self?.state = .downloading(fraction) }
                            try? await Task.sleep(for: .milliseconds(300))
                        }
                    }
                    defer { watch.cancel() }
                    try await request.downloadAndInstall()
                }
            @unknown default:
                break
            }
            try? await AssetInventory.reserve(locale: locale)
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            self.locale = locale
            state = .ready
        } catch is CancellationError {
            state = .notLoaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        // Volatile results: the words appear while talking and settle as
        // more is heard.
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    // MARK: Listening live

    /// Starts the microphone and fills `liveConfirmed` and `liveTentative`
    /// as words are recognised. Needs `load()` first.
    func startListening() throws {
        guard let locale, let target = analyzerFormat else { throw EngineError.notLoaded }
        // A listen left running (the sheet closed mid-note) is dropped, so
        // its words never land in the new note.
        if isListening { tearDown() }
        liveConfirmed = ""
        liveTentative = ""
        finalText = ""
        frames.reset()
        session += 1
        let current = session

        #if os(iOS)
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audio.setActive(true)
        #endif
        // A microphone that fails to start hands the audio back too.
        var started = false
        defer { if !started { Self.releaseAudio() } }

        let transcriber = Self.makeTranscriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        let engine = AVAudioEngine()
        let mic = engine.inputNode
        let micFormat = mic.outputFormat(forBus: 0)
        guard micFormat.sampleRate > 0, let converter = AVAudioConverter(from: micFormat, to: target) else {
            throw EngineError.noMicrophone
        }
        let counter = frames
        mic.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, with: converter, to: target) else { return }
            counter.add(Int64(buffer.frameLength), rate: micFormat.sampleRate)
            continuation.yield(AnalyzerInput(buffer: converted))
        }
        engine.prepare()
        try engine.start()
        started = true

        self.audioEngine = engine
        self.analyzer = analyzer
        self.input = continuation
        isListening = true

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    guard let self, self.session == current else { return }
                    if result.isFinal {
                        self.finalText = Self.joined(self.finalText, text)
                        self.liveConfirmed = self.finalText
                        self.liveTentative = ""
                    } else {
                        self.liveTentative = Self.clean(text)
                    }
                }
            } catch {
                // The listen was cancelled; nothing to show.
            }
        }
        startTask = Task {
            try await analyzer.start(inputSequence: stream)
        }
    }

    /// Stops the microphone and waits for Apple's engine to settle the last
    /// words, then returns the whole note. If the engine fails at the end,
    /// the words already heard are still returned; it throws only when
    /// nothing at all was heard (audit Oct 24).
    func stopListening() async throws -> Result {
        guard isListening, let analyzer else { throw EngineError.notLoaded }
        isListening = false
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        input?.finish()
        input = nil
        let ended = Date()
        // However this ends, the listen is cleared and the audio handed
        // back, so the truck's music or podcast comes back.
        defer {
            resultsTask = nil
            startTask = nil
            self.analyzer = nil
            Self.releaseAudio()
        }
        var failure: Error?
        do {
            // A quick tap can stop before the analysis has even begun.
            _ = try await startTask?.value
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            failure = error
            await analyzer.cancelAndFinishNow()
        }
        await Self.wait(for: resultsTask, upTo: failure == nil ? .seconds(5) : .seconds(1))
        let text = Self.clean(Self.joined(finalText, liveTentative))
        if let failure, text.isEmpty { throw failure }
        return Result(text: text, seconds: Date().timeIntervalSince(ended), audioSeconds: frames.seconds)
    }

    /// Stops listening without writing anything down.
    func cancelListening() async {
        guard isListening else { return }
        let analyzer = self.analyzer
        tearDown()
        await analyzer?.cancelAndFinishNow()
        liveConfirmed = ""
        liveTentative = ""
        Self.releaseAudio()
    }

    private func tearDown() {
        isListening = false
        session += 1
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        input?.finish()
        input = nil
        resultsTask?.cancel()
        resultsTask = nil
        startTask = nil
        analyzer = nil
    }

    // MARK: A recorded file

    /// Transcribes one audio file (the fallback when live listening could
    /// not start, and the Speech test screen).
    func transcribe(fileURL: URL) async throws -> Result {
        guard let locale else { throw EngineError.notLoaded }
        let file = try AVAudioFile(forReading: fileURL)
        let audioSeconds = Double(file.length) / file.processingFormat.sampleRate
        let transcriber = Self.makeTranscriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let started = Date()
        let collector = Task { () -> String in
            var text = ""
            do {
                for try await result in transcriber.results where result.isFinal {
                    text = Self.joined(text, String(result.text.characters))
                }
            } catch {}
            return text
        }
        if let end = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let text = await collector.value
        return Result(text: Self.clean(text), seconds: Date().timeIntervalSince(started), audioSeconds: audioSeconds)
    }

    // MARK: Helpers

    /// The microphone's audio in the format Apple's engine wants.
    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    /// Waits for a task to finish, but not forever.
    private static func wait(for task: Task<Void, Never>?, upTo limit: Duration) async {
        guard let task else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    private static func joined(_ a: String, _ b: String) -> String {
        [a, b].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// One space between words, nothing around them.
    nonisolated static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Hands the audio back once the microphone is done, so music or a
    /// podcast on the truck's speakers comes back (Oct 20 phone audit).
    private static func releaseAudio() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    enum EngineError: LocalizedError {
        case notLoaded
        case noMicrophone

        var errorDescription: String? {
            switch self {
            case .notLoaded: return "Voice isn't ready yet."
            case .noMicrophone: return "No microphone was found."
            }
        }
    }
}

/// Counts the audio heard, from the microphone's own thread.
private final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total: Double = 0

    func reset() { lock.lock(); total = 0; lock.unlock() }

    func add(_ count: Int64, rate: Double) {
        lock.lock(); total += Double(count) / max(rate, 1); lock.unlock()
    }

    var seconds: Double { lock.lock(); defer { lock.unlock() }; return total }
}

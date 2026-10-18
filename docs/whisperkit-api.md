# WhisperKit API reference (source-verified, v1.1.1)

Verified 2026-10-18 by reading the package source at tag `v1.1.1` (commit
`1bbc57cb`, 2026-10-07) of `https://github.com/argmaxinc/argmax-oss-swift`.
Everything below was read from source unless marked **unconfirmed**. Kept here
so this research is never redone from memory; old tutorials (0.x) are wrong
in several places.

## Package

- Repository: `https://github.com/argmaxinc/argmax-oss-swift` (the old
  `argmaxinc/WhisperKit` URL redirects). Package name and identity:
  `argmax-oss-swift`. Products: `WhisperKit` (what we use), `ArgmaxOSS`
  (umbrella), `TTSKit`, `SpeakerKit`. Latest tag `v1.1.1`.
- Platforms: iOS 16+, macOS 13+. CI runs on Xcode 16.4, 26.6 and 27.0.
- `import WhisperKit` also brings in `ArgmaxCore` (`Logging`, `ModelState`).
- License MIT. Only third-party dependency: swift-argument-parser.
- In the Xcode project: `XCRemoteSwiftPackageReference` with that URL,
  `upToNextMajorVersion` from `1.1.1`; product dependency `productName =
  WhisperKit`.
- 1.0.0 (May 2026) removed all deprecated APIs: `transcribe` now always
  returns `[TranscriptionResult]`; `supressTokens` became `suppressTokens`;
  free helper functions moved into `ModelUtilities` / `TranscriptionUtilities`.
- `WhisperKit`, `WhisperKitConfig` are classes and **not Sendable**. In a
  Swift 6-language-mode app that is an error when captured in `@Sendable`
  closures; in Swift 5 mode (what this project uses) at most a warning.

## WhisperKitConfig (Configurations.swift)

```swift
public init(model: String? = nil, downloadBase: URL? = nil, modelRepo: String? = nil,
            modelToken: String? = nil, modelEndpoint: String? = nil,
            modelFolder: String? = nil,            // String path, not URL
            tokenizerFolder: URL? = nil, computeOptions: ModelComputeOptions? = nil,
            audioInputConfig: AudioInputOptions? = nil, /* deprecated */
            audioProcessor:, featureExtractor:, audioEncoder:, textDecoder:,
            logitsFilters:, segmentSeeker:, voiceActivityDetector:, /* all optional */
            verbose: Bool = true, logLevel: Logging.LogLevel = .info,
            prewarm: Bool? = nil, load: Bool? = nil, download: Bool = true,
            useBackgroundDownloadSession: Bool = false)
```

- `verbose: false` silences all logging. `LogLevel` cases: `.debug, .info,
  .error, .none`.
- Loading rule: `if config.load ?? (config.modelFolder != nil) { loadModels() }`.
  So `WhisperKitConfig(model: "base.en")` downloads at init but loads lazily
  on the first transcribe; `load: true` loads eagerly.
- Init-time download (`download: true`, `modelFolder == nil`) has **no
  progress callback**. For a progress bar use the static `download` below,
  then a second config with `modelFolder: folder.path, load: true,
  download: false` (this is what the app does).
- `prewarm: true` loads/unloads each Core ML model once to force the
  device-specific compile; lowers peak memory, roughly doubles load time.

## WhisperKit (WhisperKit.swift)

- `open class WhisperKit` — plain class, not an actor, not main-actor.
- `public init(_ config: WhisperKitConfig = WhisperKitConfig()) async throws`.
- Members: `modelState: ModelState` (unloaded, loading, loaded, prewarming,
  prewarmed, downloading, downloaded, unloading), `modelStateCallback`,
  `progress: Progress` (transcription progress), `modelFolder: URL?`,
  `static let sampleRate = 16000`, `currentTimings`.
- `loadModels() async throws`, `prewarmModels() async throws`,
  `unloadModels() async`.

## Download

```swift
public static func download(variant: String, downloadBase: URL? = nil,
                            useBackgroundSession: Bool = false,
                            from repo: String = "argmaxinc/whisperkit-coreml",
                            token: String? = nil,
                            endpoint: String = "https://huggingface.co",
                            progressCallback: ProgressCallback? = nil) async throws -> URL
```

- `ProgressCallback = @Sendable (Progress) -> Void`, called on a background
  thread; use `progress.fractionCompleted` (0…1). Hop to the main actor to
  update UI.
- Variant matching is a glob `*<variant>/*`, so `"base.en"` and
  `"openai_whisper-base.en"` both work; ambiguous or missing names throw
  `WhisperError.modelsUnavailable`.
- Default `downloadBase` is `Documents/huggingface`. Files land in
  `Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/`.
  Already-downloaded files are skipped.
- No Hugging Face token needed for the public repo. Since 1.1.1 tokens are
  read only from `modelToken` / `token:` or the `HF_TOKEN` env var.
- The **tokenizer** is fetched separately on the first `loadModels()` (small
  download from `openai/whisper-<variant>`), then cached. So the very first
  load needs internet even with a pre-downloaded model folder.
- Cancelling the surrounding `Task` throws `CancellationError`.

## Model names (folder names in argmaxinc/whisperkit-coreml)

`openai_whisper-tiny(.en)`, `openai_whisper-base(.en)`,
`openai_whisper-small(.en)`, `openai_whisper-large-v3-v20240930_626MB`,
`openai_whisper-large-v3-v20240930_turbo_632MB`, `openai_whisper-large-v3`
(≈3 GB), `openai_whisper-large-v3_947MB`, `_turbo_954MB`,
`distil-whisper_distil-large-v3_594MB`, `_turbo_600MB`, plus large-v2
variants. Sizes in names are download sizes; tiny ≈ 75 MB, base ≈ 150 MB,
small ≈ 500 MB (**unconfirmed**, Hugging Face unreachable from the research
environment).

Device table built into the package: iPhone 14 Pro through iPhone 16 family
(identifiers `iPhone15`, `iPhone16`, `iPhone17`) default to
`openai_whisper-base` and support every compressed large model. iPhone 16
Pro Max is `iPhone17,2`. The iPhone 17 family (`iPhone18,x`) is not in the
built-in table yet. Argmax's README recommends
`large-v3-v20240930_626MB` for accuracy and `tiny` only for debugging.
`WhisperKit.recommendedModels()` (offline) and
`WhisperKit.recommendedRemoteModels()` (fetches the repo's config.json)
return a `ModelSupport { default, supported, disabled }`.

## Transcription

```swift
open func transcribe(audioPath: String, audioInputOptions: AudioInputOptions? = nil,
                     decodeOptions: DecodingOptions? = nil,
                     callback: TranscriptionCallback? = nil) async throws -> [TranscriptionResult]

open func transcribe(audioArray: [Float] /* 16 kHz mono */, decodeOptions:, callback:,
                     segmentCallback:) async throws -> [TranscriptionResult]
```

- Any file `AVAudioFile` can open (WAV, M4A, MP3, FLAC, CAF, AIFF) at any
  sample rate or channel count; WhisperKit resamples to 16 kHz mono itself.
- Audio ≤ 30 s gives exactly one result. Longer audio: one result (internal
  30-second windows) unless `chunkingStrategy: .vad`, which splits on silence
  and returns one result per chunk. Join with
  `results.map(\.text).joined(separator: " ")` or
  `TranscriptionUtilities.mergeTranscriptionResults(_:)`.
- `TranscriptionResult` is a class: `text`, `segments`, `language`,
  `timings`, `seekTime`.
- `TranscriptionTimings` (struct): `fullPipeline`, `inputAudioSeconds`,
  `audioLoading`, `encoding`, `decodingLoop`, `totalDecodingLoops`,
  `tokenizerLoadTime`, computed `realTimeFactor`, `tokensPerSecond`.
- `TranscriptionCallback = @Sendable (TranscriptionProgress) -> Bool?` on a
  background thread; return `false` to stop early.
- Errors: `WhisperError` (`modelsUnavailable`, `loadAudioFailed`,
  `transcriptionFailed`, `microphoneUnavailable`, …), `LocalizedError`.

## DecodingOptions (struct, Sendable)

`init(verbose: false, task: .transcribe, language: String? = nil,
temperature: 0.0, temperatureIncrementOnFallback: 0.2, temperatureFallbackCount: 5,
sampleLength: 224, topK: 5, usePrefillPrompt: true, detectLanguage: Bool? = nil,
skipSpecialTokens: false, withoutTimestamps: false, wordTimestamps: false,
maxInitialTimestamp:, maxWindowSeek:, clipTimestamps: [], windowClipTime: 1.0,
promptTokens:, prefixTokens:, suppressBlank: false, suppressTokens:,
compressionRatioThreshold: 2.4, logProbThreshold: -1.0,
firstTokenLogProbThreshold: -1.5, noSpeechThreshold: 0.6,
concurrentWorkerCount: (16 macOS / 4 iOS), chunkingStrategy: ChunkingStrategy? = nil)`

- `language` is an ISO code (`"en"`), ignored by `*.en` models.
- `chunkingStrategy: .vad` only matters for audio over 30 seconds.

## Live microphone (not used in step 1)

`public actor AudioStreamTranscriber` with `startStreamTranscription()` /
`stopStreamTranscription()` and a state callback; or
`whisperKit.audioProcessor.startRecordingLive { samples in }` and
re-transcribe the growing buffer every second (what the WhisperAX sample
does). An open issue (#517, Aug 2026) reports memory growth when
`AudioStreamTranscriber` is recreated repeatedly on iPadOS 26; keep one
instance, or record-then-transcribe as this app does.

## Simulator

WhisperKit forces CPU-only compute in the Simulator and the maintainers say
results are unreliable beyond `tiny`. Test on the real iPhone.

## First-launch cost

Core ML compiles ("specializes") a downloaded model for the device's chip on
first load. User reports: a few seconds to several minutes depending on model
and chip; repeated after each OS update. When launched from Xcode the
specialization can re-run every launch; launched from the home screen it is
cached. Plan for a visible "Preparing model" state.

# Platform facts

Fact sheet for Kyle, dated October 18, 2026. Each statement starts with **Verified** (read in a primary source, link given), **Likely** (secondary sources agree, or the primary source is vague), or **Unknown** (nobody could confirm). Nothing here was built or run; the research sessions ran on Linux with no Xcode.

## What this means for the plan

- Keep the minimum at iOS 26 / macOS 26. iOS 27 and macOS 27 shipped in September 2026, so this is exactly one version back, and nothing in the 27 cycle changed the speech, controls or storage features the app needs.
- Kyle's Mac must be Apple silicon running macOS 26.6 or newer to use the current Xcode (27.1). An Intel Mac tops out at Xcode 26.x. If his iPhone 16 Pro Max is already on iOS 27, Xcode 27 is very probably required.
- Apple's SpeechTranscriber is a good fit, but it is not on every iOS 26 phone: iPhone 11-series and iPhone SE 2 fail the availability check. The app must check `SpeechTranscriber.isAvailable` and fall back. It also does not work in the iPhone Simulator; test on a real phone or the Mac build.
- WhisperKit is also viable (MIT license, iOS 16+ floor, actively tested on OS 26 and 27). Both engines need a one-time model download, then run offline. Pick by testing on Kyle's phone, as planned.
- Pay the $99/year Apple Developer Program. The free account limits you to 3 devices and the app stops working every 7 days. Paid: iPhones get a yearly re-install; the Mac app gets notarized and keeps working indefinitely.
- The Lock Screen / Control Center button needs a second target (a Widget Extension). The Action button alone can be done with a plain App Shortcut in the main app, no extension.
- Keep the hand-written Xcode project file for now; reconsider XcodeGen only when the Widget Extension target is added.
- Both model IDs (`claude-haiku-5-5`, `claude-sonnet-5-5`) are real and current. Get the form back as strict JSON via structured outputs (`output_config.format`), never via forced tool use, which Sonnet 5.5 rejects.
- The device-held API key is acceptable for two trusted users per Anthropic's own guidance, but the cleaner option is relaying through the existing Cloudflare Worker. Decide and record in `docs/decisions.md`.
- Storage: SwiftData or GRDB both work at this size; GRDB is recommended because the sync needs a schema you fully control. Cloudflare D1 is far larger than needed, but the $5/month plan removes a daily hard cutoff.

## Current Apple releases and Xcode

- Verified: Xcode 27.1 is current (October 15, 2026); iOS 27.0.1 and macOS 27.0.1 shipped September 28, 2026; 27.2 is in beta (https://developer.apple.com/news/releases/).
- Verified: Xcode 27 and 27.1 require macOS Tahoe 26.6 or later and run only on Apple silicon Macs (https://developer.apple.com/support/xcode/, https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes).
- Verified: Xcode 26.0 to 26.3 run on macOS Sequoia 15.6 or later (the last Intel-capable line); 26.4.1 to 26.6 need Tahoe 26.2+. No Xcode with an iOS 26 SDK runs on macOS 14 (https://developer.apple.com/support/xcode/).
- Verified: macOS 26 is the final release for Intel Macs; macOS 27 is Apple silicon only (https://developer.apple.com/videos/play/wwdc2025/102/, https://developer.apple.com/news/).
- Likely: iOS 26 and iOS 27 both run on iPhone 11, iPhone SE (2nd gen) and newer; XS/XS Max/XR were dropped. (Apple's support pages were unreachable from the research sandbox; press coverage agrees.)
- Likely: iOS 27.0 and macOS 27 ("Golden Gate") first shipped September 14, 2026.
- Verified: Xcode 27.2 beta adds an optional JSON project format (.xcproj); it is beta-only and should not be adopted yet (https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes).

**So what.** The plan's version assumptions hold. The one hard check is Kyle's Mac: it must be Apple silicon on macOS 26.6+ for Xcode 27.1. The project's run guide currently says "Xcode 26 / macOS 15.6" and needs updating once Kyle confirms his setup.

Still unknown:
- Whether Xcode 26 can deploy to an iPhone already on iOS 27 (likely not; no explicit Apple statement found).

## Apple SpeechTranscriber (on-device speech-to-text)

- Verified: SpeechAnalyzer, SpeechTranscriber, DictationTranscriber and AssetInventory are all iOS 26.0 / macOS 26.0 APIs (https://developer.apple.com/documentation/speech/speechtranscriber).
- Verified: Apple says SpeechTranscriber has "certain hardware requirements" and tells developers to check `isAvailable` / `supportedLocales` and fall back to DictationTranscriber. Apple DTS: "We typically do not publish such lists." (https://developer.apple.com/videos/play/wwdc2025/277/, https://developer.apple.com/forums/thread/802863)
- Likely: works on iPhone 12 and newer and iPhone SE 3; unavailable on iPhone 11/11 Pro/11 Pro Max and SE 2 (developer reports on Apple's forums, no Apple statement).
- Likely: it does not require an Apple Intelligence chip (works on iPhone 12, which has none).
- Verified: transcription is entirely on device; the language model is downloaded from Apple's servers into shared system storage, is updated automatically by the system, and the system "may unsubscribe your app from assets that haven't been used in a while" (https://developer.apple.com/documentation/speech/assetinventory, https://developer.apple.com/videos/play/wwdc2025/277/).
- Verified: custom vocabulary (`contextualStrings`, up to 100 phrases) exists only on DictationTranscriber, not SpeechTranscriber (https://developer.apple.com/documentation/speech/dictationtranscriber).
- Verified: three helper classes in Apple's current sample (`AnalyzerInputConverter`, `CaptureInputSequenceProvider`, `AssetInputSequenceProvider`) are iOS 27 only; an iOS 26 app must convert audio itself with AVAudioConverter (https://developer.apple.com/documentation/speech/analyzerinputconverter).
- Verified: the `.offlineTranscription` preset shown in the WWDC video does not exist in the shipping SDK; use `.transcription` (https://developer.apple.com/documentation/speech/speechtranscriber/preset).
- Likely: SpeechTranscriber does not work in the iOS 26 Simulator (consistent developer reports; no Apple statement).
- Verified: no WWDC26 session, and no entry in the iOS 27 / macOS 27 / Xcode 27 release notes, concerns the Speech framework (https://developer.apple.com/videos/wwdc2026/).

**So what.** This engine costs the app nothing in download size and runs fully offline once the model is on the phone, but the app must handle three things: a first-run download that needs network, a runtime availability check with a fallback, and a possible re-download later. Testing happens on Kyle's iPhone or the Mac build, not the Simulator. Do not paste Apple's current sample code verbatim; it will not compile for iOS 26.

Still unknown:
- Model download size for English (Apple publishes no number).
- Whether SpeechTranscriber output is punctuated and capitalized (no option exists; test it).
- Any maximum recording length.

## WhisperKit (Argmax)

- Verified: current release v1.1.1 (October 8, 2026). The package is now `argmax-oss-swift`; the product is still `WhisperKit`. v1.0.0 (May 2026) was a breaking change, so ignore older tutorials (https://github.com/argmaxinc/WhisperKit/releases).
- Verified: MIT license; no license server or activation (https://raw.githubusercontent.com/argmaxinc/WhisperKit/main/LICENSE).
- Verified: minimum platforms iOS 16 / macOS 13 (https://raw.githubusercontent.com/argmaxinc/WhisperKit/main/Package.swift).
- Verified: Argmax's CI tests on iOS 26.5 and iOS 27.0 Simulators with Xcode 26.6 and 27.0 (https://github.com/argmaxinc/WhisperKit/blob/main/.github/workflows/release-tests.yml).
- Verified: models download from Hugging Face `argmaxinc/whisperkit-coreml` on first use; inference is on-device (https://raw.githubusercontent.com/argmaxinc/WhisperKit/main/Sources/WhisperKit/Core/WhisperKit.swift).
- Verified: the default download path always contacts Hugging Face, even if files are already cached. To run offline, pass `modelFolder` and skip download. Two of three checkers flagged this; one treated it as a nuance. The precise statement above is the better-supported one (https://raw.githubusercontent.com/argmaxinc/WhisperKit/main/Sources/WhisperKit/Core/WhisperKit.swift).
- Verified: the built-in device table has no entry for iPhone 17-family (A19) or M5 chips; pin the model explicitly (recommended: `openai_whisper-large-v3-v20240930_626MB`) (https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Models.swift).
- Verified: first launch compiles the model for the chip, which can take minutes, and this repeats after every OS update (https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Configurations.swift).
- Verified: the Simulator runs CPU-only and the maintainer recommends a real device for anything beyond the "tiny" model (https://github.com/argmaxinc/WhisperKit/issues/302).
- Verified: an open issue reports memory growth when recreating the live transcriber repeatedly on iPadOS 26.5; reuse one instance or use record-then-transcribe (https://github.com/argmaxinc/WhisperKit/issues/517).

**So what.** WhisperKit is a safe second candidate. Its cost is a 600 MB download plus a multi-minute first-launch wait, versus Apple's smaller shared model. Its advantage is working on every phone the app supports. The step-1 Debug screen decides.

Still unknown:
- Measured speed and accuracy on iPhone 15/16 Pro (benchmark sites were unreachable).
- Exact sizes of the smaller models.

## One-tap entry: Control Center, Lock Screen, Action button

- Verified: controls are built with `ControlWidget` + `ControlWidgetButton`, whose action is an App Intent; available iOS 18+, and also macOS 26+ (Control Center and menu bar) (https://developer.apple.com/documentation/widgetkit/controlwidgetbutton).
- Verified: Apple's guide builds controls in a Widget Extension target, and the intent must belong to both the app and the extension to open the app (https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system).
- Verified: the Action button can alternatively run an App Shortcut (`AppShortcutsProvider`, iOS 16+) defined in the main app, no extension needed (https://developer.apple.com/documentation/appintents/hardware-interactions). Two of three checkers corrected the original claim on this point.
- Verified: `openAppWhenRun` is deprecated in iOS 26; use `supportedModes` or an `OpenIntent` (https://developer.apple.com/documentation/appintents/appintent/openappwhenrun).
- Verified: recording without opening the app requires `AudioRecordingIntent` plus a mandatory Live Activity; much more work (https://developer.apple.com/documentation/appintents/audiorecordingintent).
- Likely: tapping an "open the app" control on a locked phone will prompt Face ID first (Apple documents this only for the camera case).
- Verified: no control changes in the iOS 27 cycle (https://developer.apple.com/documentation/updates/widgetkit).

**So what.** Ship one stateless "Record" control backed by an `OpenIntent`, registered as an App Shortcut too, so the same intent covers all three entry points. The control needs a second Xcode target, which is why build step 8 is late in the order.

Still unknown:
- Exact Settings wording for assigning a control to the Action button.
- Which iPhone models have the Action button (widely reported: 15 Pro and all 16/17-family; not confirmed from Apple).

## Distribution: free vs paid Apple account

- Verified: free account: 3 devices, 3 apps per device, profiles expire after 7 days and the app must be rebuilt and reinstalled (https://developer.apple.com/support/compare-memberships/).
- Verified: paid program is $99/year; 100 devices per product family per membership year; disabling a device does not free a slot (https://developer.apple.com/programs/whats-included/, https://developer.apple.com/help/account/devices/devices-overview).
- Likely: Ad Hoc profiles last up to one year (Apple's WWDC19 session says "yearly"; one Apple DTS forum reply said 90 days; no current Apple page states a number). Plan to re-sign and re-install the iPhone build yearly and check the date in the profile.
- Verified: recipients of an Ad Hoc install must enable Developer Mode on their iPhone (https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).
- Verified: for teams created after June 2021, the iPhone app must reach Apple's servers on first launch or it may not open (https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates).
- Verified: Mac: Developer ID + notarization is paid-only; a notarized app keeps running even after the certificate expires (https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution, https://developer.apple.com/developer-id/).
- Verified: since macOS Sequoia, right-click-Open no longer bypasses Gatekeeper; unsigned apps need System Settings > Privacy & Security > Open Anyway (https://developer.apple.com/news/?id=saqachfa).
- Verified: App Groups and Keychain Sharing are available on the free tier; push notifications and iCloud are not (https://developer.apple.com/help/account/reference/supported-capabilities-ios/).

**So what.** The free account cannot serve two other people's phones for more than a week at a time. The paid program is a recurring cost, not one-off, because the iPhone build dies when the profile does.

Still unknown:
- Over-the-air install via a web link (Apple's deployment guide was unreachable; likely works for Ad Hoc with a valid HTTPS host).

## Anthropic API (Claude)

- Verified: `claude-haiku-5-5` (released October 7, 2026) and `claude-sonnet-5-5` (September 28, 2026) are active model IDs with no retirement before late 2027 (https://platform.claude.com/docs/en/about-claude/models/overview).
- Verified: Haiku 5.5 is $0.10 in / $0.50 out per million tokens; Sonnet 5.5 is $2 / $10. A form-fill call costs roughly $0.0001 on Haiku (https://platform.claude.com/docs/en/about-claude/pricing).
- Verified: structured outputs (`output_config.format`, JSON schema with `additionalProperties: false`, all fields required, no min/max) is GA and guarantees schema-valid JSON (https://platform.claude.com/docs/en/build-with-claude/structured-outputs).
- Verified: forced `tool_choice` returns a 400 on Sonnet 5.5; `temperature`, `top_p`, `top_k` and assistant prefill are rejected on both models; use `output_config.effort` ("low" for speed) (https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide).
- Verified: always check `stop_reason` (`refusal`, `max_tokens`) before decoding (https://platform.claude.com/docs/en/api/errors).
- Verified: endpoint `POST https://api.anthropic.com/v1/messages`, headers `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json` (https://platform.claude.com/docs/en/api/overview).
- Verified: Anthropic's no-key App Attest option and official Swift package require iOS 27 / macOS 27, so they cannot be the primary path at an iOS 26 minimum (https://platform.claude.com/docs/en/manage-claude/app-attest).
- Verified: Anthropic tolerates a client-held key for "internal tools" with trusted users. Mitigate with a dedicated Workspace, spend cap, and a key with an expiry (https://platform.claude.com/docs/en/cli-sdks-libraries/sdks/typescript, https://platform.claude.com/docs/en/api/rate-limits).
- Verified: prompt caching needs 512+ tokens; this app's requests are smaller, so it will not engage (https://platform.claude.com/docs/en/build-with-claude/prompt-caching).

**So what.** A small hand-written network client is enough: one POST, three headers, a JSON body, a 30-60 second timeout, and retries on 429/500/529. The form comes back as JSON that matches the schema exactly, which the app decodes straight into the review form.

Still unknown:
- Real latency numbers for Haiku vs Sonnet (Anthropic publishes none; measure).

## Storage, sync, and the Mac app

- Verified: one multiplatform target builds a native iPhone app and a native AppKit-backed Mac app from the same SwiftUI code; "Mac" is a different choice from "Mac Catalyst" (https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target).
- Verified: SwiftData's History API (the change log needed for sync) works on iOS 26; the convenient `HistoryObserver` is iOS 27 only; SwiftData has no built-in sync except CloudKit (https://developer.apple.com/documentation/swiftdata/historyobserver).
- Verified: an iOS 26.1 SwiftData change broke apps using array attributes (https://developer.apple.com/forums/thread/806161).
- Verified: GRDB 7.11.1 (June 2026), MIT, iOS 13+ (https://raw.githubusercontent.com/groue/GRDB.swift/master/CHANGELOG.md).
- Verified: D1 free plan: 500 MB per database, 5 million reads and 100,000 writes per day; since September 1, 2026, exceeding these fails queries until midnight UTC. Paid is $5/month (https://raw.githubusercontent.com/cloudflare/cloudflare-docs/production/src/content/docs/d1/platform/limits.mdx).
- Verified: D1 `batch()` is one transaction; all-or-nothing (https://raw.githubusercontent.com/cloudflare/cloudflare-docs/production/src/content/docs/d1/worker-api/d1-database.mdx).
- Verified: Mac features needed (NavigationSplitView, Commands/menus, keyboard shortcuts, multiple windows, fileImporter, searchFocused for ⌘F) are all available well below macOS 26 (https://developer.apple.com/documentation/swiftui/commands, https://developer.apple.com/documentation/swiftui/view/searchfocused(_:)).
- Verified: `.sensoryFeedback(.success/.warning)` compiles on Mac and is a silent no-op there (https://developer.apple.com/documentation/swiftui/sensoryfeedback).
- Verified: CoreXLSX (Excel reader) last released February 2023; SwiftSheets is new (October 2026) with no adoption yet (https://github.com/CoreOffice/CoreXLSX/tags, https://github.com/nanbu/SwiftSheets).
- Verified: Keychain storage uses `SecItemAdd` etc.; use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `kSecUseDataProtectionKeychain: true` (https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain).

**So what.** The storage choice is the one real decision here. The researchers lean GRDB because the sync needs explicit columns (`updated_at`, `deleted`, `server_seq`) and a change log; SwiftData is viable if Kyle prefers Apple-only dependencies. Either way the sync engine is hand-written in the app and the Worker.

Still unknown:
- Whether CoreXLSX compiles cleanly in Xcode 27 (test by adding it on the Mac).
- Whether an ad-hoc-signed Mac app can write to the data-protection keychain (test on the Mac build as Ashley will install it).

## How the project file is generated

- Verified: the existing hand-written `Ace.xcodeproj` uses Xcode 16+ synchronized folders, one target, iOS/macOS 26.0 targets, and a GitHub Actions workflow on a hosted Mac compiles it (local files: `/home/user/ace-junk-removal/Ace.xcodeproj/project.pbxproj`, `/home/user/ace-junk-removal/.github/workflows/build.yml`).
- Verified: Swift Package Manager alone cannot produce an installable app (https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode).
- Verified: XcodeGen 2.46.0 (July 2026) supports multiplatform targets, packages and app extensions, but only emits the Xcode 16 project format (https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0).
- Likely: Xcode 27 will show an "Update to recommended settings" prompt because the file says LastUpgradeCheck 2600; harmless.

**So what.** Nothing changes until the Widget Extension target is added. At that point hand-editing the project file gets error-prone and XcodeGen (run on the hosted Mac, not Kyle's) becomes worth it.

Still unknown:
- Whether the GitHub Actions build actually succeeded (the research session could not see the run).

## Claims we double-checked

| Claim | Result | Corrected wording | Best source |
|---|---|---|---|
| iOS 26 runs on iPhone 11 and later; XS/XS Max/XR cannot | Confirmed (likely; Apple page unreachable) | Add: iPhone SE 2nd and 3rd gen also supported | support.apple.com/guide/iphone/iphe3fa5df43 |
| SpeechTranscriber runs on every iPhone that runs iOS 26; no Apple Intelligence chip needed | Corrected | Runs on device, but unavailable on iPhone 11-series and SE 2 (reported); no Apple Intelligence chip needed; must check `isAvailable` | developer.apple.com/forums/thread/802863 |
| SpeechTranscriber needs a one-time download, then works offline | Corrected (2 of 3) | Download via AssetInventory, then on-device; but the system auto-updates the model and may remove it if unused, so re-download can be needed | developer.apple.com/documentation/speech/assetinventory |
| WhisperKit: iOS 16/macOS 13 minimum, Hugging Face download, then offline | Confirmed with caveat (split 1 of 3) | Offline only if the app loads from `modelFolder` and skips the download step, which always contacts Hugging Face | github.com/argmaxinc/argmax-oss-swift |
| Control Center, Lock Screen and Action button all need ControlWidget + Widget Extension, iOS 18+ | Corrected (2 of 3) | True for Control Center and Lock Screen; the Action button can also run a plain App Shortcut with no extension | developer.apple.com/documentation/appintents/hardware-interactions |
| Free account: 7-day expiry; paid: Ad Hoc one year, 100 iPhones/year | Confirmed | "One year" is likely, not documented; 100 is per product family | developer.apple.com/support/compare-memberships/ |
| Current Xcode needs macOS 15.x or newer, not macOS 14 | Corrected | Current Xcode 27.1 needs macOS 26.6+ on Apple silicon; only Xcode 26.0-26.3 run on macOS 15.6 | developer.apple.com/support/xcode/ |
| iOS 27 / macOS 27 released September 2026 | Confirmed | | developer.apple.com/news/releases/ |
| `claude-haiku-5-5` and `claude-sonnet-5-5` are valid IDs | Confirmed | | platform.claude.com/docs/en/about-claude/models/overview |
| One multiplatform target builds native iPhone and native Mac apps | Confirmed | | developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target |
| macOS 26 is the last for Intel; only four 2019-2020 Intel Macs | Confirmed | Four-model list is likely, not from an opened Apple page | developer.apple.com/videos/play/wwdc2025/102/ |

## Open questions for Kyle

1. Which Mac do you have (Apple silicon or Intel), and which macOS version is it on?
2. Is your iPhone 16 Pro Max on iOS 26 or iOS 27?
3. Which iPhone models do Ashley and Alex have, and does either have an Action button (iPhone 15 Pro or newer)?
4. Which Mac does Ashley use, and is it Intel or Apple silicon?
5. Do you have a paid Apple Developer Program membership, or only a free account?
6. Do you prefer Apple-only libraries (SwiftData) or accept a third-party database library (GRDB) for the sync?
7. Should Claude calls go through the Cloudflare Worker, or hold the API key on each device as the plan currently says?
8. Is the Cloudflare account on the free Workers plan or the $5/month paid plan?

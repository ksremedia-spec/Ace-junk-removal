# Where things stand

Updated 2026-10-18, late evening (US Eastern). Read this first in a new
session; then `CLAUDE.md` for the rules and `decisions.md` for the why.

## Done (written and compiling; not yet run on a device)

- **Data (step 2):** customers, jobs, six dumpsters and rental history
  stored on the device with SwiftData. `Ace/Data/`.
- **iPhone screens (steps 3 and 4):** tab bar Today, Jobs, Customers,
  Dumpsters; add/edit for jobs and customers; search; swipe to mark done or
  delete; dumpster drop-off, due-back, overdue status, and the weigh-in at
  pickup with the overweight charge (rate in Settings). `Ace/Today`,
  `Ace/Jobs`, `Ace/Customers`, `Ace/Dumpsters`.
- **Mac layout:** sidebar, list, detail (`Ace/Mac/MacMainView.swift`);
  ⌘N new job, ⇧⌘N new customer, ⌥⌘N new window, ⌘F search, ⇧⌘A Assistant;
  right-click menus on jobs and customers; Settings in the app menu (⌘,).
  File › Import is a disabled placeholder until step 7.
- **Assistant (step 6, first version):** toolbar button on every screen.
  Record → WhisperKit transcribes on the phone → Claude fills the form
  (structured output) → review screen with flagged fields in the warning
  color → remaining problems asked one at a time as yes/no questions
  (missing phone, missing price, past date, double booking, Claude's own
  flags) → customer matched by phone or name, or created → job saved.
  Spoken questions ("which dumpsters are due back Friday") are answered
  from a snapshot of the records. Not yet: MapKit address completion,
  Lock Screen / Control Center / Action button entry (step 8).
- **Settings:** API key (Keychain), Claude model and effort, speech model,
  overweight rate per ton, Debug (Speech test, Claude test, Load sample
  data, Clear all data).
- **Build checks:** every push compiles on GitHub's Macs with Xcode 26.6 and
  27.1 for iPhone and Mac. Screenshots workflow photographs each screen in
  the Simulator with sample data (`docs/screenshots/`).
- Research saved: `whisperkit-api.md`, `platform-facts.md`.
- Kyle's setup (confirmed 2026-10-18): paid Apple Developer Program;
  iPhone 16 Pro Max on iOS 27.1; Xcode 27.1. Distribution: Ad Hoc.

## Not done

- Nothing has run on a real device. First run: `run-on-your-mac.md`.
- Step 1's engine comparison (Apple SpeechTranscriber vs WhisperKit) is
  still WhisperKit-only; the Debug screen has the placeholder row.
- Step 5 Cloudflare sync. Step 7 Excel import. Step 8 one-tap entry.
  Step 9 the text-size and dark-mode pass.
- Open questions only Kyle can answer: Ashley's and Alex's iPhone models,
  Ashley's MacBook model and macOS version, the Cloudflare account details,
  the Excel column headings.

## Decisions pending Kyle's word

- Keep or remove the Effort picker (Claude test and Settings).
- Keep or remove the GitHub build check and screenshot workflow.
- Keep or remove "Load sample data" / "Clear all data" in Settings › Debug.
- Exclude the downloaded speech models (up to 630 MB) from iCloud backup.

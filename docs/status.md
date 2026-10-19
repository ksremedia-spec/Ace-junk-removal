# Where things stand

Updated 2026-10-19, early morning UTC (late evening 2026-10-18 US Eastern). Read this first in a new
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

## Added 2026-10-19 (all still unbuilt on a device; the cloud build checks pass)

- **Browser demo for the client** (claude.ai artifact, private until Kyle
  shares it: https://claude.ai/artifact/Mv1yKwDUgPyxR2jaj8qQ3j). Source:
  the session scratchpad `ace-demo/index.html`; a standalone copy
  `ace-demo-standalone/Ace-demo.html` opens in any browser. iPhone view and
  a Mac view (sidebar, list, detail, menu bar, search, sort, right-click
  menus). Opens with about 620 customers and 1,000 jobs already in, the way
  the app looks after the Excel import; File › Import shows the preview
  flow. Figures everywhere: today's totals, owed, per-day totals, customer
  history, dumpster rental history. The Assistant is typed, not spoken, and
  uses Sonnet. It can use a key pasted into the demo's Settings (kept in
  that browser), the viewer's claude.ai login, or the relay below. Settings
  shows a "Connection" row that says whether claude.ai lets the page reach
  Anthropic; that was still unknown when this was written. Verified in
  headless Chrome by a 68-check Playwright script (`ace-demo-tools/`).
- **Demo relay** (`docs/demo-relay/`): a Cloudflare Worker that forwards the
  demo's request with the key as a server secret, so the client can use the
  Assistant from the link with nothing to type. Kyle sets it up; the demo is
  republished with its address (`RELAY_URL` in the demo source).
- **Client screenshot page** (https://claude.ai/artifact/8wvbCffQ4deC7uh8ThqXsC):
  the five iPhone screens; the Mac screens were being added once the cloud
  Mac produced clean ones (the app draws its own windows with `-screenshot`,
  see `Ace/Mac/WindowSnapshot.swift`; with `-screenshot` the sidebar uses a
  plain highlight because the glass one draws black offscreen).
- **App screens show the business:** Today figures and Owed; Jobs with
  Upcoming / Unpaid / Done and per-day totals; "Unpaid" marker; customer
  summary (since, jobs, total, owed), Call and Directions, dumpster rentals;
  dumpster "This month"; Mac sidebar Unpaid and Done, customer sort, richer
  right-click menu. Sample data now has about 600 generated customers,
  1,000 past jobs and 20 past rentals (`SampleData.swift`, seeded, the same
  every load).
- **Demolition** is a job type, and the Assistant works out the job type
  from the work described instead of asking whenever "junk removal" was not
  said (see `decisions.md`).

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

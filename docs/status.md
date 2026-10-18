# Where things stand

Updated 2026-10-18, late evening (US Eastern). Read this first in a new
session; then `CLAUDE.md` for the rules and `decisions.md` for the why.

## Done

- Step 1 of the build order is written: Speech test (WhisperKit) and Claude
  test (Haiku + Sonnet side by side) behind a Debug section, plus the API
  key screen. `README.md` describes the screens; `run-on-your-mac.md` is
  Kyle's guide for the first run.
- I verified: the project compiles for iPhone and Mac on GitHub's build
  check with Xcode 26.6 (runs #1, #2, #3 all green on 2026-10-18). The
  check runs on every push that touches `Ace/` or the project file.
- Reviewed: every file by independent reviewers (behavior bugs), and the
  WhisperKit wrapper against the library's source. All confirmed findings
  were fixed and are listed in the commit messages of 2026-10-18.
- Research saved: `whisperkit-api.md` (source-verified) and
  `platform-facts.md` (iOS/macOS minimums, device support, Xcode
  requirements, free vs paid Apple account, controls and Action button,
  Anthropic API, storage and sync; 7 topics, 11 claims fact-checked by three
  independent checkers each). Read its "What this means for the plan"
  section before step 2. Two things it changed: Apple's SpeechTranscriber is
  not available on every iOS 26 phone (iPhone 11 and SE 2 fail), and the
  current Xcode is 27.1, which needs an Apple silicon Mac on macOS 26.6+.

## Not done, and who is next

- Nothing has run on a real device. Kyle runs it on his iPhone 16 Pro Max
  (see `run-on-your-mac.md`) and reports: did it build, did a model load,
  did a recording transcribe, did Claude fill the form. Any error text goes
  back to the assistant verbatim.
- Apple's SpeechTranscriber is not in the Speech test yet (decision of
  2026-10-18: WhisperKit first). The row placeholder is there.
- Open questions only Kyle can answer: Ashley's and Alex's iPhone models,
  Ashley's MacBook model and macOS version, Kyle's own Mac (Apple silicon or
  Intel, macOS version) and his iPhone's iOS version (26 or 27, which decides
  the Xcode version), and whether he has a paid Apple Developer membership
  (free: 3 devices, app expires every 7 days; paid: one install a year).

## Decisions pending Kyle's word

- Keep or remove the Effort picker on the Claude test screen.
- Keep or remove the GitHub build check (`.github/workflows/build.yml`).
- Exclude the downloaded speech models (up to 630 MB) from iCloud backup.

## Next steps in the build order

2. Data model and local storage for customers, jobs, dumpsters.
3. Customers and jobs screens, iPhone first, then Mac.

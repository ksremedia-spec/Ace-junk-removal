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
- Research saved: `whisperkit-api.md` (source-verified). `platform-facts.md`
  (iOS/macOS minimums, device support, free vs paid Apple account, controls
  and Action button, Anthropic API, storage and sync) is being produced by
  the research run; if the file is missing, that run did not finish and the
  per-topic results are in the session's scratchpad only.

## Not done, and who is next

- Nothing has run on a real device. Kyle runs it on his iPhone 16 Pro Max
  (see `run-on-your-mac.md`) and reports: did it build, did a model load,
  did a recording transcribe, did Claude fill the form. Any error text goes
  back to the assistant verbatim.
- Apple's SpeechTranscriber is not in the Speech test yet (decision of
  2026-10-18: WhisperKit first). The row placeholder is there.
- Open questions only Kyle can answer: Ashley's and Alex's iPhone models,
  Ashley's MacBook model and macOS version, Kyle's own macOS version, and
  whether he has a paid Apple Developer membership (needed for installs
  that last longer than 7 days).

## Decisions pending Kyle's word

- Keep or remove the Effort picker on the Claude test screen.
- Keep or remove the GitHub build check (`.github/workflows/build.yml`).
- Exclude the downloaded speech models (up to 630 MB) from iCloud backup.

## Next steps in the build order

2. Data model and local storage for customers, jobs, dumpsters.
3. Customers and jobs screens, iPhone first, then Mac.

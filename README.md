# Ace Junk Removal app

A native iPhone and Mac app for Ace Junk Removal: customers, jobs, a dumpster
tracker, and voice job entry. Used by two people at the company. Installed
directly from the developer's Mac, not from the App Store.

Read `CLAUDE.md` first: it says who the app is for, how it must look, and the
order things get built. Research and decisions are written up in `docs/`.

## Status

Step 1 written, not yet built: a hidden Debug screen with a Speech test
(record a clip, transcribe it with WhisperKit, see the time it took) and a
Claude test (send the transcript to Haiku and Sonnet, see both filled-in job
forms side by side). Nothing has been compiled or run on a device yet; the
cloud computer that wrote it has no Xcode.

To run it, follow `docs/run-on-your-mac.md`. Decisions so far are in
`docs/decisions.md`.

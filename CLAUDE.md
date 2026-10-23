# Ace Junk Removal — app project

A native Apple app for Ace Junk Removal, a small junk removal and dumpster rental
company in Massachusetts (about 5 trucks, 6 dumpsters, 600–700 customers a year).

- Developer: Kyle (a photographer, not a programmer).
- Users: Ashley (runs the phones and paperwork, iPhone + MacBook) and Alex, the
  owner (drops off and picks up dumpsters, iPhone). Drivers won't use it.
- This repository is separate from the construction app (`resio-clone`). Never
  touch that project from here.

## Start of every session

Kyle works in the Claude desktop app (Code tab, local session, with computer use), not in Terminal. Run commands yourself; don't hand him Terminal steps unless there's no other way. Read HANDOFF.md at the start of every session and keep it current.

## How to work with Kyle

- Explain everything in plain English, no jargon. Describe what a screen does,
  not how the code works.
- Label everything: "I verified X", "I'm assuming X", or "I don't know X, here's
  how to find out". Never state a guess in the same voice as a checked fact.
- Never say something is "tested" or "working" unless it actually ran on a real
  device. If it was only built, or only ran in the Simulator, say so. (Cloud
  sessions run on Linux with no Xcode: nothing can be built or run there. Say
  so whenever it matters.)
- Change only what Kyle asks for. If something else is worth changing, suggest
  it and wait.
- Ask one question at a time when a decision is needed.
- Do research once and get it right. Kyle would rather wait than go through a
  fix-it loop. Record research results in `docs/` so they are not redone.

## Platform and architecture

- One SwiftUI project targeting iPhone and Mac. Minimum iOS 26 and macOS 26
  (Kyle's assumption; confirmed/adjusted in `docs/platform-facts.md`).
- Distribution is direct install from Kyle's Mac (ad hoc or sideload), not the
  App Store or TestFlight.
- Data is stored on the device first, so the app works offline, and syncs to a
  shared backend on Cloudflare (Workers + D1). Kyle, Oct 21 2026: it runs on
  Kyle's own Cloudflare account for now (and Google sign-in on his Google
  Cloud project), so the client has nothing to set up; it can move to them
  later. Details: `docs/device-sync.md`, `docs/decisions.md`. The server
  address is kept out of this public repository.
- AI calls go to the Anthropic API using the client's own account. Starting
  model: `claude-haiku-5-5`. Keep `claude-sonnet-5-5` available as a switch for
  testing. The API key is typed in once per device in Settings and stored in
  the Keychain. It is never stored on the server or in the code.
- Speech-to-text runs on the device. Do NOT use Apple's keyboard dictation
  engine. Kyle, Oct 23 2026: use Apple's SpeechTranscriber (SpeechAnalyzer
  framework, the engine behind Notes and Voice Memos transcripts, not
  DictationTranscriber) on iPhone and Mac. WhisperKit was removed: in his own
  testing on his phone it was too heavy. Code: `Ace/Speech/SpeechEngine.swift`.

## Features for version 1

1. Customers and jobs: name, phone, address, job type, date and time, price,
   payment type (cash, check, card), paid/unpaid, notes. Shared across devices.
2. Dumpster tracker (must-have): 6 dumpsters, each with current location,
   drop-off date, due-back date, price, agreed weight. Alex logs actual weight
   at pickup and the app calculates the overweight charge (rate per unit over
   the agreed weight, editable in Settings). Status: in the yard, out, due
   today, overdue. Fast and one-handed for Alex in the truck.
3. Voice job entry: a one-tap entry point (Lock Screen / Control Center control
   and Action button via App Intents) that opens straight into recording.
   Flow: record → transcribe on device → send transcript plus a fixed list of
   fields to Claude → Claude returns the fields filled in → the app validates →
   Ashley reviews the filled form and taps save. Validation is plain code where
   possible: Apple Maps (MapKit) completes shorthand addresses and asks for a
   missing house number; a code check catches double-bookings (same date and
   time); Claude flags missing price, missing phone, or a date in the past.
   Problems are shown as plain yes/no questions, one at a time. Voice entry can
   also answer simple questions ("which dumpsters are due back Friday?") from
   the local data.
4. Excel import, Mac only: Ashley picks her own .xlsx file. Show a preview
   ("Found 614 customers, 12 rows have no phone number") before saving. Mostly
   column mapping in code; use Claude only to clean messy cells
   ("pd cash 300" → paid, cash, $300).
   Column headings (Oct 21, from the real sheet, a Google Sheet "2026 ACE
   Books", tab "Client Job List"): Date, Customer Name, # and Street Name,
   City State & Zip, Price, Form of Payment, Check #, Not Mailing Address.
   Details and what it means for the import: `docs/ashley-spreadsheet.md`.

Not in version 1: QuickBooks sync, card processing, customer-facing anything,
call recording, extra-day charges (notes field only).

## Design rules — slick and polished, never "AI"

- Kyle, 2026-10-19: "disregard standard control rules. make app look slick -
  i was only trying to avoid an 'AI' look." Custom views are allowed when
  they look better than the stock control (the Mac month grid was the
  first). Keep the familiar Apple structure (List, Form, sheets, navigation,
  swipe actions, context menus) where it already works.
- The shared look lives in `Ace/Support/Design.swift`: the spacing scale
  (`Space`), what each colour means (`Tint`: paid green, owed orange, overdue
  red, done blue), job-type badges, status pills, number tiles, initials
  circles, action buttons and the detail-page header card. Build new screens
  from these instead of one-off styling. The accent colour (a deep teal) is
  the `AccentColor` asset, one place to change.
- System font and system semantic colors. Dark mode and Dynamic Type must work
  on every screen.
- SF Symbols for every icon. No custom illustrations.
- Nothing that reads as "AI": no gradients, no glow, no sparkle icons, no chat
  bubbles, no typing indicators, no emoji in the UI. The voice button is
  labeled "Assistant" with a small, understated AI icon (Apple's Apple
  Intelligence SF Symbol or a quiet waveform), the same size as other toolbar
  icons, no glow or gradient. That icon is the only AI-flavored visual allowed.
- Show the filled-in form after dictation, never the raw transcript. Fields
  needing attention get the standard warning color and a short note.
- iPhone: tab bar (Today, Jobs, Customers, Dumpsters). Nothing deeper than two
  taps.
- Mac: NavigationSplitView (sidebar, list, detail) like Mail and Notes.
  Keyboard shortcuts (⌘N new job, ⌘F search), menu bar items, right-click
  menus, multiple windows. Import lives in the File menu.
- Copy: short, plain business language. "Job saved." "Dumpster 3 is overdue."
  No exclamation points, no first-person voice from the app, no cheerfulness.
- Opens instantly to the last screen. No splash screen, no onboarding beyond
  the microphone permission on first use of Assistant.
- Haptics on save and on a flagged problem, matching Apple's own apps.
- When unsure, match what Reminders, Notes, or Mail would do.

## Build order

1. A hidden Debug screen that takes one audio recording and runs it through
   WhisperKit and Apple's SpeechTranscriber side by side, showing both
   transcripts and timings. Then a second panel that sends the same transcript
   to Haiku and Sonnet and shows both filled forms. Kyle tests on his
   iPhone 16 Pro Max with recordings written together: normal fast speech,
   truck and TV background noise, odd names and street names, missing house
   numbers, double-bookings.
2. Data model and local storage for customers, jobs, dumpsters.
3. Customers and jobs screens, iPhone first, then Mac.
4. Dumpster tracker.
5. Cloudflare sync.
6. Voice job entry with validation, using whichever engine and model won in
   step 1.
7. Excel import on Mac.
8. Lock Screen / Control Center / Action button entry point.
9. Pass on every screen at the smallest and largest text sizes, light and dark.

Deadline: a working version 1 on Ashley's and Alex's devices by about
October 31, 2026.

## Repository layout

- `CLAUDE.md` — this file: who the app is for and the rules above.
- `HANDOFF.md` — where things stand, what is verified or not, open questions,
  next steps and a first-look checklist. Read it first; keep it current.
- `docs/` — research results, decisions and the plain-English guide for
  running the app (`run-on-your-mac.md`). Read `docs/decisions.md` before
  changing direction on anything listed there.
- `Ace.xcodeproj` — the Xcode project. It uses Xcode 16+ "synchronized
  folders": every file under `Ace/` is part of the app automatically, so new
  Swift files need no project-file edits.
- `demo/` — the clickable demo, the client Preview page, slideshow and deck
  (published on claude.ai), with their automatic browser checks. See
  `demo/README.md`.
- `Ace/` — the Swift source. `Speech/` is recording and transcription,
  `Assistant/` is the Claude form-filling, `Support/` is Keychain and helpers.

## Working rules for code

- The cloud session cannot compile Swift. Keep to well-known APIs, re-read
  every change for type errors, and say plainly that it is unbuilt.
- Swift language mode 5 (not 6) to keep concurrency warnings from becoming
  errors. Mark view-facing model classes `@MainActor @Observable`.
- Claude requests use structured output (`output_config.format`) and never
  send `temperature` or a forced `tool_choice`: the current models reject them.
- Apple's speech API: check the Speech framework's .swiftinterface in Xcode's
  SDK before using anything; several helpers (AnalyzerInputConverter,
  CaptureInputSequenceProvider) are iOS 27 only, and the app's minimum is 26.
  WhisperKit is no longer used (`docs/whisperkit-api.md` is kept only as
  history).

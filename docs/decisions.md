# Decisions

Short log of decisions and why, newest first. Written in plain English so it
can be read later without the conversation.

## 2026-10-20 (late night) · Fixes from the iPhone audit

- Kyle asked for the same audit as Oct 19 (reviewers, two skeptics per
  finding, five judges, a summary and a critic), aimed at the phone. Results:
  `review-2026-10-20-iphone/audit.md`. Kyle said to start on the safe fixes.
- Done: swipe-to-delete (jobs, customers) and swipe-to-lost (quotes) ask
  first and never fire on a full swipe; search finds lost quotes; the
  microphone turns off however the Assistant closes, and the audio is handed
  back; Calendar and Labor move to the new day after a night in the
  background; a deleted job or quote is not written back to; a half-typed
  new job, quote, customer or person is not lost to a swipe, and Cancel asks;
  Back from a job whose new time clashes asks the overlap question first
  (leaving a job page still saves, as decided Oct 19); detail page buttons
  wrap instead of running off the screen and are at least 44 points; one
  search rule everywhere (every word must match, accents ignored, digits
  search phones only when the search is a phone number); the dumpster page
  puts the pickup first with Call and Directions; Directions starts driving
  directions; hours over 24 or not a number are refused; many smaller label,
  wording and large-text fixes.
- Decided along the way: a saved job's Paid switch is gone (Mark paid in the
  header saves at once; two controls could disagree). The Labor day comes
  before the figures. The Assistant's toolbar button shows the word
  "Assistant" again (CLAUDE.md). The two Skip buttons are now "Skip step"
  and "Not now". Warning text uses Ace's darker orange everywhere.
- Left for Kyle: the 17 proposals in the audit file (overweight charge on the
  bill, linking dumpster jobs to dumpsters, hiding Debug, and more).

## 2026-10-20 (late night) · iPhone gets the boards and a Labor tab; Quotes moves under Calendar

- Kyle: "pour all the changes we've made today over to the iOS app".
  The iPhone Calendar and Dumpsters use the same cards and tiles as the
  Mac; Labor gets its own tab.
- Five tabs fit on an iPhone; a sixth hides behind "More", two taps deep,
  which breaks the "nothing deeper than two taps" rule. Labor took the
  fifth place and **Quotes moved under Calendar** (its figure and "All
  quotes"). Quotes is mostly Ashley's, at her Mac, where it keeps its own
  sidebar entry; Labor is Alex's, on his phone.
- Fixes found while testing in the iPhone Simulator: number pads get a
  Done button (they have no Return key); the Assistant's note box sends on
  the keyboard's Return key (its Send button sat under the keyboard); a
  Missing question's "Type it", a gap chip and "Fix it" scroll to the field
  and bring up the keyboard; the house number gets a numbers keyboard; the
  largest text sizes stack rows instead of cutting them.

## 2026-10-20 (night) · The Assistant runs on Haiku

- Kyle had Sonnet set ("he'd want the smarter of the two models"). Tested on
  his Mac the same day, with every raw answer saved (Debug builds write
  `tmp/assistant-response-*.json`): Sonnet 5.5 dropped work on most notes -
  an empty form, the name and address missing, the date missing, and three
  times one person out of four on an hours note (twice with no questions
  pointing at the missing ones, so no check could catch it). At the app's
  `medium` effort it often did no thinking at all (`thinking_tokens: 0`);
  at `high` it thought and still returned one of four. Haiku 5.5 filled
  every one of the same notes correctly.
- Kyle: "We can switch to haiku then it's cheaper faster if it's doing the
  job right then it's doing the job right." Settings › Claude model is now
  Haiku on his Mac (the app's default already was). Sonnet stays in
  Settings for testing; the Haiku retry for empty or short answers stays.
- Cause not proven: it looks like Sonnet 5.5 with structured output and
  this 30-field schema, not reasoning. Worth retesting when a new Sonnet
  ships.

## 2026-10-20 (night) · Labor: crew, hours, and the Assistant

- Alex, through Kyle: a Labor tab to track "how many hours each guy worked
  every day"; two guys are on salary and count as working every day; add
  people for seasonal hires; and "build the laborers portion into the
  assistant as well, obviously". Mac first, then iPhone. Filler names and
  wages until Alex fills in his own (Kyle).
- Plain hours per day, not start and end times (Kyle was asked and did not
  answer; hours are quickest to type and say). Salaried work week Monday to
  Saturday, assumed. People leaving are retired, not deleted.
- Assistant: new action `log_hours` (workerName, hours, ref W#, date); all
  of a note's hours on one screen; the crew and two weeks of hours go with
  every note. A second safety net asks Haiku again when Sonnet's answer
  leaves actions out. Details: `labor.md`.

## 2026-10-20 (evening) · Mac Calendar and Dumpsters become wide boards

- Kyle: "I still think the app looks kind of blah." Shown three sketches
  (Ace red and dark; bright cards; a week board), he picked "BNC" (bright
  cards and the week board) and said not to change the colouring: "Ace's
  website is very old. Just use the color we have for now." So the teal
  accent stays; Ace's website red was not used.
- Calendar and Dumpsters on the Mac are now one wide page each, with the
  chosen record in an inspector on the right, instead of a list beside an
  empty pane. Jobs, Quotes and Customers keep sidebar, list and page.
  Details: `calendar-tab.md`, "Mac".

## 2026-10-20 (later) · Missing details as on-screen questions; hold to talk

- Kyle: when the Assistant's form is missing something, "just be able to
  click it and quickly type it in", and have it ask for what was missed
  ("is there a house number, is there an address"). A version that asked
  out loud was built and tried; Kyle: "I don't want it to talk back, maybe
  it asks questions back on screen. And I want a slicker integration of
  it, maybe a hold to talk".
- So: a Missing section at the top of the new-job and new-quote forms asks
  one question at a time on screen, answered by holding the talk button,
  by typing in the field, or skipped; every missing item is also a button
  that puts the cursor in its field. Plain numbers are read in code;
  anything else goes to Haiku in a small separate request. Saving is still
  a tap. Details: `assistant-actions.md`, "Follow-up questions".
- The Assistant's Record/Stop buttons became one **hold to talk** button:
  hold, talk, let go to send; or tap once for hands-free and tap again to
  send (for the truck). The same button answers the questions.
- Same customer or new, Kyle: "both the phone number and customer name need
  to match otherwise new customer". With his Oct 19 rule (same name and
  address is the same customer): the name must match and any phone or
  address said must agree with the record.
- Still Claude + WhisperKit underneath: on-device speech is already a rule,
  and Claude's API works on text (no live speech-to-speech that I know of).

## 2026-10-20 · Assistant: whole directory, thinking on, quote visits, live words

- Claude is sent every customer (cached), so lookups by address or street
  work; until now it saw at most six named customers.
- `thinking: {type: "adaptive"}` is sent explicitly: Sonnet 5.5 without it
  returned empty forms on notes Haiku filled correctly. An empty action is
  asked again once on Haiku.
- "Estimate" is "Quote visit" everywhere (Kyle: they say quotes, never
  estimates). A quote booked for a day is a Quote visit job; a price given
  and not yet accepted is still a quote on the Quotes tab.
- Unpaid means done, priced and not paid, the same as Owed, so the numbers
  agree. Past jobs never marked done belong under "Not marked done".
- Live transcription uses WhisperKit's streaming transcriber (Kyle: "It
  should be using the WhisperKit"), with a full pass at the end for accuracy.

## 2026-10-19 (evening) · Slick over stock; a full-size month on the Mac

- Kyle, at the first look at the Mac app: "calander is too small", then
  chose a full-size month with dots over enlarging Apple's picker, then:
  "disregard standard control rules. make app look slick - i was only trying
  to avoid an 'AI' look."
- So the "standard controls only, no custom-drawn controls" rule is gone.
  Custom views are fine where they look better. What stays: nothing that
  reads as AI (no gradients, glow, sparkles, chat bubbles, typing
  indicators, emoji), system font and colours, dark mode, plain copy.
- First use: the Mac Calendar's month (`MacMonthGrid`) replaces Apple's
  small graphical date picker, with dots under days that have open jobs.
- Then Kyle: "think, and drastically change the look and design of the app,
  work rebuild and test as needed." Done the same evening, see HANDOFF
  "Design pass": a teal accent, job-type badges, status pills instead of
  struck-through names, header cards on every detail page with one-click
  actions, number tiles on Calendar and customer pages, initials circles,
  numbered dumpster badges, sidebar counts, proper empty pages. Choices made
  without Kyle (his to overrule): the teal, the badge colours per job type,
  Done and Paid on the job page saving straight away like the right-click
  menu, and the Mac detail pages kept to 720 points wide.

## 2026-10-18 (evening) · Build the real app now, iPhone and Mac together

Kyle needs something to show the client, so steps 2, 3, 4 and the voice
Assistant (step 6) were built in one pass rather than waiting for step 1
results, and the Mac layout was built alongside the iPhone one rather than
after it. The Assistant uses WhisperKit (per the earlier decision) and the
Claude model chosen in Settings (Haiku by default, Sonnet as the switch).
Step 1's Debug screens stay under Settings › Debug for the engine and model
comparison on Kyle's phone.

## 2026-10-18 (evening) · On-device storage: SwiftData

Customers, jobs, dumpsters and rental history are stored with SwiftData,
Apple's own on-device database. Reason: it fits SwiftUI with the least code
and the least to go wrong before the deadline. The research sheet
(`platform-facts.md`) preferred GRDB because sync needs a schema under our
control; that still holds for step 5, where the plan is to sync by record
id with `updatedAt` timestamps and a per-device change log, which SwiftData
supports well enough. Revisit only if step 5 hits a wall.

## 2026-10-18 (evening) · Sample data lives in Settings › Debug

"Load sample data" fills the app with six dumpsters, six customers and a
week of jobs for showing the client, and "Clear all data" empties it. Both
ask for confirmation. Kyle's addition to approve or remove.

## 2026-10-18 · Tooling and distribution confirmed by Kyle

Kyle has a paid Apple Developer Program membership, an iPhone 16 Pro Max on
iOS 27.1, and Xcode 27.1 on his Mac. So: builds use Xcode 27.x; the minimum
stays iOS 26 / macOS 26; distribution to Ashley and Alex will be Ad Hoc
(their devices registered on the developer account, one install per device
per year, no App Store, no TestFlight). The Mac app can be notarized under
the same membership.

## 2026-10-18 · Speech models load from disk first, download only if missing

A source-level review found that WhisperKit's download call always contacts
Hugging Face, even when the model is already on the phone, so the app would
have failed offline. The app now checks for the model files itself and only
downloads when they are missing. The first load of a model still needs
internet once (a small tokenizer file); after that it is fully offline.
Same review: WhisperKit runs its work on whichever thread calls it, so the
app calls it from background helpers to keep the screen responsive.

Suggested, not done (Kyle to decide): the model files (up to 630 MB) sit in
Documents, which iCloud/iTunes backup includes. They could be excluded from
backup with one flag after download.

## 2026-10-18 · Step 1 uses WhisperKit only, for now

Kyle wants something runnable by morning and cannot confirm Ashley's and
Alex's device models tonight. Decision: build the Debug screen with WhisperKit
alone. Apple's SpeechTranscriber (iOS 26+) stays on the list and can be added
to the same screen later as a second column; the screen already has a
placeholder row for it.

- Kyle's assumption: both iPhones are newer than an iPhone 11, so iOS 26 is
  fine. Unconfirmed. Ashley's MacBook model and macOS version are the real
  unknown for the Mac app.
- Minimum OS stays iOS 26 / macOS 26 until the devices say otherwise.

## 2026-10-18 · How Claude returns the filled-in form

The app asks the Anthropic API for a strictly structured answer
(`output_config.format` with a JSON schema), not for a "tool call". Reason:
the current Sonnet model rejects forced tool calls, and structured output
guarantees the fields come back in the exact shape the app expects. Both
models run with the same effort setting, chosen on the Debug screen, so the
comparison is fair. Temperature is never sent: the current models reject it.

## 2026-10-18 · Project generated by hand, not by a tool

The cloud session has no Mac or Xcode. The Xcode project file was written
directly in the modern format (Xcode 16+, "synchronized folders"), so Xcode
picks up every file in the `Ace` folder automatically and no file list has to
be maintained. It was checked with a project-file parser. Alternative
considered: XcodeGen, which would have needed Kyle to install Homebrew and a
command-line tool. Rejected for now to keep Kyle's steps to "open and run".

## 2026-10-18 · Separate repository

The construction app (`resio-clone`) and this app share nothing. This is its
own repository with its own rules file (`CLAUDE.md`).

## Job types and how the Assistant picks one (2026-10-19)

- Job types are Junk removal, Demolition, Dumpster drop-off, Dumpster pickup and
  Other. Demolition was added because Alex also does demo work (Kyle, 2026-10-19).
- The Assistant works out the job type from the work described ("garage empty"
  is junk removal, "take down the shed" is demolition, "needs a dumpster" is a
  drop-off) and asks only when nothing in the note says what the work is. Kyle
  found that asking whenever the words "junk removal" were missing was wrong.
- The browser demo for the client uses Sonnet (`claude-sonnet-5-5`, effort
  medium) because it cannot be tested from the cloud session and a wrong guess
  in front of the client costs more than the extra pennies. The phone app keeps
  Haiku as the default with Sonnet as the switch, pending the step-1 comparison
  on Kyle's iPhone. Kyle allowed Sonnet ("use sonnet if you have to").

## How the browser demo reaches Claude for the client (2026-10-19)

- Kyle wants the client to open the demo link and have the Assistant work with
  nothing to type, billed to Kyle's key ("using my api key is fine").
- The key is never written into the page. The cloud session's safety check
  refused to build a "write the key into the page" button, and a key in a page
  anyone with the link can read is the wrong shape anyway. Instead the demo can
  send its request through a small relay on Cloudflare Workers
  (`docs/demo-relay/`) that holds the key as a server secret, forces the model
  and answer size, and only answers the demo page's own web addresses. Kyle
  sets it up once; the demo is republished with the relay's address.
- Settings in the demo shows a "Connection" row: whether the page can reach
  Anthropic (or the relay) from inside claude.ai. That answers the one open
  question nobody can settle from the cloud session.
- Fallbacks if claude.ai blocks the connection: the viewer signs in to
  claude.ai (Claude through their own account, no key), or the demo is hosted
  as a plain web page outside claude.ai.

## The Assistant understands five kinds of note (2026-10-19)

- Kyle, after trying it: "I just tried to speak to it to say a job was done
  and paid cash on site and it got lost and asked me for all the info as if
  I was making a job." The Assistant must serve Alex in the field as well as
  Ashley in the office.
- Kinds: `job` (new work), `question`, `update` (an existing job is done,
  paid and how, moved, price changed, note added), `pickup` (a dumpster was
  picked up or weighed), `dropoff` (a dumpster was dropped off). Claude only
  classifies and extracts; the app finds the record itself: customer by
  phone, then name (whole name, or the last word so "Johnson" finds Linda
  Johnson), then address; the job by the spoken date, else today's open job,
  else the nearest open job, else the latest done one; the dumpster by number,
  else by the customer or location it is out at.
- Exactly one match shows a one-tap confirmation (Update Job, Dumpster
  Pickup, Dumpster Drop-off). Several matches ask "Which job?" or "Which
  dumpster?". A spoken name that matches nobody never silently lands on
  someone else's job: it asks, or offers "Start a new job instead".
- "Paid on site" means the job is done. The same wording is in the demo's
  and the app's instructions to Claude so both behave alike.

## Calendar replaces Today; jobs go to Google Calendar through the device (2026-10-19)

- Kyle: "app need to have a fully functional calendar tab - and it needs to
  integrate with google cal on mac and iphone". Offered three places for it
  (replace Today, a switch inside Jobs, a sixth tab that pushes two tabs
  under More), Kyle chose **Calendar replaces Today**. It keeps everything
  Today showed, under a month view.
- Google Calendar is reached through Apple's EventKit: the Google account is
  added once in each device's Settings and Ace writes jobs to a calendar
  named "Ace Jobs" picked in Ace's Settings. No Google developer setup, no
  sign-in inside Ace. Research and sources: `calendar.md`. Writing from the
  Cloudflare server instead is the later upgrade.
- Ace is the master copy: changes made in Google Calendar do not flow back.
- A job with a start but no end time goes to Google as an event with no
  length, following Kyle's "no defaults"; to be checked on a real device.
- Spec: `calendar-tab.md`.

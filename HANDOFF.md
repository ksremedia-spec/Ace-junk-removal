# Handoff: start here

Last updated 2026-10-19, about 20:45 UTC (4:45 PM Eastern), by the cloud
session that wrote everything so far. Kyle is moving to a Local session in
the Claude desktop app on his Mac (Code tab, computer use on). The chat
history does not come along, so this file is the handoff. Keep it current:
update it whenever something is built, tested, decided or asked.

Labels used below: **Verified** (checked, with how), **Assumed** (believed,
not checked), **Unknown** (with how to find out).

---

## 1. What this is

- A native iPhone and Mac app for **Ace Junk Removal**, a small junk removal
  and dumpster rental company in Massachusetts. Users: **Ashley** (office,
  phones and paperwork; iPhone and MacBook) and **Alex** (owner; drops off
  and picks up dumpsters; iPhone).
- **Kyle** builds it with Claude. He is a photographer, not a programmer:
  explain in plain English, do the technical steps yourself, ask one
  question at a time.
- One SwiftUI project for iPhone and Mac. Records are stored on the device
  (works offline). Shared sync through Cloudflare comes later (not built).
- The **Assistant**: speak a note ("Mrs. Johnson, 42 Elm, garage cleanout
  Friday at 9, $300 cash"), the phone turns speech into text on the device
  (WhisperKit), Claude fills in the form, Ashley checks it and taps Save.
- Deadline: version 1 on Ashley's and Alex's phones by about **October 31,
  2026**.
- Repository: https://github.com/ksremedia-spec/Ace-junk-removal (public),
  branch `main`. It is separate from Kyle's construction app (`resio-clone`):
  never touch that one from here.
- The rules (design, copy, how to work with Kyle) are in `CLAUDE.md`.

## 2. Where things stand

- **Oct 21, late night: sync between devices (build step 5), first
  version, running on Kyle's Mac.** Not committed. Server in
  `cloudflare/ace-sync` (Worker + D1; `npm run dev`, with Node.js 24.21.0
  in `~/.ace-tools/` and Wrangler 4.148.0, both downloaded with Kyle's
  OK). App side in `Ace/Sync/` plus a Sync section in Settings (server
  address, sync code in the Keychain). Every record now has a permanent
  ID (`syncID`; jobs keep `jobID`). Design and test results:
  `docs/device-sync.md`. Verified with two iPhone Simulators: 1,716
  example records copied across exactly, an edit and a deletion followed
  within 40 seconds, the later of two changes won both ways. Then the Mac
  app (erased with Kyle's OK): it received everything, a click on Mark
  paid reached the phone, and a phone edit showed on the Mac's open page
  in about 22 seconds. Not yet: tapping on the iPhone, a real iPhone
  (needs a local-network setting), Cloudflare's real servers.

- **Oct 21, night: plan for keeping Ashley's Google Sheet and Ace in step**
  (Kyle promised them both stay in step while she keeps using the sheet).
  Researched with two agents from Google's and Cloudflare's docs; plan in
  `docs/google-sheet-sync.md`. Nothing built. Plan: Ashley connects the
  sheet once with "Sign in with Google" and picks it (chosen by Kyle; the
  robot-account route was the first recommendation and is the fallback),
  the Cloudflare server checks every minute, hidden row tags to tie rows
  to jobs, read-only first, then writing on a copy, then the real sheet.
  Needs device sync (step 5) first; realistically after Oct 31. Six
  decisions for Kyle are listed in that file; the first is answered
  (a regular @gmail.com account), and so is the second (the Google
  setup belongs to the business's
  Google account; setting it up needs that account signed in once),
  and the third (when both sides change a job, the latest change wins),
  and the fourth (deletions copy across automatically, kept 30 days on
  the server).
  Kyle asked for a route without the robot: "Sign in with Google" and
  pick the one sheet (scope `drive.file`) was researched the same night
  and should avoid Google's "unverified app" warning; the catch is that
  the business name shows on Google's screen only with a website the
  business owns. **Kyle chose the sign-in route.** Still open: does the
  business have a website address, and the red/one-sheet-a-year questions.
  The Google Sheets menu path in the welcome guide was checked in a live
  sheet: File › Download › Microsoft Excel (.xlsx).

- **Oct 21, evening: Excel import and the Mac welcome guide.** Built for
  iPhone and Mac; run on Kyle's Mac with fake sheets only. Not committed.
  - File › Import Customers from Excel… (⇧⌘I), Mac only. Reads .xlsx (and
    .csv) in Ashley's layout (`docs/ashley-spreadsheet.md`), shows a
    preview first (customers, jobs, red-price unpaid total, rows with no
    house number or address, first six rows), then imports. Customers are
    matched by name and address; jobs come in as Junk removal, no time,
    past ones marked done, nothing written to the calendar. Importing the
    same file twice adds nothing; two identical rows inside one sheet both
    come in. Code: `Ace/Import/`.
  - Still assumed: red price = not paid. Phones, job types and times are
    not in her sheet. The "Contracted Labor" tab is not imported.
  - Welcome guide (`Ace/Mac/WelcomeView.swift`): opens once on the first
    launch, Help › Getting Started opens it again. Steps: import the
    sheet (with how to download it from Google Sheets), set up the
    dumpsters, add the crew, Assistant (checked when a key or the beta
    relay is there), plus the shortcuts. The example-data notes in the
    guide and the import appear only when the beta loaded examples.
  - Test sheets: `test-data/make_ashley_layout_sheet.py` (573 rows, or
    `... 600` for exactly 600 jobs and 480 customers). Debug-only launch
    switches: `-debug.empty` (start with nothing; the beta otherwise loads
    examples into an empty app) and `-debug.import <file in the app's tmp>`
    (open the preview without the Open panel, which Claude cannot click).

- **Oct 21: the Mac beta went out; the rest of the audit fixes; the real
  spreadsheet.**
  - Beta: "Ace Beta.dmg" (signed and notarized by Apple, drag-to-Applications
    window) sent to one tester through a Google Drive link (Gmail blocks app
    files). It opens on the sample data; the Assistant goes through Kyle's
    Cloudflare relay `ace-beta-relay` (docs/beta-relay.md). The relay
    address lives in `Ace/Support/BetaRelay.txt`, kept off the public repo.
    Before the real build: `Beta.isBeta = false`, delete that file, and
    delete the Worker in Cloudflare when testing ends.
  - Audit fixes finished today: a phone call ends a voice note cleanly; the
    Assistant's drop-off and swap screens no longer pre-pick a dumpster or
    customer they are unsure of, and say why; its pickup asks before saving
    with no weight; price and weight boxes there are labelled; spoken names
    match whole words; the job page's phone and address are tappable.
    Built for iPhone and Mac; checked in the Simulator. The phone-call
    handling needs a real iPhone to confirm.
  - Ashley's real sheet: a Google Sheet, layout in
    `docs/ashley-spreadsheet.md` (no customer data copied). It has no phone
    numbers, and uses Venmo and Cash App, which Ace has no payment type for
    yet: a decision for Kyle.

- **Oct 20, late night: iPhone audit and its safe fixes.** The full audit
  (638 agents, 191 confirmed findings, score 6 of 10) is in
  `docs/review-2026-10-20-iphone/audit.md`, with the screenshots it used.
  About 25 of the 29 "fix now" items are done; what changed is listed in
  `docs/decisions.md`. Built for iPhone and Mac; checked in the iOS Simulator
  (big iPhone and the small 17e, light, dark, largest text). Not run on a
  real iPhone. Not done from the list: a Mark-paid-asks-how-paid flow and
  other items that need Kyle (the audit's "Needs Kyle's decision" list), the
  audio interruption handling (a phone call mid-note needs a real iPhone to
  test), and the Assistant dumpster screens' preselect changes. Not committed.

- **Oct 20, late night: everything from today is on the iPhone.** Kyle:
  "pour all the changes we've made today over to the iOS app".
  `docs/decisions.md` has the why; specs in `docs/calendar-tab.md` and
  `docs/labor.md` ("iPhone").
  - Tabs are now Calendar, Jobs, Customers, Dumpsters, Labor. Quotes opens
    from the Calendar.
  - Calendar: figures, week strip or month, the day's job cards (long press
    for Mark done / Mark paid), the six dumpster tiles, Not marked done,
    Quotes waiting. Dumpsters: the tiles, two to a row.
  - Labor: day by day, hours boxes and salaried checks, week totals, Add
    person, a person's page with Retire and Delete.
  - Assistant: hold to talk, the on-screen Missing questions, the Hours
    screen, Return sends a typed note.
  - **Run in the iOS Simulator only** (iPhone 17 Pro Max and the small
    iPhone 17e, light and dark, normal and the largest text). Not run on a
    real iPhone. The Assistant was fed saved Claude answers (`-debug.plan`)
    because the simulator has no API key, and the microphone was not used.
    The Mac app was rebuilt and opened after the shared changes.
  - Not committed.

- **Oct 20, evening: Mac Calendar and Dumpsters redesigned.** Kyle: "the
  app looks kind of blah". Three sketches shown in the chat; Kyle picked
  bright cards plus the week board, keeping the teal (not Ace's website
  red). Spec: `docs/calendar-tab.md`, "Mac"; `docs/decisions.md`.
  - Calendar is one wide page (`Ace/Mac/MacBoard.swift`, which replaces
    `MacCalendarList`): four figures, the week as seven columns of job
    cards (or the full month beside the chosen day), the six dumpsters as
    tiles, then Not marked done and Quotes waiting. Clicking a card opens
    it in an inspector on the right. Dumpsters is the same idea
    (`MacDumpsterBoard`).
  - **Seen on the Mac, dark and light:** the week, Month, the tiles,
    opening a job in the inspector, the Dumpsters page. Light mode was
    checked with a new test switch, `-debug.light` (and `-debug.dark`),
    so the Mac's own setting was not touched.
  - Not yet redesigned: the job, quote and customer pages (still the
    settings-style form) and the Jobs, Quotes and Customers lists.
  - Built for Mac, compiled for iPhone (the iPhone Calendar is unchanged).
    Not committed.
- **Oct 20, night: Assistant switched to Haiku; full-resolution screenshots.**
  Sonnet dropped people and fields on most test notes, Haiku on none; Kyle
  agreed to switch (`docs/decisions.md`). Debug builds now also save each
  raw reply to `tmp/assistant-response-*.json` in the app's container.
  Ten full-resolution screenshots of the running Mac app are in
  `screenshots/2026-10-20/` (not committed). How they were made: the
  window filled to the screen, each screen captured as nine zoomed pieces
  through computer use and stitched (a small Swift script in the session
  scratchpad); the plain screenshot tool returns only 1453 pixels wide,
  and macOS's own `screencapture` needs Screen Recording permission, which
  was not given.

- **Oct 20, night: Labor (Alex's request).** Spec `docs/labor.md`;
  decision in `docs/decisions.md`. Data `Ace/Data/Labor.swift` (Worker,
  LaborEntry); Mac page `Ace/Mac/MacLaborBoard.swift`; person screens
  `Ace/Labor/WorkerViews.swift`; Assistant `AssistantLaborView.swift` and
  the `log_hours` action.
  - **Seen on the Mac:** adding five filler people (two salary, three
    hourly) through Add person; typing hours (8, 7:30, 9.5) with correct
    totals and pay; marking a salaried day off; the Assistant logging four
    people from one typed note, adding Kevin as new, and answering "how
    many hours has Joey worked this week and what do I owe him".
  - Filler crew in Kyle's Mac copy: Mark Sullivan and Dave Brennan
    (salary), Chris Pacheco $20, Joey Medeiros $22, Tyler Gomes $18, and
    Kevin (added by the Assistant test). Made up; Alex replaces them.
  - Assumed, to confirm with Alex: hours rather than start and end times;
    salaried work week Monday to Saturday.
  - Not built: the iPhone screen (where it goes in the tab bar is open),
    sync between devices, a screen for the salaried work week.
  - The demo now says "Crew hours are kept in the app" for a log_hours
    action. The demo's own checks were not run: Node.js is not installed
    on this Mac.
  - Built for Mac, compiled for iPhone. Not committed.

- **Oct 20, afternoon: missing details as on-screen questions; hold to
  talk.** Kyle: click a missing item and type it, and have the Assistant
  ask for what was missed. A first version asked out loud; Kyle tried it
  and said no ("I don't want it to talk back, maybe it asks questions back
  on screen ... maybe a hold to talk"). Spec: `docs/assistant-actions.md`,
  "Follow-up questions" and "Same customer or new"; `docs/decisions.md`.
  - New-job and new-quote forms: a Missing section at the top. The first
    missing item is a question on screen with Hold to answer, Type it and
    Skip; every missing item is also a button that puts the cursor in its
    field; a missing house number gets its own field above the address.
    **Seen working on the Mac:** the question, Skip, Type it (typed a phone,
    the question moved on to price), and a tapped Hold to answer that heard
    room speech, sent it to Haiku and correctly filled nothing.
  - The Assistant's Record/Stop is now one Hold to talk button: hold and
    let go, or tap once for hands-free and tap again. **Seen on the Mac**
    through tapping (it heard real speech in the room and answered it).
    **Not seen:** an actual press-and-hold with the mouse, and a spoken
    answer filling a field (the Mac's volume was 6 of 100, so its own test
    voice could not be heard). Needs Kyle to try once.
  - Fixed on the way: WhisperKit's live transcriber kept the last
    recording's words and its place in the audio, so a second recording
    showed old words and went quiet. Now a fresh one per recording.
  - Customer matching (Kyle): name and phone must both match, otherwise a
    new customer; any address said must match too. Shared by both forms
    (`existingCustomer`). Built; not re-checked on screen.
  - **Seen twice on Oct 20: the Sonnet setting dropped fields** on the same
    typed note ("Dana Whitcomb, Locust Street in Taunton, garage cleanout
    tomorrow at 9"): once the date, once the name and address. The Missing
    section caught both, but Haiku did not do this in earlier tests.
    Recommendation to Kyle: switch Settings › Claude model to Haiku.
  - Built for Mac and compiled for iPhone (not run on a phone). Not
    committed.

- **Oct 20, early morning: full audit of the Mac app and the fixes from it.**
  Kyle: judge the app start to finish; Mac only ("don't worry about any
  iPhone screens let's get the Mac app right first"). 12 reviewers read the
  code and 23 Mac screenshots (`docs/review-2026-10-19/`, not committed);
  262 findings (`scratchpad`, summarised here). The verify and judge stages
  hit Kyle's plan limit, so findings were checked by hand as they were fixed.
  Nothing committed. Fixed and seen on the Mac unless marked:
  - Money: Unpaid list/count now use the same rule as Owed (done, priced,
    not paid); done jobs with no price and past jobs not marked done no longer
    count. Billed and Last on a customer count only done/past work, plus
    "Next" for booked work. Prices read the first number only ("300-350" was
    $300,350). Dates show the year when it is not this year. (Built; the
    Unpaid list itself not re-counted on screen.)
  - Safety: right-click Delete Job / Delete Quote and Mark Lost ask first;
    lost quotes show under "Lost" when a search matches them. Job and quote
    pages keep unsaved edits when another row is clicked (saved on leaving,
    like Mail/Notes), Save is greyed out until something changes, ⌘S saves.
  - Calendar: month pinned above the list (never scrolls away, reopens in
    view), Today in the month header (greyed when on today), ⌘T follows,
    tighter day cells, today moves on at midnight, VoiceOver says "today".
  - Look: one colour per meaning (green good, orange owed, red overdue,
    grey done; blue/indigo only job and dumpster types), deeper light-mode
    status colours for contrast, quiet grey initials circles, smaller
    badges, readable address lines, Unpaid rows show how many days owed
    instead of repeating "Done · Unpaid", Booked quotes without the pill,
    header Done/Paid buttons neutral until on, overlap alert "Save anyway" /
    "Change the time", hints in empty fields, Notes boxes match the form,
    dumpster Choose… is a real button, Settings rate row reads
    "Overweight charge, $ per ton".
  - Toolbar: + is a menu (job, quote, customer), a Settings gear, tooltips;
    search clears when the section changes. App icon: Ace's own spade
    emblem, white on near-black (Kyle: "pull the ace junk removal logo
    online - clean it up and add"). Source: the header logo on
    acejunkremovalma.com (`AceJunkRemoval_horizontal-logo_white.png`,
    4484 × 1416), emblem cut out without the words; both kept in
    `docs/brand/`. Their round logo was only 274 × 238 with tiny text, too
    small for an icon.
  - Assistant (tested with Kyle's key, Sonnet, typed and spoken notes):
    - Sends the whole customer directory (cached block) instead of at most
      six named customers; jobs two weeks back to two months ahead; years
      on dates. "who lives at 63 Locust St in Taunton" now answers (First
      Parish Church of Raynham). Spec, app and demo prompt in step.
    - Root cause of "it doesn't understand": Sonnet 5.5 without an explicit
      thinking setting returned forms with every field empty (verified:
      byte-identical requests, Haiku filled them, Sonnet did not even at
      high effort). Now sends `thinking: {type: "adaptive"}`; verified Sonnet
      then fills them. Safety net: an empty action is re-asked once on Haiku.
    - "Estimate" renamed "Quote visit" (Kyle: "They refer to them as
      quotes"); old stored "Estimate" reads as Quote visit. "Schedule a
      quote … tomorrow at 3" books a Quote visit on that day (verified). No
      job-type question, no price question on quote visits, no "is this a
      new customer" question; same name + same address = same customer.
    - Type a note on the Mac; Send again keeps the note after an error; a
      missing key shows up front; Mac wording.
    - Save questions are "Save as is" / "Fix it" (Yes used to save without
      the thing asked about).
    - Live transcription with WhisperKit's streaming transcriber: words show
      while talking, then one full pass for accuracy. Verified with the Mac
      speaking a note: two actions found (Linda Johnson done/paid cash; new
      junk removal for Paul Silva tomorrow, $400). Whisper wrote "at ten" as
      "$10"; the prompt now says a time can come out as money.
    - Debug builds only: `tmp/assistant-last.txt` and
      `tmp/assistant-request-*.json` in the app container hold the last note,
      answer and request. Not in release builds.
  - Not done, for Kyle (see the proposals in the chat of Oct 20): week view
    in the empty Calendar detail; billing the overweight charge (it is
    calculated and then goes nowhere); Undo; selecting what the Assistant
    saved; Debug section and model/effort settings before handing over;
    keyboard Delete and Mark done shortcuts; duplicate-customer check.

- **The app is written and compiles, but has never run on a real iPhone or
  Mac.**
  - Verified: GitHub's build check compiles it for iPhone and Mac with
    Xcode 26 and Xcode 27.1 on every push, and it passes. The last run
    that compiled app code was #24 (commit `a0a9cb9`).
  - Older versions did run in the iPhone Simulator and as a Mac app on
    GitHub's Macs, to take the screenshots in `docs/screenshots/`. The last
    screenshot run was the morning of Oct 19. Quotes, end times and the
    Calendar tab came after it and have never been seen running anywhere.
- **Oct 19 evening, first build on Kyle's Mac: the Mac app builds and opens.**
  - Verified: Xcode 27.1 (27A9275, `~/Desktop/Xcode 2.app`, the Mac's
    default) on macOS 26.6.1, Apple silicon. WhisperKit resolved
    (argmax-oss-swift 1.1.1). `xcodebuild` for macOS: BUILD SUCCEEDED, no
    errors, one deprecation warning (`Text` + `Text` in
    `Speech/SpeechTestView.swift:175`).
  - Signed "to run locally" (ad hoc, command-line overrides only; the
    project file and Kyle's developer account were not changed). Built into
    the session's scratch folder, not the repo.
  - The window opened on Calendar in dark mode: sidebar Calendar, Jobs
    (Unpaid, Done), Quotes, Customers, Dumpsters; October 2026 with the
    19th marked; "0 jobs today", "No dumpsters", "No jobs today", New job,
    Tomorrow. No sample data loaded.
  - The Assistant sheet was open on first look, showing "Preparing the
    speech model". No launch option was passed, and the code only opens it
    from the toolbar button, ⇧⌘A or `-open assistant`. Unknown whether
    Kyle clicked it.
  - The API key can't be saved in this ad-hoc Mac build. The screen is
    there (Ace › Settings… › API key) and opens. Verified with a separate
    ad-hoc-signed probe using the same Keychain call: `SecItemAdd` with
    `kSecUseDataProtectionKeychain` returns -34018, "A required entitlement
    isn't present". Assumed the same in Ace (its own footer warns of it); not
    tried in Ace, because automation can't type into the password field.
    Signing with Kyle's team alone does NOT fix it (verified: `DEVELOPMENT_TEAM
    = 6YCK9MG5RD` set in the project, Mac build signed with team 6YCK9MG5RD,
    no provisioning profile embedded, and the probe signed with his Apple
    Development certificate still gets -34018). The data-protection keychain
    needs an application identifier from a provisioning profile. Options put
    to Kyle: add `keychain-access-groups` to `Ace/Ace-macOS.entitlements` so
    Xcode makes a Mac development profile (registers the Mac as a device), or
    drop `kSecUseDataProtectionKeychain` on macOS in `Support/Keychain.swift`.
    Kyle chose the first. Done: `keychain-access-groups` =
    `$(AppIdentifierPrefix)com.acejunkremoval.app` added to
    `Ace/Ace-macOS.entitlements`; built with `-allowProvisioningUpdates
    -allowProvisioningDeviceRegistration`. Verified: Xcode used its managed
    "Mac Team Provisioning Profile: *" (team wildcard, expires 2027-10-19),
    this Mac is in it, and the app carries application-identifier
    `6YCK9MG5RD.com.acejunkremoval.app` and that keychain group. Kyle then
    adds his key himself (Ace › Settings… › API key). Verified Oct 19: the
    screen then read "A key is stored on this device." with Remove key, so
    the Keychain save works in the team-signed Mac build.
  - Kyle, Oct 19: "lets just work on mac app 4 now". The iPhone waits.
  - Sample data loaded by Kyle. Verified on the Mac: the Assistant's full
    chain ran with his key. A note became a New Job form (John Smith, 9
    Radcliffe Lane, Junk removal, Oct 30, $600) with Claude's flags: new
    customer?, no phone, no town, no time. Whether he spoke or typed it:
    not yet asked.
  - Kyle's feedback on that form (not built yet, waiting on which first):
    1. "when i enter incomplete data it should be an esy click and type to
       fix." Found: every field is already a text field, but on the Mac an
       empty one shows nothing to click; the Save questions are Yes/No,
       and for Claude's own wording ("Do you have a phone number?") Yes
       saves without it while No just stops, pointing nowhere. Proposed:
       hints in empty fields, a question line that puts the cursor in its
       field, and "Fix it" / "Save without it" buttons.
    2. "or when i say incomplete stuff": no way to add a missing piece by
       voice from the form; only Start over. Proposed: a speak-to-fill
       button that updates only the fields said. Changes the Assistant
       contract (`docs/assistant-actions.md` first).
    3. "if i say a name thats not in the system - assume its new". The
       app already creates a new customer silently; the question came from
       Claude. Proposed: one line in the system prompt (spec first, then
       `AssistantPlan.swift`, then sync the demo) and a plain "New
       customer." line on the form. Trade-off: a misheard existing name
       makes a duplicate (a phone match still links correctly).
       Refined by Kyle: "check name for previous address also so if name
       and address match its the same customer - if it oesnt assume new".
       Today `JobReviewView.matchingCustomer` links on the note's
       reference, a phone match, or the exact name alone. New rule: name
       AND address (house number + street word, suffix and town ignored)
       → same customer; otherwise new. Answered Oct 20: a phone match
       alone does not link ("both the phone number and customer name need
       to match otherwise new customer"); see the Oct 20 entry above.
    4. "calander is too small on open to": on the Mac the month is the
       standard graphical `DatePicker`, about 140pt wide in a column twice
       that. Options put to Kyle: a full-size month grid in the middle
       column built from standard buttons, with job dots (bends the "no
       custom-drawn controls" rule and `calendar-tab.md`), or scale up the
       standard picker (keeps the rule; no dots; click accuracy unknown).
       Kyle chose the full-size month, then: "disregard standard control
       rules. make app look slick - i was only trying to avoid an 'AI'
       look." CLAUDE.md design rules, `decisions.md` and `calendar-tab.md`
       updated. Built: `Ace/Mac/MacMonthGrid.swift` (month and year, arrows,
       weekday row, six weeks, accent circle on the chosen day, accent
       number for today, hover highlight, dot under days with open jobs),
       used by `MacCalendarList`. Verified: the Mac build succeeds with no
       errors or warnings from it. Not yet seen on screen.
    5. "paid customrs are showing crossed out names": `JobRow` strikes
       through every done job's name (spec: "done ones crossed out"), so the
       Unpaid list (all done, not paid) reads like cancelled jobs.
    6. "app overall spacing looks not used correctly or frankly looks like
       shit". Audit from the Mac screens: detail pages are stock grouped
       Forms stretched edge to edge (label far left, value far right, empty
       middle), no header saying whose job or what it's worth; a black
       Notes box inside a grey panel; Done and Delete job each alone in a
       panel at the bottom, Delete not red; list rows cramped, tiny grey
       secondary lines, status as coloured words; the Calendar column's
       figures are plain text lines; Save sits in the shared toolbar.
       Proposed design pass (waiting on Kyle): roomier rows with status
       pills instead of strikethrough, detail pages with a header (name,
       type and date, big price, pills) and a centred column of limited
       width, matched field colours, actions grouped with Delete in red,
       figure tiles on Calendar, one spacing scale.
    7. "i just created a quote using the ai assistant and it dint update
       the quoptes tab". Verified in a read-only copy of the Mac store
       (`~/Library/Containers/com.acejunkremoval.app/.../default.store`):
       first reading said nothing was saved, but that query was wrong
       (compared a stored number with text). Corrected reading: at 6:07 PM
       the Assistant saved a new customer Tom Sousa (13 Main Street,
       Taunton, MA, no phone) and a JOB, type Estimate, today 7:00 PM, no
       price, note "Needs a quote today by 7 PM". Not a quote: by the
       prompt, new_quote is "a price was given" and an on-site quote visit
       is an Estimate job. So the save works; the open question for Kyle
       is what "needs a quote" with no price should become. Settled by
       Kyle: "yes so it handled correctly". No change.
    8. "lose the lost quotes tab" and "get rid of quotes follow up for now":
       done. `QuoteStatus.listed` = Open, Booked; `QuoteFeatures.followUps =
       false` hides follow-up rows, sections, the Calendar row and Call
       back, and stops new quotes getting a call-back day (`quotes.md`
       updated). Verified: Mac build and an iPhone Simulator compile both
       succeed, no errors or new warnings. Not yet seen on screen.
  - Seen on screen after a restart (Mac, dark mode, sample data):
    - The new month: "October 2026" with arrows, SUN…SAT, six weeks, today
      (19) a blue circle, dots under days with open jobs, hover circle.
      Choosing the 22nd (pressed through accessibility) worked: blue
      circle on 22, today's number in blue, a Today button above, that
      day's jobs and New job. An automated raw mouse click on a day scrolled
      the list instead; not yet known whether a real mouse click works.
      Small thing seen: the Today button appearing pushes the month down.
    - Quotes: only Open and Booked; no Follow up or Waiting sections; rows
      read "Quoted Tue, Oct 13" with no follow-up. Calendar's figures line
      no longer mentions quotes.
  - **Design pass (Oct 19 evening, Kyle away: "think, and drastically
    change the look and design of the app, work rebuild and test as
    needed").** Nothing committed; waiting for Kyle to look.
    - New: `Ace/Support/Design.swift` (spacing, colour meanings, TypeBadge,
      StatusPill, JobPills, StatTile/StatGrid, Avatar, action buttons,
      DetailHeader, EmptyDetail, readable width), `Calendar/TodayFigures.swift`,
      `Customers/CustomerRow.swift`. Accent colour asset set to a deep teal.
    - Job rows: type badge, time first then type, price and Done / Paid /
      Unpaid pills; no strikethrough (done jobs get a grey badge). Day-grouped
      lists no longer repeat the date. Rows on a customer's page lead with the
      job type.
    - Job page: header card (badge, name, type, day and time, address, big
      price, pills incl. Overlaps) with Mark done / Mark paid (save at once,
      like the right-click menu), Call, Directions; Notes box matches the
      form; Delete in red; the old Done toggle row is gone (the header button
      replaces it).
    - Calendar (iPhone and Mac): four tiles (Today, Owed, Dumpsters, Quotes)
      replace the figure lines and the Owed row.
    - Customers: initials circles in the list; page header with Call,
      Directions, New job and three tiles (Jobs, Billed with per-job average,
      Owed). Dumpsters: numbered badge in the status colour, status pill,
      "Back Sat, Oct 17", size on the second line; page header; Mark picked
      up / dropped off as prominent buttons. Quotes: type badge, details,
      price; page header with Book job and Mark lost (or Reopen).
    - Mac: sidebar counts (Unpaid, open Quotes, Dumpsters due or overdue),
      empty detail pages with a symbol and help line, detail pages at most
      720 points wide, list column a little wider, pills and coloured text
      turn white on a selected row.
    - Verified: Mac build and an iPhone Simulator build succeed with no
      errors and no new warnings; `check-contract.py` still identical. Seen on
      screen on the Mac (dark, and light via `-NSRequiresAquaSystemAppearance
      YES`): Calendar, Jobs, a job page, Mark done and back (Unpaid count
      31 → 32 → 31), Customers and a customer page, Dumpsters and a dumpster
      page, Quotes and a quote page. Seen in the iPhone 17 Pro Max simulator
      (iOS 26.5, light): every tab and the New Job form. Not seen: the
      iPhone job, customer, dumpster and quote pages (the simulator tool
      needs Kyle's permission to tap), iPhone dark mode, the largest text
      sizes, the Assistant screens (not restyled).
    - Pictures: `docs/design-pass/mac-2026-10-19.png` (job page dark,
      Calendar light, Dumpsters light, quote page dark) and
      `docs/design-pass/iphone-2026-10-19.png` (the five tabs, light).
    - The simulator got its own sample data (`-sampledata`); the Mac's data
      is the sample data Kyle loaded, unchanged by the checks.
  - Also verified on the Mac with sample data: the overlap note ("Overlaps
    Linda Johnson, Junk removal, 9:00 AM to 12:00 PM." on Mark Pereira's
    11:00 job), and Today's figures line, Owed, Dumpsters (Overdue, Due
    today) and today's jobs.
  - Not done yet: the iPhone. It needs the signing team set (Kyle's paid
    team "Kyle Silva", 6YCK9MG5RD, is signed in to Xcode; `DEVELOPMENT_TEAM`
    is empty in the project) and the bundle ID `com.acejunkremoval.app`
    registered on his account, which changes his developer account.
- **The clickable browser demo is up to date** (version 21, with the
  Calendar tab). It is what the client has been shown. Verified: 203
  automatic checks pass in a test browser (not on a phone).

## 3. What the app has today

- **iPhone tabs:** Calendar, Jobs, Quotes, Customers, Dumpsters. Every tab
  has the Assistant button (top right); Settings is the gear on Calendar.
  - **Calendar** (replaced Today on Oct 19): a month with a dot under days
    that have jobs. Today shows the day's figures, money owed, dumpsters due
    back or overdue, today's jobs, jobs not marked done, quotes to call
    back, other calendars' events, and tomorrow. Tap another day to see
    that day. A Today button goes back.
  - **Jobs:** Upcoming, Unpaid, Done; add and edit by hand; optional end
    time; a warning when two jobs overlap; swipe to mark done or delete.
  - **Quotes:** prices given that are waiting on a yes; Follow up, Waiting,
    Booked, Lost; Book Job turns a quote into a job.
  - **Customers:** search by name, phone or address; history; Call and
    Directions.
  - **Dumpsters:** six dumpsters; drop-off; due back and overdue; weight at
    pickup with the overweight charge (rate in Settings).
- **Mac:** sidebar, list, detail, like Mail. ⌘N new job, ⇧⌘N new customer,
  ⌥⌘N new window, ⌘F search, ⇧⌘A Assistant, ⌘T go to today, right-click
  menus, Settings with ⌘,. File › Import from Excel is a disabled
  placeholder.
- **Settings:** API key (typed once per device, kept in the Keychain, never
  in the code), Claude model (Haiku; Sonnet for testing), speech model,
  overweight rate, Calendar (access, which calendar jobs go into, which
  other calendars show), Debug (Speech test, Claude test, Load sample data,
  Clear all data).
- **Google Calendar:** once a calendar is picked in Settings › Calendar,
  every job saved in Ace is also written to it (for example a Google
  calendar "Ace Jobs" added through the device's Settings). Ace is the
  master copy: changes made in Google don't come back into Ace.

## 4. What changed recently and why (all on Oct 19)

| Change | Why | Spec |
|---|---|---|
| Quotes tab, plus "Quotes to follow up" on the first screen | Ashley wanted outstanding quotes kept straight | `docs/quotes.md` |
| The Assistant creates and updates quotes ("quote for 66 Johnson St, $800, customer approved") | Kyle asked | `docs/assistant-actions.md` |
| End times on jobs, and a warning when jobs overlap | Kyle asked how overlaps are kept apart; chose "warn on any overlap", then "no defaults, end time will be selected or spoken" | `docs/job-length.md` |
| Calendar tab replaces Today; jobs written to Google Calendar | Kyle: "fully functional calendar tab ... integrate with google cal on mac and iphone"; chose "Calendar replaces Today" | `docs/calendar-tab.md`, research in `docs/calendar.md` |
| Changing or deleting a customer updates their jobs' calendar events | Closing a gap in the calendar work | `docs/calendar-tab.md` |
| Screenshots of typing a job in by hand (`docs/screenshots/9-new-job.png`, `mac-6-new-job.png`) | Ashley asked whether she can type instead of speaking in public: yes | |
| Demo pages and their checks saved in `demo/` | They had lived only on the cloud machine | `demo/README.md` |

Older decisions, with reasons, are in `docs/decisions.md`. A longer history
is in `docs/status.md`.

## 5. Verified, assumed, unknown

**Verified**
- The app compiles for iPhone and Mac (GitHub build check, see section 2).
- The Assistant's instructions to Claude in the app match the spec in
  `docs/assistant-actions.md` word for word (`demo/checks/check-contract.py`).
- The demo passes its 203 automatic checks in a test browser.
- Research facts listed with their sources: `docs/platform-facts.md`,
  `docs/calendar.md`, `docs/whisperkit-api.md`.
- Kyle's setup (he confirmed on Oct 18): iPhone 16 Pro Max on iOS 27.1,
  Xcode 27.1, paid Apple Developer Program. Install straight from Xcode,
  not the App Store or TestFlight.

**Assumed (not checked)**
- That the app runs at all on a real device. It has only been compiled.
- One business Google account on every device (Kyle: "im assuming yes but
  TBD").
- Events Ace writes reach calendar.google.com within minutes, and are kept
  and sent later when there is no signal.
- Google keeps an event with no length (a job with a start time but no end
  time is written that way, following Kyle's "no defaults").
- The dots under calendar days update as soon as a job changes.
- Phones that already have an older Ace build keep their records when
  updated. This only matters if Kyle installed an earlier build.
- ⌘T doesn't clash with another Mac menu item.

**Unknown, and how to find out**
- How fast and accurate speech-to-text is on the iPhone 16 Pro Max: Settings
  › Debug › Speech test.
- Haiku versus Sonnet on real recordings: Settings › Debug › Claude test.
- The exact menu path for adding a Google account on iOS 27.1: follow
  `docs/calendar.md` section 5 on Kyle's phone.
- The six Google Calendar device tests at the end of `docs/calendar.md`.
- Whether a demo viewer who isn't signed in to claude.ai can reach Claude:
  the "Connection" row in the demo's Settings.

## 6. Never built, or never seen running

- **Never run on a real iPhone or Mac:** all of it.
- **Never seen running anywhere (only compiled):** the Quotes tab, the
  Assistant's quote actions, end times and overlap warnings, the Calendar
  tab, Settings › Calendar, writing jobs to Google Calendar.
- **Not written yet:**
  - The Apple SpeechTranscriber half of the step 1 speech comparison. The
    Speech test has WhisperKit only; Apple's engine is a placeholder row.
  - Apple Maps address completion in the Assistant.
  - Step 5, Cloudflare sync between devices. Until then each device has its
    own records.
  - Step 7, Excel import on the Mac (waiting on Ashley's column headings).
  - Step 8, the Lock Screen, Control Center and Action button shortcut.
  - Step 9, the check of every screen at the smallest and largest text
    sizes, light and dark.
  - On the Mac, the record the Assistant just saved isn't selected
    afterwards.
- **Demo pages behind the app:** the client Preview page and the phone
  slideshow still show the old Today tab, with no Quotes, end times or
  Calendar. The clickable demo is current.
- **Demo relay** (`docs/demo-relay/`): lets someone without a claude.ai
  login use the demo's Assistant. It waits on Kyle setting up a Cloudflare
  Worker.

## 7. Open questions waiting on Kyle (ask one at a time)

1. Is there one business Google account (Gmail or Google Workspace), and do
   Ashley and Alex already have it on their phones and Ashley's Mac?
   Currently assumed yes.
2. Ashley's spreadsheet column headings, for the Excel import. (A guessed
   test sheet is in `test-data/` for now; rebuild it to match once known.)
3. The Cloudflare account details, for sync and the demo relay. Free or
   paid Workers plan?
4. Ashley's and Alex's iPhone models (does either have an Action button?),
   and Ashley's Mac model and macOS version.
5. Should the client Preview page and phone slideshow be brought up to date
   (Quotes, end times, Calendar)?
6. Delete the stray duplicate Preview page
   (https://claude.ai/artifact/KSMW87Xj4mE3o7LZtNkDxD)? Only on Kyle's word.
7. Keep or remove, before handing the app to Ashley and Alex: the Effort
   picker, the Debug section (Load sample data, Clear all data), the GitHub
   build and screenshot checks.
8. Leave the downloaded speech models (up to 630 MB) out of iCloud backup?

## 8. Next steps, in order

1. **Get it running on Kyle's Mac and iPhone.** Open `Ace.xcodeproj`, let
   Xcode fetch WhisperKit, set the signing team (Kyle's paid account),
   build, install on his iPhone, and run the Mac app. Fix whatever fails.
   `docs/run-on-your-mac.md` has the steps written for Kyle; on his Mac a
   Claude session can do most of them itself.
2. **Walk Kyle through the checklist below,** one item at a time. Note what
   works and what doesn't in this file.
3. **Step 1 speech test:** Kyle's recordings (fast speech, truck and TV
   noise, odd names, missing house numbers, double bookings) through the
   Speech test and Claude test. Add Apple's SpeechTranscriber to the
   comparison. Pick the engine and the model.
4. **Google Calendar on Kyle's devices:** the setup in `docs/calendar.md`
   section 5, then its six device tests. Use a test calendar first, not
   the business one.
5. **The remaining build order:** step 5 Cloudflare sync, step 7 Excel
   import, step 8 one-tap entry, step 9 text sizes and dark mode, Apple
   Maps address completion.
6. **The client pages,** if Kyle wants them updated.
7. **Install on Ashley's and Alex's phones and Ashley's Mac** before
   October 31.

## 9. Checklist: what to look at first (with Kyle, one at a time)

1. The project opens in Xcode, and WhisperKit downloads ("Resolving
   packages" at the bottom finishes).
2. It builds for the iPhone with Kyle's team, installs, and opens. The phone
   may need Developer Mode on, and the developer trusted, the first time.
3. It opens on the **Calendar** tab. Load the example records: gear ›
   Settings › Debug › Load sample data.
4. **Calendar:** dots under days, tap another day, the Today button, New
   job on another day.
5. **Jobs:** add a job by hand with an end time. Today's example records
   clash on purpose (Linda Johnson 9:00 to 12:00 and Mark Pereira at
   11:00): the overlap warning should show.
6. **Quotes:** follow up, Book Job, Mark Lost.
7. **Customers:** search, open one, Call and Directions.
8. **Dumpsters:** drop one off; pick one up with a weight over the agreed
   amount and check the overweight charge.
9. **API key:** Settings › API key, paste Kyle's key once.
10. **Assistant:** tap Assistant, say a new job, check the filled-in form
    and the one-at-a-time questions. Then say an update ("the Johnson job is
    done, paid cash").
11. **Debug screens:** Speech test (load `base.en`, record, transcribe) and
    Claude test (Haiku and Sonnet side by side).
12. **Settings › Calendar:** Allow Calendar Access, pick a test calendar,
    save a job, look for it in Apple's Calendar app.
13. **The Mac app:** the same screens in the sidebar, ⌘N, ⌘F, ⌘T,
    right-click on a job.
14. **A glance in dark mode and at the largest text size.**

## 10. Where things are

- `CLAUDE.md`: the rules. `HANDOFF.md`: this file.
- `Ace.xcodeproj` and `Ace/`: the app. New Swift files under `Ace/` join the
  app automatically.
- `docs/`:
  - `status.md`: detailed history.
  - `decisions.md`: decisions and their reasons.
  - Feature specs: `assistant-actions.md`, `quotes.md`, `job-length.md`,
    `calendar-tab.md`.
  - Research: `calendar.md`, `platform-facts.md`, `whisperkit-api.md`.
  - `run-on-your-mac.md`: Kyle's guide to building and running the app.
  - `screenshots/`: Simulator pictures, morning of Oct 19.
  - `demo-relay/`: the Cloudflare Worker for the demo.
- `test-data/`: a fake stand-in for Ashley's spreadsheet, for trying the
  Excel import (step 7) without her real file. Made-up customers only; the
  layout is a guess until her headings are known (Kyle, Oct 19: "reasonable
  test for now"). `README.md` there lists the mess it holds and an answer
  key; `make_test_sheet.py` rebuilds it.
- `demo/`: the demo pages and their automatic checks. See `demo/README.md`.
  - Clickable demo (shared with the client):
    https://claude.ai/artifact/Mv1yKwDUgPyxR2jaj8qQ3j
  - Client Preview page: https://claude.ai/artifact/8wvbCffQ4deC7uh8ThqXsC
  - Phone slideshow: https://claude.ai/artifact/MikLi52xrfdmSewj4KyLHb
  - Slide deck: https://claude.ai/artifact/J8UKoRfm4Zg8qpaw8t1GLR
- `.github/workflows/`:
  - `build.yml`: compiles on every push.
  - `screenshots.yml`: started by hand; uses about 50 minutes of Kyle's
    monthly GitHub Mac allowance.

## 11. Notes for the next Claude session

- **Work in Kyle's place, and tell him what you did:**
  - Kyle works in the Claude desktop app (Code tab, Local session, computer
    use on), not in Terminal. Run commands and click through Xcode
    yourself; don't hand him Terminal steps.
  - He needs to do anything that involves his phone in his hand (plugging
    it in, Developer Mode, trusting the developer, speaking a test).
- **Building:** this Mac can build, unlike the cloud session.
  - Build before saying anything works.
  - Say "tested" or "working" only after it ran on a real device.
  - Say "Simulator" when that is all it was.
- **Changing what the Assistant tells Claude:** change the spec first
  (`docs/assistant-actions.md`), then the app
  (`Ace/Assistant/AssistantPlan.swift`), then run
  `demo/checks/sync-assistant-prompt.py` for the demo and
  `demo/checks/check-contract.py` to confirm the app matches.
- **Publishing the demo pages:** this needs the Artifact tool. If the Local
  session doesn't have it, say so instead of working around it.
- **Commits:** build on Kyle's Mac first (that is the check), then commit
  and push to `main`. Don't wait on GitHub's build check from a Mac session
  (Kyle, Oct 20: "Why are you build checking in GitHub? You have a Mac");
  it was the only check while the work was done in the cloud. Whether to
  keep the GitHub workflows at all is open question 7.

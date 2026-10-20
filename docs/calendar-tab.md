# Calendar tab, and jobs in Google Calendar

Asked for by Kyle, 2026-10-19: "app need to have a fully functional calendar
tab - and it needs to integrate with google cal on mac and iphone". Asked
where it should go, Kyle chose option 1: **Calendar replaces Today.** The
research behind the Google part is in `calendar.md`; this page is what gets
built.

## In plain English

- The first tab is now **Calendar**. It opens on today and shows everything
  the Today screen showed. Above that is a month. Days with jobs have a dot
  under them (iPhone). Tapping a day shows that day: its jobs, dumpsters
  going out or coming back, quotes to call back, and events from the other
  calendars on the device, such as Alex's own Google calendar.
- When a job is saved, Ace also puts it into one Google calendar, "Ace
  Jobs", through the Google account added in the device's Settings. Moving,
  editing or deleting the job in Ace changes or removes that event.
- **Ace is the master copy.** Moving or editing an Ace job's event in
  Google Calendar does not change the job in Ace; the next time the job is
  saved in Ace, the event is put back to match. (Kyle was told this and did
  not ask for the other direction.)
- Nothing to do with Google happens until someone allows calendar access
  and picks "Ace Jobs" in Ace's Settings. Until then the Calendar tab works
  with Ace's own records only.

## iPhone

Redesigned on Oct 20 to match the Mac boards (Kyle: "pour all the changes
we've made today over to the iOS app"). Source: `Ace/Calendar/CalendarView.swift`,
with the shared pieces in `Ace/Calendar/BoardCards.swift` and
`Ace/Calendar/WeekStrip.swift`.

- **Tab bar:** Calendar, Jobs, Customers, Dumpsters, Labor. Quotes is no
  longer a tab (Labor took the fifth place; a sixth tab hides behind
  "More"). Quotes opens from the Quotes figure or "All quotes" on the
  Calendar. A phone left on the old Quotes tab reopens on Calendar.
- **One scrolling page, top to bottom:**
  1. Four figures: Today, Owed, Dumpsters, Quotes (a tap opens Quotes).
  2. **Week / Month** switch (remembered). Week: the week as seven day
     buttons with a dot under days that have open jobs; arrows or a swipe
     move a week. Month: Apple's own month view.
  3. **The chosen day:** "Today" or "Thursday, October 22", the count and
     total, then the jobs as cards tinted by the kind of work, dumpster
     drop-offs and due-backs as small cards, other calendars' events, and
     New job. A long press on a job card gives Mark done and Mark paid.
  4. **Dumpsters:** the six as tiles in their status colour.
  5. **Not marked done** (when there are any) and **Quotes waiting** (the
     first five, then "All quotes").
- **Today button:** in the toolbar while another day is chosen.
- The day picked is not remembered: the app always opens on today.
- **Large text:** at the accessibility text sizes the figures go one to a
  row, the dumpster tiles one to a row (two from the xxLarge size), and the
  day buttons stop growing at xxLarge so seven still fit, as in Apple's
  Calendar.

## Mac

- **Sidebar:** Calendar replaces Today, first in the list (`calendar`
  symbol); Jobs changes to `list.bullet`.
- **One wide page** (changed 2026-10-20, Kyle: the app "looks kind of
  blah"; he picked the bright-cards and week-board sketches and kept the
  teal). No middle list and no empty "Nothing selected" pane: the Calendar
  is sidebar plus a board (`MacBoard`), on a soft grey page with white
  cards (dark grey in dark mode).
  - **Header:** "Today" over the date (or the chosen day over "Week of
    October 19"), a Week / Month switch (remembered), and in Week ‹ Today ›
    to move a week at a time.
  - **Figures:** the same four tiles as before (Today, Owed, Dumpsters,
    Quotes), in one row.
  - **Week:** seven columns in the month grid's order, each a white card:
    weekday and date at the top (today's date in a teal circle; the chosen
    day's column outlined in teal; clicking a date chooses that day), then
    the day's jobs as cards tinted by job type (time, customer, type and
    price; done jobs faded with a check; jobs with money owed show an
    orange dollar sign), dumpster drop-offs and due-backs, and other
    calendars' events. "Nothing booked" when empty; "New job" on hover adds
    a job on that day. Too narrow for seven days (the inspector open), the
    week scrolls sideways.
  - **Month:** the full-size month (`MacMonthGrid`, with its own arrows and
    Today) beside the chosen day's cards.
  - **Dumpsters:** the six as tiles in their status colour: the number,
    "3 days late" / "Due back today" / "Back Sat, Oct 24" / "In the yard",
    and who has it.
  - **Below:** "Not marked done" and "Quotes waiting" cards, when there are
    any.
  Right-click a job for the same menu as in Jobs.
- **Inspector:** clicking any card opens it in an inspector on the right
  (the job, dumpster, quote or other-calendar event page as before); the
  board stays in view. Closing the inspector clears the choice. An
  other-calendar event shows a simple read-only page: title, calendar,
  date and time, location and notes. To change it, use Apple's Calendar
  app.
- **Dumpsters** (sidebar) uses the same layout: the six as big tiles with
  where each one is, days out, price and agreed weight, and the chosen one
  in the inspector.
- **Menu:** View › **Go to Today** (⌘T), as in Apple's Calendar app.

## Settings: Calendar section (iPhone and Mac)

- **Calendar Access:** "Not set", "Full access" or "Off".
  - Not set: a button **Allow Calendar Access**, which shows Apple's
    question. This is the only place Ace asks; it never asks at launch.
  - Off: footer "Calendar access is off. Turn it on in Settings › Privacy
    & Security › Calendars." with an **Open Settings** button on iPhone.
- **Calendar for Jobs:** None (the starting choice), or any calendar on
  the device that can be written to, shown with its account ("Ace Jobs ·
  acejunk@gmail.com"). Choosing one turns on writing jobs.
- **Show Calendars:** a list of every calendar on the device with a switch
  each, all on to start. Switched-off calendars stay out of the Calendar
  tab. (The Calendar for Jobs is not in this list; its copies of jobs are
  handled as above.)
- Footer: "Jobs are added to the calendar for jobs when saved. Changes made
  in Google Calendar do not change jobs in Ace."
- **Load sample data** also sets Calendar for Jobs back to None, so example
  jobs never reach Google. **Clear all data** does not touch any calendar.

## What a job looks like in Google Calendar

- **Title:** "Linda Johnson · Junk removal" ("Junk removal" with no
  customer).
- **Location:** the customer's address.
- **Time:**
  - Start and end time: exactly that.
  - Start time only: an event that starts and ends at the start time. No
    length is made up (Kyle: "no defaults"). Not known whether Google keeps
    an event with no length or how it shows it; test 6 in `calendar.md`
    settles it on a real device, and Kyle decides if it needs changing.
  - No time ("Set a time" off): an all-day event on that day.
- **Notes:** the phone number; "$450 · Cash · Unpaid" (or "Paid", or "Done
  · Paid"); the job's notes; then, on the last line, "Ace job" and the
  job's permanent ID. That last line is how Ace recognises its own events
  on any device.
- No alerts.
- Done jobs keep their event. Deleted jobs lose it.

## When the event is written

- Whenever a job is saved on this device, from any screen (the form, the
  Assistant, Book Job, swipe actions, right-click), Ace writes or updates
  its event, if a Calendar for Jobs is chosen and access is on.
- When a job is deleted on this device, Ace deletes its event.
- When a customer's name, phone or address is saved on this device (the
  customer form or the Assistant), Ace rewrites the events of that
  customer's jobs it has written, from 60 days back onward.
- When a customer is deleted, their jobs stay without a customer, and Ace
  rewrites those jobs' events: the title becomes just the job type, with no
  address and no phone line.
- Ace only writes events for changes made on this device ("one writer per
  change", `calendar.md` section 3). When Ace's own sync is built (step 5),
  jobs that arrive through sync are not written again.
- **No duplicates:** before creating an event, Ace looks in the Calendar
  for Jobs for an event carrying the job's ID (60 days back to a year
  ahead) and updates that one instead. If it finds two, it keeps one and
  deletes the others.
- No signal: the device's calendar keeps the change and sends it to Google
  later. Assumed (`calendar.md` section 1); untested.
- If writing fails (access turned off, calendar removed), the job still
  saves. The Calendar for Jobs row in Settings shows "Not found" if the
  calendar has gone.

## The record

- **Job** gains a permanent ID, given when the job is created; jobs from
  before this change get one the first time they are written. Ace's own
  sync (step 5) needs it too.
- **Job** also remembers its event's identifier on this device, for a
  quick look-up, and when it was last written.
- Settings keeps the chosen calendar and the hidden calendars on each
  device (not synced).

## Project settings (none of this affects the GitHub build check)

- iPhone and Mac: the wording for Apple's calendar question,
  `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription`: "Ace shows your
  calendars next to your jobs and adds jobs to the calendar you choose."
- Mac: `com.apple.security.personal-information.calendars` in
  `Ace/Ace-macOS.entitlements`.
- No new code library. EventKit is part of the system.

## Not in this change

- Changes made in Google Calendar flowing back into Ace.
- A week or day grid with hour lines like Apple's Calendar app. It does not
  come ready-made, and CLAUDE.md rules out custom-drawn controls.
- The overlap check does not look at other calendars' events.
- Writing to Google from the Cloudflare server (the later upgrade in
  `calendar.md` section 4).

## For the builder

- iPhone month: `UICalendarView` with `UICalendarSelectionSingleDate`,
  wrapped in `UIViewRepresentable`, with `sizeThatFits` so it sits in a
  List row; dots through the delegate's `calendarView(_:decorationFor:)`
  returning `.default()`; call `reloadDecorations(forDateComponents:animated:)`
  when jobs change. Mac month: `MacMonthGrid` (`Ace/Mac/MacMonthGrid.swift`).
- Tapping an other-calendar event on iPhone: `EKEventViewController` from
  EventKitUI, wrapped for SwiftUI, `allowsEditing = true` (EventKitUI is
  not available in a native Mac app, hence the read-only page there).
- Access: `EKEventStore.authorizationStatus(for: .event)` and
  `requestFullAccessToEvents()`; call `reset()` after a grant. Listen for
  `.EKEventStoreChanged` and reload. One shared `EKEventStore`.
- Writing: keep it in one place that every save and delete path calls.
  Never write while `-sampledata` or `-screenshot` is in the launch
  arguments.
- Permanent ID: `var jobID: UUID? = nil`, set in `init` and filled in
  lazily for older jobs (a non-optional default would give every existing
  job the same value during migration). Event look-up field:
  `var calendarItemID: String? = nil`; last written:
  `var calendarWrittenAt: Date? = nil`.
- Screenshot workflow: `-open today` keeps working (it opens Calendar);
  `-open calendar` too. Keep the existing file names.

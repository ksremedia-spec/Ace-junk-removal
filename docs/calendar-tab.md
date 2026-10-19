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

- **Tab bar:** Calendar, Jobs, Quotes, Customers, Dumpsters. Calendar uses
  the `calendar` symbol; Jobs changes to `list.bullet`. A phone that was
  left on Today reopens on Calendar.
- **The month:** Apple's own iPhone month view (the one with dots under
  days), at the top of the screen. Swipe for other months. A dot under a
  day means it has at least one job that is not done. Today is marked the
  standard way.
- **Today button:** in the toolbar, next to the gear, only while another day
  is selected. Tapping it goes back to today and its month.
- **When today is selected**, under the month, in this order (the same as
  the old Today screen, plus two sections):
  1. The figures: "2 jobs today · $750", dumpsters due back or overdue,
     Quotes to follow up (tap for the Quotes tab).
  2. Owed.
  3. Dumpsters (due back today or overdue).
  4. **Today's jobs**, headed with the date ("Monday, October 19"),
     including done ones (crossed out, as in the Jobs list), then **New
     job**.
  5. Not marked done.
  6. **Call back**: open quotes whose follow-up day is today or earlier.
  7. **Other calendars**: today's events from the device's other calendars.
  8. Tomorrow.
- **When another day is selected**, under the month:
  1. **That day's jobs**, headed "Thursday, October 22": every job that
     day, in time order (jobs without a time first), done ones crossed out.
     "No jobs." when there are none. Then **New job**, which opens the New
     Job form on that day (time off).
  2. **Dumpsters**: "Dumpster 3 drop-off", "Dumpster 3 due back" or
     "Dumpster 3 picked up", with the customer and location. Tap for the
     dumpster. Drop-offs and due-backs come from dumpsters out now;
     drop-offs and pickups of finished rentals come from their history.
     Hidden when there are none.
  3. **Call back**: open quotes with a follow-up on that day. Hidden when
     none.
  4. **Other calendars**: that day's events, as in today's list. Hidden
     when none.
- **Other-calendar rows:** a small dot in the calendar's own colour, the
  title, and "9:00 to 10:00 AM · Alex" (time, then the calendar's name), or
  "All day · Alex". Tapping one opens Apple's standard event screen, where
  it can be read and edited like in Apple's Calendar app.
- Events in "Ace Jobs" that are copies of jobs on this device are not shown
  there (the job is already listed). An "Ace Jobs" event that matches no
  job on this device (for example, one saved on another device before
  Ace's own sync exists) shows under Other calendars like any other event.
- Jobs rows open the job, swipe actions and all, exactly as in the Jobs
  list.
- The day picked is not remembered: the app always opens on today.

## Mac

- **Sidebar:** Calendar replaces Today, first in the list (`calendar`
  symbol); Jobs changes to `list.bullet`.
- **Middle column:** Apple's month picker at the top (the standard one; it
  has no dots on the Mac), then the same sections as on iPhone for the
  chosen day. A **Today** button above the month while another day is
  chosen. Right-click a job for the same menu as in Jobs.
- **Detail column:** the selected job, dumpster or quote, as elsewhere. An
  other-calendar event shows a simple read-only page: title, calendar,
  date and time, location and notes. To change it, use Apple's Calendar
  app.
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
  when jobs change. Mac month: `DatePicker` with `.graphical`.
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

# Labor: the crew and their hours

Asked for by Alex through Kyle, 2026-10-20: "another tab titled labor where
he can keep track of how many hours each guy worked every day", built "into
the assistant as well, obviously". Mac first, then iPhone.

## In plain English

- **The crew:** one list of people. Each is paid **hourly** (with an
  optional rate, so the week's pay can be worked out) or **salary**. Alex
  has two on salary; the rest are hourly. Seasonal help is added the same
  way, and someone who leaves is **retired**, not deleted, so their hours
  stay on past weeks. Rates and personal details are Alex's to fill in;
  the app holds made-up names and wages until then (Kyle, Oct 20).
- **Hours:** one number per person per day ("8", "7.5", "7:30"). Start and
  end times were not asked for; Kyle did not answer the question, so plain
  hours were chosen as the quickest to type and to say.
- **Salaried crew** count as working every work day without anyone typing
  anything. A day is clicked to mark them off (sick, vacation), or, on a
  day outside the work week, to mark them in. The work week is Monday to
  Saturday: an assumption until Alex says otherwise (setting
  `settings.salaryDays`, no screen for it yet). Days before someone was
  added do not count.

## Mac

- **Sidebar:** Labor (`clock`), last. A wide page with the chosen person in
  an inspector on the right, like Calendar and Dumpsters.
- **Header:** "Labor", "This week, October 18 to October 24", **Add
  person**, and ‹ This week › to move a week at a time.
- **Figures:** hourly hours this week so far, hourly pay at their rates
  ("some rates not set" when a rate is missing), how many are working
  today, and the crew count (salary and hourly).
- **Timesheet:** one row per person still on the crew, salaried first, then
  by name; one column per day in the calendar's order; a Week column.
  - Hourly: a box per day. Typed hours are saved on Return, Tab or clicking
    away. The Week column shows the hours and, with a rate, the pay.
  - Salaried: a teal check on days worked, orange "Off" on a work day
    marked off, a dash on other days. Days still to come are faint.
    Clicking switches the day. The Week column shows days worked so far.
  - Bottom row: the hourly hours per day and for the week.
  - Too narrow (the inspector open), the timesheet scrolls sideways
    instead of pushing the window past the screen.
- **Retired:** a card listing retired people; clicking one opens them.
- **Person page (inspector):** name, phone, paid (Hourly or Salary), rate,
  the last four weeks, notes, **Retire** / **Bring back**, and **Delete
  person** only for someone with no hours on record. Changes save as they
  are made.
- **Add person (sheet):** name, Hourly or Salary, rate for hourly (optional).

## The Assistant

- New action `log_hours`: `workerName`, `ref` (W1, W2… from the crew list
  sent with the note), `hours` (digits; 0 for a day off) and `date`. One
  action per person per day. The wording is in `assistant-actions.md`.
- Every log_hours action in a note shares one **Hours** screen, at the
  first one's place among the steps: a row per person with the day and the
  hours (hourly) or Worked on/off (salaried). Someone not on the crew shows
  in the warning colour with "Add Kevin to the crew" (on) and Hourly or
  Salary. Save writes every row ("Hours saved for 4 people.").
- The records sent with each note include the crew and their hours this
  week and last week, so "how many hours did Joey work this week" is
  answered from them.
- Seen on the Mac, Oct 20: "Joey worked 8 today, Chris 6 and a half, Dave
  was out sick Monday, and the new guy Kevin did 5 hours today" gave four
  rows and saved them; "How many hours has Joey worked this week and what
  do I owe him?" was answered correctly. Twice the Sonnet setting returned
  one action while its questions named the third and fourth; the app now
  asks again on Haiku when that happens (not yet seen firing).

## iPhone

The Labor tab (`Ace/Labor/LaborView.swift`) took Quotes' place in the tab
bar; Quotes now opens from the Calendar.

- The week as seven day buttons, then the chosen day: everyone on the
  crew, salaried first (the boxes come first since the Oct 20 phone audit,
  so Alex sees them without scrolling). Then four figures (hourly hours,
  hourly pay, working today, crew). A Today button shows while another day
  is chosen, and the page moves to the new day after a night in the
  background. Hourly crew have a box for the day's hours; salaried crew a box
  with a check that a tap turns to "Off".
- Tapping an hours box selects what is in it, so typing replaces it, and
  scrolls it clear of the keyboard. The number pad has a Done button.
  Anything that is not hours, or more than 24 ("85" for 8.5), is not saved:
  the old value comes back with a warning buzz. Typing still under way when
  another day is picked is saved to the day it was typed for.
- Someone retired mid-week still counts in that week's hours and pay, shown
  as "Retired" in the week's totals.
- Delete is offered only for someone added by mistake: no hours yet, and for
  salaried crew only on the day they were added.
- Under that, the week's totals per person, then people who have left.
- Add person is the button at the top left. A person's page has their
  details, the last four weeks, Retire, and Delete (only for someone with
  no hours yet).
- At the largest text sizes each row puts the box under the name.

## Not built

- Hours do not sync between devices until the Cloudflare sync (step 5).
  Alex's phone and Ashley's Mac each have their own timesheet until then.
- No start and end times, no overtime, no export for payroll.
- No screen for the salaried work week.

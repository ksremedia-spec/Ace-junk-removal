# How long a job takes, and overlaps

Asked for by Kyle, 2026-10-19: "Does it currently have a timing feature like
so Ashley could input hey this job is gonna take two hours. How does the app
currently reconcile and keep things from overlapping". Asked how a clash
should be judged (any overlap, more jobs than trucks, or one truck per job),
Kyle chose **any overlap**.

## In plain English

Every job with a start time also has a length: "How long", such as 2 hours.
The app works out when it ends. Whenever a job is saved, typed or spoken, the
app checks it against every other unfinished job that day that has a time.
If the two overlap at all, it says so and asks before saving. A job that ends
exactly when another starts (9:00 to 11:00, then 11:00) is not a clash. Jobs
with no time set ("Set a time" off) have no length and are never checked.

Before this change the app only caught two jobs at exactly the same start
time, and only through the Assistant.

## The record

`Job` gains `durationMinutes` (whole minutes). 0 means "not set", and the job
then takes its type's default length. Existing jobs are 0, so nothing has to
be filled in by hand.

| Type | Default length |
|---|---|
| Junk removal | 2 hours |
| Demolition | 4 hours |
| Dumpster drop-off | 30 minutes |
| Dumpster pickup | 30 minutes |
| Dumpster swap | 1 hour |
| Estimate | 30 minutes |
| Other | 30 minutes |

These defaults are assumptions to be checked with Ashley and Alex.

## Screens

- **Job form** (New Job, editing a job, Book Job from a quote): a **How long**
  row under Time, shown only while "Set a time" is on. A picker with: 30
  minutes, 1 hour, 1½ hours, 2 hours, 2½ hours, 3 hours, 4 hours, 5 hours,
  6 hours, 8 hours (and the job's own value if it is something else, such as
  7 hours from the Assistant). It starts at the type's default and follows
  the type until it is changed by hand.
- **Overlap note:** while the form's day, time or length overlaps another
  job, a short note in the warning color sits under How long: "Overlaps Linda
  Johnson, Junk removal, 9:00 to 11:00 AM." (the first overlapping job; "and
  2 more" when there are others).
- **On Save** with an overlap: one yes/no question, "This overlaps Linda
  Johnson, 9:00 to 11:00 AM. Save anyway?" (No keeps the form open.) The
  Assistant's new-job screen asks it as one of its one-at-a-time questions,
  in place of the old same-start-time question.
- **Lists** show the range for timed jobs: "9:00 to 11:00 AM" (Today, Jobs,
  customer history, Mac lists). Untimed jobs are unchanged.
- **Assistant screens:** new job and Book Job have How long and the overlap
  note; Update Job shows the note when a job is moved to a time that
  overlaps.

## The Assistant

A new answer field `hours` ("Length of the job in hours as digits, like 2 or
1.5, or empty."). Claude fills it when a length is said: "it'll take about two
hours", "half a day" (4), "all day" (8). Empty means the type's default. It
applies to new_job, update_job (the length changed) and update_quote when
approved. Job lines in the records show the range: "J1 Mon, Oct 19 9:00 to
11:00 AM". The full contract is in `assistant-actions.md`.

## Not in this change

Trucks and crews are not tracked, so the app cannot tell two jobs on
different trucks apart; with five trucks some warnings will be expected.
That was Kyle's choice (option 1 of 3).

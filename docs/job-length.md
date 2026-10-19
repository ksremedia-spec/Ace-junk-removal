# End times, and overlaps

Asked for by Kyle, 2026-10-19: "Does it currently have a timing feature like
so Ashley could input hey this job is gonna take two hours. How does the app
currently reconcile and keep things from overlapping". Asked how a clash
should be judged (any overlap, more jobs than trucks, or one truck per job),
Kyle chose **any overlap**. A first version used a default length per job
type; Kyle then said: "no defaults, end time will be selected or spoken."

## In plain English

A job with a start time can also have an **end time**, picked on the form or
spoken to the Assistant ("till noon", "about three hours"). Nothing is
assumed: a job with no end time just has its start time. Whenever a job is
saved, typed or spoken, the app checks it against every other unfinished job
that day that has a time, and asks before saving if they clash.

Before this change the app only caught two jobs at exactly the same start
time, and only through the Assistant.

## What counts as a clash

- Two jobs with end times clash when their spans overlap at all. A job that
  ends exactly when another starts (9:00 to 11:00, then 11:00) does not.
- A job with no end time is treated as its start moment only. It clashes
  with a job whose span contains that moment (a 10:00 start inside 9:00 to
  11:00), or with a job that starts at the same time.
- Jobs with "Set a time" off are never checked. Done jobs are never checked.

## The record

`Job` gains an optional end time (none by default). Existing jobs have none.
The end must be later than the start on the same day.

## Screens

- **Job form** (New Job, editing a job, Book Job from a quote): under Time,
  a switch **Set an end time** (only while "Set a time" is on). When on, an
  **Ends** time picker. Turning it on puts the picker one hour after the
  start, just as a starting point to choose from; nothing is saved until
  Save. An end that is not after the start shows "Ends before it starts." in
  the warning color and blocks Save.
- **Overlap note:** while the form clashes with another job, a short note in
  the warning color under the times: "Overlaps Linda Johnson, Junk removal,
  9:00 to 11:00 AM." (the first clashing job; "and 2 more" when there are
  others).
- **On Save** with a clash: one yes/no question, "This overlaps Linda
  Johnson, 9:00 to 11:00 AM. Save anyway?" (No keeps the form open). The
  Assistant's new-job screen asks it as one of its one-at-a-time questions,
  in place of the old same-start-time question.
- **Lists** show "9:00 to 11:00 AM" for jobs with an end time and "9:00 AM"
  for jobs without (Today, Jobs, customer history, Mac lists).
- **Assistant screens:** new job, Update Job and Book Job have the end time
  and the overlap note.

## The Assistant

A new answer field `endTime` ("HH:MM, 24-hour: when the job ends, or
empty."). Claude fills it when an end time or a length is said, working the
end out from the start: "till noon" is 12:00; "about three hours" from a 9:00
start is 12:00. Empty means no end time. It applies to new_job, update_job
(the end changed, or the job moved and a new end was said) and update_quote
when approved. Job lines in the records show "9:00 to 11:00 AM" when the end
is known. The full contract is in `assistant-actions.md`.

## Not in this change

Trucks and crews are not tracked, so two crews working at the same time
will raise a warning. That was Kyle's choice (option 1 of 3).

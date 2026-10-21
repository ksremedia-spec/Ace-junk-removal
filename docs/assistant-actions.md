# What the Assistant understands

This is the contract for the Assistant, shared by the iPhone/Mac app and the
browser demo. Both send Claude the same instructions and the same answer
shape, and both handle the answer the same way. Change it here first.

Decided 2026-10-19 after Kyle: "It needs many possible answers not just 6,
think and implement all possible options for a junk removal company." and
earlier "Shouldn't the model just figure out what's going on without you
having to train it? What if something comes up we haven't trained it."

## How it works, in plain English

1. Someone says something. It is written down on the device.
2. The app sends Claude the words, the list of things the app can do (below),
   and the records that matter: dumpsters, jobs from a week ago to two weeks
   ahead, the open quotes, any customer whose name, phone or street was said,
   and a few totals. Every record carries a short reference such as C4
   (customer), J12 (job), Q2 (quote) or D3 (dumpster 3).
3. Claude works out what is wanted and answers with a list of actions, a
   reply, or both. It points at records by their reference, so the app does
   not have to guess. When the person names someone not in the list, Claude
   passes the name, phone or address and the app looks it up.
4. The app shows one confirmation screen per action, in order ("1 of 3"),
   with what will change. One tap saves each. Skip leaves one out. Cancel
   stops.
5. A question gets a plain answer. Anything the app cannot do gets a plain
   answer saying what was understood and what to do instead. Nothing is ever
   saved without a tap.

The list of actions is what the app can do, not what Claude can understand.
Claude understands nearly anything said; the list decides what can be done
with it. Adding an ability later means adding an action here and a screen
for it.

## What people say, and what happens

### Office: booking and customers

| Said | Action | Screen |
| --- | --- | --- |
| "Mrs. Johnson, 42 Elm, garage cleanout Friday morning, 300 cash" | new_job | New job form, problems flagged and asked one at a time |
| "Pereira needs a dumpster Friday, 7 Bay Road, 450" | new_job (Dumpster drop-off) | New job form |
| "Silva basement cleanout Friday at 9, about three hours" | new_job (time 09:00, endTime 12:00) | New job form, 9:00 to 12:00, checked for overlaps |
| "The Johnson job will run till 3" | update_job (endTime 15:00) | Job changes, checked for overlaps |
| "Swap at Keane's Thursday" | new_job (Dumpster swap) | New job form |
| "Schedule a quote for the Silva basement Tuesday at 10" | new_job (Quote visit) | New job form |
| "Call back Mrs. Smith Thursday about the second dumpster" | new_job (Other, note "Call back about the second dumpster") | New job form; shows on Today that day |
| "Add Dave Macomber, 774 555 0171, 88 Plymouth St" | new_customer | New customer |
| "Linda Johnson's new number is 508 555 0199" | update_customer | Customer changes |
| "Johnson moved to 50 Oak St, Raynham" | update_customer | Customer changes |
| "Keane's gate code is 4412" | update_customer (note) | Customer changes |
| "Move Johnson to Thursday at 2" | update_job (newDate, newTime) | Job changes |
| "Johnson's price is 350 now" | update_job (price) | Job changes |
| "Cancel the Johnson job" | cancel_job | Delete job, asked first |
| "Call Johnson" / "Text Johnson we're 15 minutes out" / "Directions to the next job" | contact_customer | Call, Message or Directions buttons |

### Quotes (added 2026-10-19, see `quotes.md`)

| Said | Action | Screen |
| --- | --- | --- |
| "Quote for 66 Johnson Street, garage cleanout, 800" | new_quote | New quote form, filled in; call-back day three days out unless one was said |
| "Gave Silva a price of 1,200 for the shed, call her back Monday" | new_quote (followUp) | New quote form |
| "The quote for 66 Johnson Street, 800, customer approved" | update_quote (approved) | Book Job: the job filled in from the quote; saving books it and marks the quote booked |
| "Silva approved, do it Friday morning" | update_quote (approved, date, time) | Book Job, with Friday morning filled in |
| "Silva went with someone else" | update_quote (declined) | Mark Lost |
| "Call Silva back Thursday about the quote" | update_quote (followUp) | Quote changes |
| "Silva's quote is 1,100 now" | update_quote (price) | Quote changes |
| "Which quotes need a call back?" | question | Plain answer from the open quotes |

When a price is given and accepted in the same note and no open quote
matches, it is a new_job, not a quote.

### Field: finishing work and dumpsters

| Said | Action | Screen |
| --- | --- | --- |
| "Johnson's done, paid cash" | update_job (done, paid, cash) | Job changes |
| "Done at Keane's, they'll mail a check" | update_job (done, paid no, note) | Job changes |
| "Pereira paid 250 by card" | update_job (paid, card, price 250) | Job changes |
| "Nobody home at the Silva job, moved to Thursday" | update_job (newDate, note) | Job changes |
| "Dump fee was 85 on the Johnson job" | update_job (note) | Job changes |
| "Got 50 extra for the mattress at Johnson's" | update_job (price, note) | Job changes |
| "The check from Pereira bounced" | update_job (paid no, note) | Job changes |
| "Dropped dumpster 3 at Pereira's, 7 Bay Road, 450, two tons, back next Friday" | dumpster_dropoff | Dumpster drop-off; also offers to mark the booked drop-off job done |
| "Picked up dumpster 1, 2.8 tons" | dumpster_pickup | Dumpster pickup with the overweight charge; also offers to mark the booked pickup job done |
| "Swapped 2 at Keane's, 3.1 tons, left 5" | dumpster_swap | Take away one, leave another, in one screen |
| "Harborview is keeping the dumpster till Monday" | update_rental (dueBack) | Rental changes |
| "Dumpster 2 has a cracked door, don't send it out" | dumpster_note | Dumpster note, shown wherever the dumpster appears |

### Questions, answered from the records

"Which dumpsters are due back Friday", "what do we have tomorrow", "how much
does Pereira owe", "what's Johnson's address", "who has dumpster 3", "is a
dumpster free Friday", "how much is owed", "what did we do this week",
"which quotes need a call back", "what's out for quotes", "how many hours
did Joey work this week", "who was off Monday".

### Crew hours (added 2026-10-20, see `labor.md`)

| Said | Action | Screen |
| --- | --- | --- |
| "Joey worked 8 today and Chris 6 and a half" | log_hours × 2 | Hours: one screen with a row per person |
| "Dave was out sick Monday" | log_hours (hours 0) | Hours: Dave off Monday |
| "Mark worked Sunday" | log_hours (hours 8) | Hours: Mark in on Sunday |
| "New guy Kevin did 5 hours" | log_hours (no ref) | Hours, with "Add Kevin to the crew" |

### Several things at once

"Johnson's done, paid cash, and she wants a dumpster next Friday" gives two
actions: update_job and new_job. "Mark all of today's jobs done" gives one
update_job per job, each pointing at its reference.

### Things the app cannot do yet (plain answer, nothing saved)

Sending an invoice or receipt, changing a setting, undoing a change,
anything about a truck, deleting a customer. The reply says what was
understood and the nearest thing that can be done.

## The answer Claude returns (structured output)

Every property is required; an empty string means "not said". Objects do not
allow other properties.

```json
{
  "type": "object",
  "properties": {
    "reply": { "type": "string", "description": "The answer to a question, or what was understood when nothing can be done, in one or two plain sentences. Empty when the actions cover the note." },
    "actions": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "type": { "type": "string", "enum": ["new_job", "update_job", "cancel_job", "new_customer", "update_customer", "contact_customer", "dumpster_dropoff", "dumpster_pickup", "dumpster_swap", "update_rental", "dumpster_note", "new_quote", "update_quote", "log_hours"] },
          "ref": { "type": "string", "description": "Reference of the record this action is about, from the records list (C4, J12, Q2, D3, W2), or empty." },
          "customerName": { "type": "string" },
          "phone": { "type": "string", "description": "Digits with dashes, like 508-555-0123, or empty." },
          "address": { "type": "string", "description": "Street address with house number, town and state, or empty." },
          "jobType": { "type": "string", "enum": ["Junk removal", "Demolition", "Dumpster drop-off", "Dumpster pickup", "Dumpster swap", "Quote visit", "Other", ""] },
          "date": { "type": "string", "description": "YYYY-MM-DD: the day of a new job, or the day of the job meant, or empty." },
          "time": { "type": "string", "description": "HH:MM, 24-hour, or empty." },
          "endTime": { "type": "string", "description": "HH:MM, 24-hour: when the job ends, or empty." },
          "price": { "type": "string", "description": "Dollars as digits, like 300, or empty." },
          "paymentType": { "type": "string", "enum": ["cash", "check", "card", "venmo", "cash app", ""] },
          "paid": { "type": "string", "enum": ["yes", "no", ""] },
          "done": { "type": "string", "enum": ["yes", "no", ""] },
          "newDate": { "type": "string", "description": "YYYY-MM-DD when a job moves, or empty." },
          "newTime": { "type": "string", "description": "HH:MM when a job moves, or empty." },
          "dumpsterNumber": { "type": "string", "enum": ["", "1", "2", "3", "4", "5", "6"] },
          "otherDumpsterNumber": { "type": "string", "enum": ["", "1", "2", "3", "4", "5", "6"], "description": "For a swap: the dumpster left in place." },
          "actualTons": { "type": "string", "description": "Weight at pickup in tons as digits, like 2.8, or empty." },
          "agreedTons": { "type": "string", "description": "Agreed weight in tons as digits, or empty." },
          "dueBack": { "type": "string", "description": "YYYY-MM-DD, or empty." },
          "followUp": { "type": "string", "description": "YYYY-MM-DD: the day to call back about a quote, or empty." },
          "quoteStatus": { "type": "string", "enum": ["approved", "declined", ""], "description": "For update_quote: approved when the customer said yes, declined when they said no." },
          "note": { "type": "string", "description": "Anything to write down, in one short sentence, or empty." },
          "newName": { "type": "string" },
          "newPhone": { "type": "string" },
          "newAddress": { "type": "string" },
          "contact": { "type": "string", "enum": ["call", "text", "directions", ""] },
          "message": { "type": "string", "description": "For a text: the message to send." },
          "workerName": { "type": "string", "description": "For log_hours: the crew member's name as said, or empty." },
          "hours": { "type": "string", "description": "For log_hours: hours worked as digits, like 8 or 7.5, 0 for a day off, or empty." }
        },
        "required": ["type", "ref", "customerName", "phone", "address", "jobType", "date", "time", "endTime", "price", "paymentType", "paid", "done", "newDate", "newTime", "dumpsterNumber", "otherDumpsterNumber", "actualTons", "agreedTons", "dueBack", "followUp", "quoteStatus", "note", "newName", "newPhone", "newAddress", "contact", "message", "workerName", "hours"],
        "additionalProperties": false
      }
    },
    "issues": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "action": { "type": "integer", "description": "Position of the action in the list, 0 for the first." },
          "field": { "type": "string", "enum": ["customerName", "phone", "address", "jobType", "date", "time", "endTime", "price", "paymentType", "paid", "done", "newDate", "newTime", "dumpsterNumber", "otherDumpsterNumber", "actualTons", "agreedTons", "dueBack", "followUp", "note", "newName", "newPhone", "newAddress", "ref", "workerName", "hours"] },
          "question": { "type": "string", "description": "One short plain yes/no question." }
        },
        "required": ["action", "field", "question"],
        "additionalProperties": false
      }
    }
  },
  "required": ["reply", "actions", "issues"],
  "additionalProperties": false
}
```

Checked against Anthropic's structured-outputs page (2026-10-19,
https://platform.claude.com/docs/en/build-with-claude/structured-outputs):
this schema has no optional parameters (limit 24) and no union types
(limit 16); a schema that is too large for the grammar gets a 400 "Schema is
too complex for compilation", which has not been seen yet because no real
request has been made from the cloud session. Enum values can come back with
different capitals ("Junk Removal" for "Junk removal"), so the app compares
every enum value without case.

## The instructions sent to Claude (system prompt)

`{today}` is like "Monday, October 19, 2026", `{zone}` the time zone name,
`{now}` the time like "9:41 AM". Send it word for word.

```text
You help the office and the crew of Ace Junk Removal, a junk removal, demolition and dumpster rental company in Massachusetts. The input is a spoken note written down by speech recognition, so names, street names and numbers may be misheard. Fix a misheard word only when the correction is certain.

Today is {today} ({zone}). The time is {now}.

The person speaking is Ashley in the office (booking work, answering the phone, keeping the books) or Alex and the crew in the field (finishing jobs, collecting payment, dropping off and picking up dumpsters). Work out what they want done and return it as a list of actions. One note can hold several actions: "Johnson's done, paid cash, and she wants a dumpster next Friday" is an update to her job and a new job.

The records sent with the note start with the customer directory: every customer on file, with phone and address. Then come the dumpsters, the jobs from two weeks ago to two months ahead, the open quotes, the crew with their hours this week and last week, and fuller lines for the customers the note seems to be about. Each record has a reference like C4, J12, Q2, D3 or W2. When an action is about a record, put its reference in "ref". Look customers up in the directory by name, phone, street or town. Speech recognition often mishears house numbers and names, so a close match on the same street or a similar name is probably the one meant: use it and say so, rather than saying nobody was found. When the note names someone who is in neither the directory nor the records, leave "ref" empty and fill in the name, phone and address as said; that is a new customer.

Actions:
- new_job: book new work. Fill customerName, phone and address as said, jobType, date, time, endTime (when it will end, when an end or a length was said), price, paymentType, paid and note. A dumpster delivery, pickup or swap booked for later is a new_job with that jobType. A visit to look at work and give a price is jobType "Quote visit": "schedule a quote", "quote it Tuesday at 3", "go price the basement", "come out and give a price". A call-back or reminder is jobType "Other" on that day, with the reason in note.
- update_job: change a job that exists. done "yes" when it is finished, "no" when it is not finished after all. paid "yes" when it was paid, with paymentType and, if an amount was said, price; paid "no" when payment did not happen or a check bounced. newDate and newTime when it moved. endTime when its end changed or a new end was said. price when the price changed. jobType when the kind of work changed. note for anything to write down: a no-show, a dump fee, an extra item, a promise to pay later. Being paid on site means the work is done. Fill only what changes.
- cancel_job: the job is off. The app asks before removing it.
- new_customer: add a customer without booking work: customerName, phone, address, note.
- update_customer: a customer's details changed or there is something to remember about them: newName, newPhone, newAddress, note (gate codes, dogs, how they pay, who to ask for).
- contact_customer: call, text or get directions. contact is "call", "text" or "directions"; for a text, message is the text to send. ref can be the customer or the job.
- dumpster_dropoff: a dumpster has just been dropped off or delivered: dumpsterNumber, customerName, address, dueBack, price, agreedTons, note.
- dumpster_pickup: a dumpster has just been picked up, collected or weighed: dumpsterNumber (or the customer or address it was at) and actualTons.
- dumpster_swap: a full dumpster was taken away and an empty one left in its place: dumpsterNumber is the one taken away, actualTons its weight, otherDumpsterNumber the one left, and dueBack, price and agreedTons for the new rental when said.
- update_rental: change a dumpster that is out: dueBack (kept longer or picked up sooner), price, agreedTons, newAddress (moved on the property or to another place), note.
- dumpster_note: something about a dumpster itself, such as damage or that it should not go out: dumpsterNumber and note.
- new_quote: a price was given that the customer has not accepted yet: customerName, phone and address as said, jobType, price, note (what was quoted, in a few words) and followUp (the day to call them back, when said).
- update_quote: an open quote changed. quoteStatus "approved" when the customer said yes or approved it, with date, time and endTime for the work when said; "declined" when they said no or went elsewhere. price when it changed. followUp when a call-back day was said. note for anything to write down. A call-back about an open quote is an update_quote with followUp, not a new_job. When a price is given and accepted in the same note and no open quote matches, book a new_job instead. A quote with a day or time to go and see the work is a visit, not a new_quote: book a new_job with jobType "Quote visit" on that day.
- log_hours: hours a crew member worked on a day: workerName as said, ref when they are on the crew list (W2), hours as digits ("eight and a half" is 8.5; 0 when they were off or out sick) and date (today when no day is said). One action per person per day: "Joey worked 8 today and Chris 6" is two. A first name alone is enough when it matches one person on the crew. Salaried crew count as working their work days without being logged: log them only when they were off (hours 0) or worked another day (the hours said, or 8).

When the note asks a question, for example "which dumpsters are due back Friday", "what do we have tomorrow", "how much does Pereira owe", "what's Johnson's address", "who lives at 63 Locust Street in Taunton", "is a dumpster free Friday", "which quotes need a call back" or "how many hours did Joey work this week", answer it in "reply" from the records in one or two plain sentences, and return actions only if something should also be done. If the records do not hold the answer, say so. Name customers and jobs in "reply" by name and day, never by their reference (C4, J12): references are for the app.

When the note asks for something none of the actions can do, such as sending an invoice, changing a setting, undoing a change or deleting a customer, say in "reply" what was understood and the nearest thing that can be done, and return no actions.

Leave "reply" empty when the actions cover the note.

Rules for fields:
- Fill only what the note says. Use an empty string for anything not said. Never invent a name, number, price or address.
- Dates as YYYY-MM-DD, worked out from today: "tomorrow", "Friday" (the next Friday, or today if today is Friday), "next week". Times as HH:MM in 24-hour time. "This morning", "just now", "just finished" and "on site" mean today.
- Money as digits: "three hundred" is 300. Weights in tons as digits: "two point eight" is 2.8. An end time is worked out from what was said: "till noon" is 12:00; "about three hours" from a 9:00 start is 12:00. With no end or length said, leave endTime empty; never guess one. A day said without a time ("tomorrow", "Friday") still fills date; leave time empty and do not ask about it. Speech recognition sometimes writes a time as money: "tomorrow at $10" is 10:00, not a price.
- jobType from the work described; nobody says "junk removal" out loud. Junk removal: clearing, emptying or cleaning out a garage, basement, attic, shed, house, estate or office, or hauling away furniture, appliances, debris or a hot tub. Demolition: tearing down or taking out a shed, deck, pool, fence, wall, kitchen, bathroom or flooring, or any mention of "demo". Dumpster drop-off, Dumpster pickup and Dumpster swap: booking those for a later day. Quote visit: going to look and give a price; the office calls this a quote, never an estimate. Other: anything else. Leave it empty only when nothing says what the work is.
- paymentType is cash, check, card, venmo or cash app. "PD cash 300" means paid, cash, 300. "Venmo'd me" is venmo; "Cash App", "cashapp" or "sent it on cash app" is cash app.

Issues: list what the person should confirm before saving, each tied to an action by its position in the list (0 for the first), naming the field and asking one short yes/no question. For a new job: no date, no price (except a quote visit, which is booked to work out the price), no phone number for a new customer, a date in the past, an address with no house number, a name or address that sounds misheard, two values said for one field, and the kind of work only when nothing in the note hints at it. A name that is not in the directory is a new customer: never ask whether it is new or in the records. A time not said is fine: never ask about it. For a new quote: no price, no phone number for someone not in the records, an address with no house number. For log_hours: a name that is not on the crew list (the app asks before adding a new person), and no hours said for someone hourly. For any other action: only when it is unclear which record is meant or what should change, and for a pickup or swap when no weight was said.

Plain business language. No exclamation points.
```

## The records sent with the note (user message)

The message has two blocks. The first is the customer directory, which
changes only when customers do, so it is marked for prompt caching
(`cache_control: ephemeral`) and a second note within a few minutes does not
pay for it again. The second is the note and the rest of the records.

```text
Customer directory (every customer on file):
- C1 Al & Lisa Souza · 774-555-0341 · 151 Center St, Lakeville, MA
- C2 Al & Matt DeLuca · 508-555-0249 · 254 Hart St, Somerset, MA
- ... every customer, in name order
```

```text
Spoken note:
<the words>

Records:
Dumpsters:
- D1 Dumpster 1 (15 yard): out with C203 Harborview Realty at 300 Broadway, Taunton, MA since Sat, Oct 10, 2026; due back Sat, Oct 17, 2026 (overdue); $450; 2 tons agreed
- D3 Dumpster 3 (15 yard): in the yard. Note: cracked door
Jobs from Mon, Oct 5, 2026 to Fri, Dec 18, 2026:
- J1 Mon, Oct 19, 2026 9:00 to 11:00 AM · C311 Linda Johnson · Junk removal · $300 cash · not paid · not done · 42 Elm St, Taunton, MA
Open quotes:
- Q1 C120 Dave Macomber · 88 Plymouth St, Middleborough, MA · Junk removal · Garage cleanout, about two loads · $450 · quoted Tue, Oct 13, 2026
Crew (hours this week from Sun, Oct 18, 2026, and last week):
- W1 Dave Brennan · salary, works Mon to Sat · this week: off Mon, Oct 19 · last week: 6 days
- W3 Chris Pacheco · hourly, $20 an hour · this week: Mon 8, Tue 7.5 (15.5 hrs) · last week: 38 hrs
Customers named in the note or on these records:
- C311 Linda Johnson · 508-555-0147 · 42 Elm St, Taunton, MA · Side gate code 4412 · 4 jobs, $1,180, owes $0, last job Mon, Oct 19, 2026
  - J1 ... (for customers the note names, their last 8 jobs, each with a reference)
Totals: owed $19,550 from 31 jobs; done this week $2,140 from 6 jobs; booked today $750 from 2 jobs.
```

- Customer references are given in name order over the whole directory, so
  they are the same for every note while the customers are the same (that
  is what lets the directory be cached). Job and quote references are made
  fresh for each note (J1, J2…, Q1…; D is the dumpster number). All are kept
  with the request so the app can turn them back into records.
- Dates always carry the year ("Mon, Oct 19, 2026"): history goes back years.
- Crew: everyone still on the crew, salaried first, then by name, with W
  references made fresh for each note. Salaried lines list only the days
  that differ from their work week ("off Mon, Oct 19", "in Sun, Oct 18");
  hourly lines list each day with hours and the week's total. Retired
  people are not sent.
- Jobs: two weeks back to two months ahead (was one week back, two weeks
  ahead, until 2026-10-20).
- Fuller customer lines: up to ten customers the note seems to name,
  strongest match first: phone digits (4 points), the full name or a house
  number plus street word (3), the street alone when twelve customers or
  fewer live on it (1.5, so "63 Locust St" finds the people on Locust St
  even when the number was misheard), the last name (1), and another word of
  the name, four letters or more, shared by three customers or fewer (0.5).
  Apostrophes and a possessive are ignored on both sides. Ties keep the list
  order. Each of these gets their last 8 jobs. Then everyone on the listed
  jobs, dumpsters and open quotes. The demo (`demo/app-demo`) still builds
  its records the old way; only its instructions were synced.
- Open quotes: every open quote, oldest first, each with its customer's
  reference and address, the type, what was quoted, the price ("no price"
  when none), the day quoted, and the call-back day marked "(overdue)" or
  "(today)" when due. "- none" when there are none. Booked and lost quotes
  are not sent. Customers on open quotes are listed under Customers.
- A job with a time shows its start, and its end when it has one ("9:00 to
  11:00 AM", or "11:00 AM to 1:00 PM" across noon; see `job-length.md`), so
  questions like "is the crew free at 10" can be answered.
- A job line ends with the job's notes when it has any, joined into one
  line ("· Call back about a second dumpster"). Without them a call-back
  booked as "Other" would carry no reason.

## How the app handles the answer

- No actions: show the reply ("No answer was found." if empty) with "Ask
  something else" and "Done".
- Actions: one screen per action, in order. With more than one, each screen
  says "1 of 3" and has Skip. The reply, if any, is shown above the first.
- Finding the record: a valid reference of the right kind wins (a job
  reference given to a customer action means that job's customer). Otherwise
  match by phone, then name (whole name, or last name), then address; jobs by
  the said date, then today's open job, then the nearest open job, then the
  latest done one; dumpsters by number, then by who or where they are out.
  Several matches: "Which job?" / "Which customer?" / "Which dumpster?" list.
  A name that matches nobody never lands on someone else's record without
  asking. A reference that points at nothing (a job deleted by an earlier
  step, or one that was never listed) gives "That job is no longer in the
  records." for update_job and cancel_job, never another job.
- Questions: each screen shows Claude's questions next to its own fields. A
  question about a field the screen has no row for (most often "ref", which
  record was meant) is shown above the screen in the warning color. The
  new-job screen asks every question on Save.
- Screens: new_job uses the new-job form with its one-at-a-time questions.
  update_job, dumpster_pickup and dumpster_dropoff use their screens. The rest
  use a simple form: the record's details, the changes as editable fields, and
  one button (Save, Delete Job, Swap, and so on). contact_customer shows Call,
  Message and Directions buttons that open the phone, Messages or Maps.
- Drop-off and pickup also offer to mark the matching booked job done (an open
  "Dumpster drop-off" or "Dumpster pickup" job for that customer, today or
  earlier), switched on.
- After the last screen: one short confirmation ("Job saved.", "3 changes
  saved."), and on the Mac the changed record is selected.
- cancel_job removes the job after a confirmation alert.
- Overlaps are checked in code, not by Claude, on every save of a job with a
  time (see `job-length.md`): any overlap with another unfinished timed job
  that day gives a note in the warning color and one yes/no question before
  saving. This replaces the old same-start-time check. A job with no end
  time counts as its start moment only.
- new_quote: the New Quote form, filled in. The customer is matched the
  way the new-job form matches (see "Same customer or new" below). When
  nobody matches, saving adds a customer with the name, phone and address
  said. Quoted is today. The call-back day is the one said, else three days
  out (shown, not flagged). Confirmation "Quote saved."
- log_hours: every log_hours action in the plan shares one Hours screen,
  at the first one's place among the steps (see `labor.md`). Confirmation
  "Hours saved." or "Hours saved for 3 people."
- Asked again on Haiku, once: an answer with an action that is completely
  empty, or with questions about actions it does not contain (Sonnet 5.5,
  Oct 20: one action returned for a note naming four people).
- update_quote: finds the quote by its reference; otherwise among open
  quotes by the customer's phone, name or address ("Which quote?" for
  several, "No open quote found for …" for none, with Skip). Then:
  - approved: a Book Job screen with the quote at the top and the job's
    date, time, price and payment below. The price starts at the quote's
    unless a new one was said; the date is the one said, else today, flagged
    "No day was said for the work." Saving adds the job (customer, type and
    what was quoted as its notes) and marks the quote booked and linked.
    Confirmation "Job saved."
  - declined: the quote with Mark Lost. Confirmation "Quote marked lost."
  - otherwise: the quote with its price, call-back day and a note to add,
    and Save. Confirmation "Quote saved."
- A step that saved nothing (Skip) adds nothing to the confirmation.
- dumpster_note is kept on the dumpster until changed and shown on its row and
  screen.

## Same customer or new (Kyle, 2026-10-19 and 10-20)

A new job or quote goes to a customer on file only when the name matches
(ignoring Mr./Mrs. and a trailing 's) and nothing said disagrees with the
record: a phone said must be the one on file, and an address said must have
the same house number and street. With no phone or address said, the name
alone decides. The same phone under a different name is a new customer, and
so is the same name at a different address. The customer Claude's reference
points at stands while the name and phone agree; its address is not checked,
because house numbers are often misheard. Code: `existingCustomer` in
`AssistantMatching.swift`.

## Follow-up questions (Kyle, 2026-10-20)

The new-job and new-quote forms show a **Missing** section at the top while
something is missing, in this order: name, address (or only the house
number), phone, date (new job only), price (not for a quote visit). A
customer on file covers their own phone and address. A time is never asked
for. The app never talks back out loud (Kyle: "I don't want it to talk
back, maybe it asks questions back on screen").

- **One question on screen.** The first missing item is asked as a
  question ("No house number. What's the house number?") with three buttons:
  **Hold to answer**, **Type it** (the cursor goes to that field) and
  **Not now**. Filling the field by any means moves on to the next question.
  Items passed over stay below as buttons, and Save does not ask about them
  again (Oct 20 phone audit; the step bar's own button is "Skip step").
- **Click to type.** Under the question, every missing item is a button
  that puts the cursor in its field. A missing house number gets its own
  small field above the address, and the number goes in front of the
  street on save. On Save, "Fix it" in a question also goes to the field.
- **Answering by voice.** Hold to answer works like the main talk button:
  hold, talk, let go; or tap once, talk, tap again. The words show as they
  are heard. Saying "skip" (or "no", "I don't know", "no phone") skips.
- **Reading the answer.** A plain number for the house number, a 7- or
  10-digit phone and a price with digits are read in code. Everything else
  (a name, an address, "tomorrow", "three hundred") goes to Claude Haiku at
  low effort with the question, the answer and the form so far, and comes
  back as one value in the field's format. An empty value means the answer
  did not give it; the question stays, with "Heard “…”, but no … in it."
- Saving is still a tap on Save.

The instructions for one answer (`FollowUpPrompt` in `FollowUp.swift`),
word for word, with `{today}` and `{zone}` as in the main prompt:

```text
You fill in one missing detail on a booking form for Ace Junk Removal, a junk removal, demolition and dumpster rental company in Massachusetts. The app asked a question on screen and speech recognition wrote down the spoken answer, so words and numbers may be misheard.

Today is {today} ({zone}).

Return the value for the field named, in its format:
- customerName: the name as it should be written, e.g. "Maria Pereira" or "First Parish Church".
- address: house number, street and town, e.g. "42 Elm St, Taunton". Keep the town already on the form when the answer leaves it out.
- houseNumber: the house number only, with a letter if one was said, e.g. "42" or "42B".
- phone: the digits only, e.g. "5085550147".
- date: YYYY-MM-DD, worked out from today: "tomorrow", "Friday" (the next Friday, or today if today is Friday), "next week".
- price: dollars as digits: "three hundred" is 300.

Return an empty value when the answer does not give it, for example "skip", "I don't know", "no phone" or something unrelated. Never invent a value.
```

The user message is `Field: …`, `Question asked: …`, `Spoken answer: …`,
then `The form so far:` with the name, phone, address, job (or what was
quoted), date and price. Structured output: one string property, `value`.


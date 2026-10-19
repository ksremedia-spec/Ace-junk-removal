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
   ahead, any customer whose name, phone or street was said, and a few totals.
   Every record carries a short reference such as C4 (customer), J12 (job) or
   D3 (dumpster 3).
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
| "Swap at Keane's Thursday" | new_job (Dumpster swap) | New job form |
| "Go look at the Silva basement Tuesday at 10 for a price" | new_job (Estimate) | New job form |
| "Call back Mrs. Silva Thursday about the quote" | new_job (Other, note "Call back about the quote") | New job form; shows on Today that day |
| "Add Dave Macomber, 774 555 0171, 88 Plymouth St" | new_customer | New customer |
| "Linda Johnson's new number is 508 555 0199" | update_customer | Customer changes |
| "Johnson moved to 50 Oak St, Raynham" | update_customer | Customer changes |
| "Keane's gate code is 4412" | update_customer (note) | Customer changes |
| "Move Johnson to Thursday at 2" | update_job (newDate, newTime) | Job changes |
| "Johnson's price is 350 now" | update_job (price) | Job changes |
| "Cancel the Johnson job" | cancel_job | Delete job, asked first |
| "Call Johnson" / "Text Johnson we're 15 minutes out" / "Directions to the next job" | contact_customer | Call, Message or Directions buttons |

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
dumpster free Friday", "how much is owed", "what did we do this week".

### Several things at once

"Johnson's done, paid cash, and she wants a dumpster next Friday" gives two
actions: update_job and new_job. "Mark all of today's jobs done" gives one
update_job per job, each pointing at its reference.

### Things the app cannot do yet (plain answer, nothing saved)

Sending an invoice or receipt, changing a setting, undoing a change, drivers'
hours, anything about a truck, deleting a customer. The reply says what was
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
          "type": { "type": "string", "enum": ["new_job", "update_job", "cancel_job", "new_customer", "update_customer", "contact_customer", "dumpster_dropoff", "dumpster_pickup", "dumpster_swap", "update_rental", "dumpster_note"] },
          "ref": { "type": "string", "description": "Reference of the record this action is about, from the records list (C4, J12, D3), or empty." },
          "customerName": { "type": "string" },
          "phone": { "type": "string", "description": "Digits with dashes, like 508-555-0123, or empty." },
          "address": { "type": "string", "description": "Street address with house number, town and state, or empty." },
          "jobType": { "type": "string", "enum": ["Junk removal", "Demolition", "Dumpster drop-off", "Dumpster pickup", "Dumpster swap", "Estimate", "Other", ""] },
          "date": { "type": "string", "description": "YYYY-MM-DD: the day of a new job, or the day of the job meant, or empty." },
          "time": { "type": "string", "description": "HH:MM, 24-hour, or empty." },
          "price": { "type": "string", "description": "Dollars as digits, like 300, or empty." },
          "paymentType": { "type": "string", "enum": ["cash", "check", "card", ""] },
          "paid": { "type": "string", "enum": ["yes", "no", ""] },
          "done": { "type": "string", "enum": ["yes", "no", ""] },
          "newDate": { "type": "string", "description": "YYYY-MM-DD when a job moves, or empty." },
          "newTime": { "type": "string", "description": "HH:MM when a job moves, or empty." },
          "dumpsterNumber": { "type": "string", "enum": ["", "1", "2", "3", "4", "5", "6"] },
          "otherDumpsterNumber": { "type": "string", "enum": ["", "1", "2", "3", "4", "5", "6"], "description": "For a swap: the dumpster left in place." },
          "actualTons": { "type": "string", "description": "Weight at pickup in tons as digits, like 2.8, or empty." },
          "agreedTons": { "type": "string", "description": "Agreed weight in tons as digits, or empty." },
          "dueBack": { "type": "string", "description": "YYYY-MM-DD, or empty." },
          "note": { "type": "string", "description": "Anything to write down, in one short sentence, or empty." },
          "newName": { "type": "string" },
          "newPhone": { "type": "string" },
          "newAddress": { "type": "string" },
          "contact": { "type": "string", "enum": ["call", "text", "directions", ""] },
          "message": { "type": "string", "description": "For a text: the message to send." }
        },
        "required": ["type", "ref", "customerName", "phone", "address", "jobType", "date", "time", "price", "paymentType", "paid", "done", "newDate", "newTime", "dumpsterNumber", "otherDumpsterNumber", "actualTons", "agreedTons", "dueBack", "note", "newName", "newPhone", "newAddress", "contact", "message"],
        "additionalProperties": false
      }
    },
    "issues": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "action": { "type": "integer", "description": "Position of the action in the list, 0 for the first." },
          "field": { "type": "string", "enum": ["customerName", "phone", "address", "jobType", "date", "time", "price", "paymentType", "paid", "done", "newDate", "newTime", "dumpsterNumber", "otherDumpsterNumber", "actualTons", "agreedTons", "dueBack", "note", "newName", "newPhone", "newAddress", "ref"] },
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

## The instructions sent to Claude (system prompt)

`{today}` is like "Monday, October 19, 2026", `{zone}` the time zone name,
`{now}` the time like "9:41 AM". Send it word for word.

```text
You help the office and the crew of Ace Junk Removal, a junk removal, demolition and dumpster rental company in Massachusetts. The input is a spoken note written down by speech recognition, so names, street names and numbers may be misheard. Fix a misheard word only when the correction is certain.

Today is {today} ({zone}). The time is {now}.

The person speaking is Ashley in the office (booking work, answering the phone, keeping the books) or Alex and the crew in the field (finishing jobs, collecting payment, dropping off and picking up dumpsters). Work out what they want done and return it as a list of actions. One note can hold several actions: "Johnson's done, paid cash, and she wants a dumpster next Friday" is an update to her job and a new job.

The records sent with the note list dumpsters, jobs and customers, each with a reference like D3, J12 or C4. When an action is about a record in the list, put its reference in "ref". When the note names someone or something not in the list, leave "ref" empty and fill in the name, phone, address or dumpster number as said; the app looks it up.

Actions:
- new_job: book new work. Fill customerName, phone and address as said, jobType, date, time, price, paymentType, paid and note. A dumpster delivery, pickup or swap booked for later is a new_job with that jobType. An on-site quote visit is jobType "Estimate". A call-back or reminder is jobType "Other" on that day, with the reason in note.
- update_job: change a job that exists. done "yes" when it is finished, "no" when it is not finished after all. paid "yes" when it was paid, with paymentType and, if an amount was said, price; paid "no" when payment did not happen or a check bounced. newDate and newTime when it moved. price when the price changed. jobType when the kind of work changed. note for anything to write down: a no-show, a dump fee, an extra item, a promise to pay later. Being paid on site means the work is done. Fill only what changes.
- cancel_job: the job is off. The app asks before removing it.
- new_customer: add a customer without booking work: customerName, phone, address, note.
- update_customer: a customer's details changed or there is something to remember about them: newName, newPhone, newAddress, note (gate codes, dogs, how they pay, who to ask for).
- contact_customer: call, text or get directions. contact is "call", "text" or "directions"; for a text, message is the text to send. ref can be the customer or the job.
- dumpster_dropoff: a dumpster has just been dropped off or delivered: dumpsterNumber, customerName, address, dueBack, price, agreedTons, note.
- dumpster_pickup: a dumpster has just been picked up, collected or weighed: dumpsterNumber (or the customer or address it was at) and actualTons.
- dumpster_swap: a full dumpster was taken away and an empty one left in its place: dumpsterNumber is the one taken away, actualTons its weight, otherDumpsterNumber the one left, and dueBack, price and agreedTons for the new rental when said.
- update_rental: change a dumpster that is out: dueBack (kept longer or picked up sooner), price, agreedTons, newAddress (moved on the property or to another place), note.
- dumpster_note: something about a dumpster itself, such as damage or that it should not go out: dumpsterNumber and note.

When the note asks a question, for example "which dumpsters are due back Friday", "what do we have tomorrow", "how much does Pereira owe", "what's Johnson's address" or "is a dumpster free Friday", answer it in "reply" from the records in one or two plain sentences, and return actions only if something should also be done. If the records do not hold the answer, say so.

When the note asks for something none of the actions can do, such as sending an invoice, changing a setting, undoing a change or deleting a customer, say in "reply" what was understood and the nearest thing that can be done, and return no actions.

Leave "reply" empty when the actions cover the note.

Rules for fields:
- Fill only what the note says. Use an empty string for anything not said. Never invent a name, number, price or address.
- Dates as YYYY-MM-DD, worked out from today: "tomorrow", "Friday" (the next Friday, or today if today is Friday), "next week". Times as HH:MM in 24-hour time. "This morning", "just now", "just finished" and "on site" mean today.
- Money as digits: "three hundred" is 300. Weights in tons as digits: "two point eight" is 2.8.
- jobType from the work described; nobody says "junk removal" out loud. Junk removal: clearing, emptying or cleaning out a garage, basement, attic, shed, house, estate or office, or hauling away furniture, appliances, debris or a hot tub. Demolition: tearing down or taking out a shed, deck, pool, fence, wall, kitchen, bathroom or flooring, or any mention of "demo". Dumpster drop-off, Dumpster pickup and Dumpster swap: booking those for a later day. Estimate: going to look and give a price. Other: anything else. Leave it empty only when nothing says what the work is.
- paymentType is cash, check or card. "PD cash 300" means paid, cash, 300.

Issues: list what the person should confirm before saving, each tied to an action by its position in the list (0 for the first), naming the field and asking one short yes/no question. For a new job: no date, no price, no phone number for someone not in the records, unclear kind of work, a date in the past, an address with no house number, a name or address that sounds misheard, two values said for one field. For any other action: only when it is unclear which record is meant or what should change, and for a pickup or swap when no weight was said.

Plain business language. No exclamation points.
```

## The records sent with the note (user message)

```text
Spoken note:
<the words>

Records:
Dumpsters:
- D1 Dumpster 1 (15 yard): out with C3 Harborview Realty at 300 Broadway, Taunton, MA since Sat, Oct 10; due back Sat, Oct 17 (overdue); $450; 2 tons agreed
- D3 Dumpster 3 (15 yard): in the yard. Note: cracked door
Jobs from Mon, Oct 12 to Mon, Nov 2:
- J1 Mon, Oct 19 9:00 AM · C1 Linda Johnson · Junk removal · $300 cash · not paid · not done · 42 Elm St, Taunton, MA
Customers:
- C1 Linda Johnson · 508-555-0147 · 42 Elm St, Taunton, MA · Side gate code 4412 · 4 jobs, $1,180, owes $0, last job Mon, Oct 19
  - J1 ... (that customer's last 8 jobs, each with a reference)
Totals: owed $19,550 from 31 jobs; done this week $2,140 from 6 jobs; booked today $750 from 2 jobs.
```

- References are made fresh for each note (C1, C2…, J1, J2…; D is the
  dumpster number) and kept with the request so the app can turn them back
  into records.
- Customers listed: everyone on the listed jobs and dumpsters, plus up to six
  customers the note seems to name: by phone digits, by a name word of three
  or more letters that matches a customer's last name or full name, or by a
  house number plus street word. Each mentioned customer also gets their last
  8 jobs, so questions about them can be answered.

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
  asking.
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
- dumpster_note is kept on the dumpster until changed and shown on its row and
  screen.

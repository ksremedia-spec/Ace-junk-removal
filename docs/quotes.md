# Quotes

Asked for by Ashley through Kyle, 2026-10-19: "a quotes tab for things
outstanding to keep them straight."

## In plain English

A quote is a price given to someone who has not said yes yet: on the phone,
or after an estimate visit. It stays on the Quotes list until it is booked
(it becomes a job) or lost (they went elsewhere or never called back). The
list shows which ones need a call back today, so nothing outstanding is
forgotten.

An **Estimate** job is different: that is a visit on the schedule to go and
look. A quote is the price that comes out of it, or out of a phone call.

## The record (Quote)

| Field | Meaning |
|---|---|
| customer | The person quoted. Required, chosen the same way as for a job (pick, or New customer). |
| jobType | Kind of work, same list as jobs. Default Junk removal. |
| details | What was quoted, one line: "Garage cleanout, about two loads". |
| price | Dollars, optional. |
| quotedOn | The day the price was given. Default today. |
| followUpOn | Optional day to call them back. |
| status | open, booked or lost. New quotes are open. |
| notes | Anything else. |
| job | The job it became, once booked. |
| createdAt, updatedAt | As on every record, for the later sync. |

Deleting a customer leaves their quotes without a customer (same rule as
jobs). Deleting a job leaves its quote booked, without the link.

## Screens

**iPhone:** a fifth tab, **Quotes**, between Jobs and Customers. Symbol
`doc.text`. Tab order: Today, Jobs, Quotes, Customers, Dumpsters.

**Quotes list:**
- Segmented control at the top: **Open**, **Booked**, **Lost** (like Jobs'
  Upcoming, Unpaid, Done). Opens on Open.
- Open has two sections:
  - **Follow up**: open quotes whose follow-up day is today or earlier,
    earliest first. The follow-up line is in the warning color: "Follow up
    today" or "Follow up was Fri, Oct 16".
  - **Waiting**: every other open quote, oldest quote first.
  - The list header gives the count and total: "5 open · $3,250".
- Booked and Lost: newest first.
- Row: customer name; "Junk removal · $450" (or "No price"); "Quoted Mon,
  Oct 12 · Follow up Thu, Oct 15". Details line under it in secondary text
  when present.
- Swipe from the leading edge: **Book** (opens the New Job form, below).
  Swipe from the trailing edge: **Lost**. On Booked and Lost: **Reopen**.
- Search: name, phone, address, details.
- Toolbar **+** opens a blank New Quote form.

**Quote form** (new and existing): Customer (Choose), Type, What (details),
Price, Quoted (date), Follow up (switch, then date), Notes. Existing open
quote also shows a section with **Book Job** and **Mark Lost**; a booked or
lost one shows **Reopen**, and a booked one shows its job. **Delete Quote**
at the bottom, with a confirmation.

**Book Job** opens the normal New Job form already filled in: the
customer, the type, the price, and the details as the job's notes. Saving
that job marks the quote booked and links it. Cancelling changes nothing.

**Mac:** **Quotes** in the sidebar after Jobs (Unpaid, Done), before
Customers. The middle column is the same list with the same segmented
control; the detail column is the quote form. File menu: **New Quote**
(no shortcut: ⇧⌘Q and ⌥⌘Q belong to the system). Right-click a quote:
Book Job, Mark Lost or Reopen, Delete.

## Copy

"Quote saved." "Quote marked lost." "Quote reopened." Booking ends with the
New Job form's own "Job saved." No exclamation points.

## Today line (added 2026-10-19, Kyle: "let's do it as a line on the screen")

- **iPhone Today:** one more row in the figures card at the top, under Owed:
  **Quotes to follow up** with the number of open quotes whose call-back day
  is today or earlier, in the warning color when more than zero. Shown only
  when there is at least one open quote. Tapping it opens the Quotes tab on
  Open.
- **Mac Today:** the figures line at the top of the list ends with
  " · 2 quotes to follow up" when there are any.

## The Assistant and quotes (added 2026-10-19)

Kyle: "The assistant should answer things like get a quote for 66 Johnson
Street $800 customer approved and then it goes in and marks that quote".
The Assistant now has two quote actions, **new_quote** and **update_quote**
(approved books it, declined marks it lost, or a new price or call-back
day). The contract, prompt and screens are in `assistant-actions.md`.

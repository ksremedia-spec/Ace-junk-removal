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

## Not in this change

- The Assistant does not create or update quotes yet ("quote Johnson 450 for
  the garage" would need a new action type in `assistant-actions.md`).
- The Today screen does not show quotes to follow up yet.

Both are natural next steps; ask Kyle before adding either.

# Ashley's spreadsheet: what the import has to read

From two photos Kyle took of the real sheet on Oct 21, 2026. Only the
layout is recorded here: the sheet holds real customers, and this
repository is public, so no names, addresses or amounts are copied in.

## Where it lives

- A **Google Sheet** named "2026 ACE Books", not an Excel file on her Mac.
  Kyle, Oct 21: "they use google sheets." (Confirmed; the guide's step 1
  is written for that.) Menu path checked in Google Sheets on Oct 21,
  2026: File › Download › Microsoft Excel (.xlsx). The download includes
  every tab.
  Version 1's import reads `.xlsx`, so the step is File → Download →
  Microsoft Excel (.xlsx) in Google Sheets, then File → Import in Ace.
  (Assumption to check with Ashley: one sheet per year.)
- Two tabs: **Client Job List** (below) and **Contracted Labor** (not seen
  yet; likely the crew's hours or pay, which the Labor tab covers).
- One row per job, about 450 rows by mid-April, so roughly the 600–700 a
  year in CLAUDE.md.

## Columns of "Client Job List"

| Col | Heading | What is in it |
|---|---|---|
| A | (none) | Narrow, coloured, empty. Ignore. |
| B | Date | First row "1/5/2026", then "1/5" (month/day, year left off). |
| C | Customer Name | Full names, first name only, couples ("A & B Name"), "c/o" for someone else's property, a business or short form, or blank. |
| D | # and Street Name | Usually number and street; sometimes street only, "???" in place of an unknown number, a P.O. Box, or blank. |
| E | City, State & Zip | "Town, MA 02740"; zip sometimes missing; some Rhode Island. |
| F | Price | Whole dollars. Some cells filled **red**. |
| G | Form of Payment | check, venmo, cash, cash app (also "cashapp"), or blank. |
| H | Check # | The check number when paid by check. |
| I | Not Mailing Address | "XXX" on some rows: the job address is not where to send mail. |

## What this means for Ace

- **No phone number, no job type, no time** in the sheet. Imported
  customers will have no phone; jobs come in as untimed, type "Junk
  removal" unless Kyle decides otherwise. The preview should say so
  ("614 jobs, none with a phone number").
- **Payment types:** the sheet uses Venmo and Cash App, which Ace does not
  have (it has Cash, Check, Card). Needs Kyle's decision.
- **Red price cells:** assumed to mean not paid yet. Not confirmed. The
  `.xlsx` export keeps cell colours, so the import can read them.
- **"???" house numbers:** import as the street only, flagged like the
  Assistant's missing house number.
- **Customers repeat** across rows (same name and address): the import
  groups them into one customer with several jobs.
- **Check numbers** and the **not-mailing-address mark** have no field in
  Ace yet; they can go into the job's notes for now.
- The `demo/` fake test sheet was guessed before this; its columns differ.

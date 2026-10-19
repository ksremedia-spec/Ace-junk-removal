# Test spreadsheet (fake data)

`Ace test sheet (fake data).xlsx` stands in for Ashley's own spreadsheet, so the Excel import (build
step 7, Mac only) can be tried as often as needed without her real file.

- **Everything in it is made up.** Names are random pairings, house numbers are
  invented on common street names in real South Coast towns, and every phone
  number is in the 555-0100 to 555-0199 range set aside for fiction. The
  repository is public: never put Ashley's real file, or anything copied from
  it, in here.
- **The layout is a guess** (Kyle, 2026-10-19: "reasonable test for now").
  Ashley's real column headings are not known yet. When they are, change
  `make_test_sheet.py` to match and run it again.
- Rebuild it: `python3 test-data/make_test_sheet.py` (needs openpyxl). It
  comes out the same every time, and rewrites this README with the counts.

## What is in it

Three tabs, the way a small office's workbook tends to grow:

| Tab | Layout |
|---|---|
| `2026` | A title in row 1, a blank row, headings in row 3: Date, Customer, Phone, Address, Town, Job, Price, Paid, Notes. A grey merged row starts each month. Unpaid past jobs are shaded yellow (the colour is the only sign). Cancelled jobs are struck through. A TOTAL row at the bottom. |
| `2025` | Headings in row 1, worded differently: Date, Name, Phone #, Address, Job Description, $, Pd?, Notes. The town is part of the address. A filter is on. |
| `Dumpsters` | Six dumpsters and where they are. Not customers or jobs; an import should leave it alone or ask. |

## The mess it holds on purpose

- **Names:** "Linda Johnson", "Johnson, Linda", "LINDA JOHNSON", "Mrs. Johnson",
  trailing spaces, a swapped-letter misspelling, and businesses written as
  "Cobblestone Realty Group (Dave)". The same person is often written
  several ways across rows.
- **Phones:** 508-555-0123, (508) 555-0123, 508.555.0123, digits stored as a
  number, no area code, two numbers in one cell, an "x2" extension, blank.
- **Addresses:** street abbreviations that vary, the town in the address
  column, no house number, "same" (meaning same as last time), lower case,
  town nicknames (Middleboro, NB, FR).
- **Prices:** numbers, "$1,200" typed as text, "300.00", "350+50",
  "quote 800", "300 cash", "tbd", blank.
- **Paid:** "pd cash 300", "cash", "chk 1043", "ck #1043", "CC", "sq",
  "visa", "owes", "OWES 300", "inv sent", "pd 200 cash owes 100", "y" / "n"
  on the 2025 tab, blank, and venmo or zelle (not one of the app's cash,
  check or card). Sometimes the payment is written in Notes instead.
- **Dates:** real dates, plus "10/3", "Oct 3", "10/3/26" typed as text, and
  "TBD". A few rows are out of date order (entered late).
- **Rows that are not jobs:** month headings, blank rows, the TOTAL row, and
  rows entered twice.

## Answer key (what the import should find)

Counted by the script from the made-up records, then checked against the file.

| | 2026 tab | 2025 tab |
|---|---|---|
| job rows (including duplicates) | 454 | 613 |
| exact duplicate rows | 4 | 3 |
| blank rows | 4 | 9 |
| month heading rows | 10 | 0 |
| total rows | 1 | 0 |
| cancelled jobs | 5 | 9 |
| rows with no phone number | 56 | 69 |
| rows with a phone missing its area code | 11 | 36 |
| rows with two phone numbers | 12 | 16 |
| rows with a date typed as text | 38 | 56 |
| rows dated TBD | 5 | 4 |
| rows with no price | 60 | 85 |
| rows with venmo or zelle | 8 | 12 |
| rows with part paid, part owed | 10 | 8 |
| rows with no house number | 11 | 18 |
| rows with no town | 22 | 36 |
| rows where address is "same" | 5 | 0 |
| rows with a misspelled last name | 18 | 47 |
| rows with a last name only | 16 | 20 |
| different real customers | 350 | 424 |

- Different real customers across both tabs: **609**, of whom 165 appear in both
  years. Some of them can't be told apart from the cells alone (a misspelled
  name with no phone, for example), so a good import gets close to this number
  and asks about the rest, rather than matching it exactly.
- The 2026 TOTAL row reads $190,825: the sum of the prices that are real numbers,
  typed in as a value (not a formula), so it reads the same in any program.
  Prices typed as text are not in it.

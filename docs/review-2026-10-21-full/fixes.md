# What was fixed from the Oct 21 audit (overnight Oct 21–22)

Kyle asked for all 14 must-fix items and design ideas 1–7. Status of each.
"Tested" below means where it was actually tried; nothing new here has run
on a real iPhone yet (his phone was asleep when the build was ready).

## The 14 must-fix items

| # | Problem | What changed | Tested |
|---|---------|--------------|--------|
| 1 | Live sync code inside every copy, incl. a beta | A release (beta) copy ignores the built-in server; `tools/check-before-sending.sh Ace.app` refuses any copy that has SyncServer.txt or BetaRelay.txt inside | Release Mac build checked: guard on, script refused it |
| 2 | Sample data on a synced device floods everything | Sample data and the Debug section are off whenever the app syncs with the live server; the server pauses the sheet link if one check would add >20 rows or change >25 | Server: automatic test (25 new jobs → paused, Resume → in) |
| 3 | Deleting a customer blanked their rows in the sheet | A job left without a customer never touches name/address cells | Automatic test |
| 4 | Every change rewrote all 8 cells of a row | Only the cells whose meaning changed are written; a filled cell is never blanked; the sheet's own spelling and street/city split are kept | Automatic test (notes-only edit → no cell writes) |
| 5 | A blank dumpster on a new device wiped the real board | New dumpsters are "as old as possible" so a real one always wins; "Set up 6 dumpsters" is hidden until the first download finishes | Built; not yet tried on a fresh device |
| 6 | Two devices syncing at once could skip a change | The server reports only as far as the changes it actually sent | Automatic test (30 writes during 40 reads → all 30 seen) |
| 7 | Phone locked right after a save didn't send | On going to the background the app asks iOS for time to finish sending; the wait after a save is 1 s on iPhone; "lost connection" while locking counts as offline, not a problem | Built; needs a real iPhone |
| 8 | An open job/quote page undid another device's change | Pages save only the fields typed in, and follow changes made elsewhere while open | Built; Simulator Mark-paid/Undo used it |
| 9 | Assistant kept the old address for a known customer | The said address goes first in the job's notes ("Job address: …") when it differs; customers are stamped only when something really changed | Built; not tried with a voice note |
| 10 | Excel import + sheet link would double jobs | File › Import is off once sync is on; welcome step 1 becomes "Connect the Google Sheet" | Built |
| 11 | Overweight charges couldn't be added later or fixed | Past rentals open (Dumpster and Customer pages): dates, price, agreed and actual weight, charge shown, Delete | Built. How the charge gets billed is still Kyle's decision |
| 12 | A stopped sheet link only showed in Settings | The toolbar icon turns orange with one line when the link is paused, has an error, or hasn't checked in 10 minutes | Built |
| 13 | A sort could scramble jobs | Pause when more than 10 tagged rows look edited at once | Automatic test (scrambled sheet → paused, nothing changed). The real Google sort test is still to do |
| 14 | No dated plan; Ashley's Mac unknown | Needs Ashley's MacBook model and macOS version from Kyle | Waiting on Kyle |

Server tests: `cloudflare/ace-sync/test/run-sheet-test.sh`, 32 checks, all pass; the 600-row
first connection still passes. Deployed to the live server (database column
`override` added) and its next sheet check ran with no error.

## Design ideas 1–7

1. **Mark paid asks how** (Cash, Check… with the number, Card, Venmo, Cash App), with the amount: everywhere a job can be marked paid. Seen in the Simulator.
2. **Undo bar** for 8 seconds after Done/Not done/Paid/Unpaid ("Job marked paid by Card. Undo"); ⌘Z on the Mac. Undo puts the old values back as a new change, so it syncs. Seen and tested in the Simulator (paid→unpaid→Undo→paid, checked in the data).
3. **Today as a run sheet**: a "Next" card at the top of the iPhone Calendar (name, time, type, price, address, Call when there is a phone, Directions); day cards show the street and town. Seen in the Simulator.
4. **Calm sync status**: a grey "offline" icon when there's no connection, orange only for real problems; "Updated just now" at the foot of the iPhone Calendar and the Mac sidebar.
5. **Figures open what they count**: Owed → Unpaid, Dumpsters → Dumpsters, Quotes → Quotes, with a small arrow (iPhone and Mac). Owed → Unpaid seen in the Simulator.
6. **Long-press a dumpster tile**: Call the renter, Directions, Extend 3 days / 1 week.
7. **Pull down to sync** on every iPhone tab; **View › Sync Now (⌘R)** on the Mac.

## Still open

- Install on Kyle's iPhone (it was unreachable at 12:30 AM) and try 5, 7 and 9 there.
- The real Google sort/cut/paste tag test (item 13).
- Decisions: how overweight charges and rental prices get billed; a per-job site address.
- Ashley's MacBook model and macOS version (item 14).

## Oct 23: more from the audit's "fix now" list

Sync (tested with two iPhone Simulators on the test server, by reading
their databases and the server's):
- 1: each device's sync memory belongs to one server (address + the
  server's own ID); a new or reset server starts it afresh. Live server
  checked: the Mac picked up its ID and kept its 616 jobs.
- 2: a save that changed nothing no longer blocks another device's real
  change (tested: B stamped a job "newer" with no edit, A's $999 price still
  reached B). Hours typed unchanged no longer re-stamp.
- 3: a pickup's rental gets an ID from the dumpster and drop-off time, so a
  pickup logged on two devices is one rental (built, not tested).
- 4: one record this copy can't read no longer stops syncing; it is kept
  and retried (tested).
- 6: clearing the sync memory mid-sync makes that sync drop what it fetched.
- 35: a wiped database with surviving sync memory starts afresh instead of
  deleting everything everywhere (tested: 1,716 records, 0 deleted); more
  than 20 deletions at once are held back until confirmed in Settings ›
  Sync (tested: 25 held, orange icon).

Sheet link (server tests now 35 checks, all pass; 600-row test passes):
- 26: one check at a time (a lease); if the sheet changed while a check
  ran, it writes nothing and tries again next minute; an edit made during
  a write is no longer skipped.
- 28: "Total Property Management" is a customer (only "Total"/"Totals" is a
  totals line, in the import too); "No name" is never written into her
  sheet and matches a blank name.
- 30: a renamed or moved heading pauses the link (tested).
- 31: a timed job's end moves with its date; a job typed for today is not
  marked done; a sign-in without Ace's state token is refused (tested).

Money and Assistant (built for iPhone and Mac; not run through the Assistant):
- 7, 8: Clear all data on a synced device leaves the shared calendar alone;
  the import's "remove example data" switch never shows once sync is on.
- 9: a swipe down can't throw away a note being worked on or a filled job;
  the note is kept until its changes are saved.
- 10: Venmo and Cash App said for a new job are kept.
- 11: a drop-off with no agreed weight or price is flagged.
- 13: weights: "5600", "5,600 lb" → 2.8 tons; "2,8" → 2.8 (checked).
- 14: "X paid" goes to X's job that's done and owed first; a lower amount
  with "paid", or a future job, is flagged.

Deploy note: database changes must be applied before deploying the server;
on Oct 23 the live server failed for about a minute until they were.

Not done from "fix now": 5, 12, 15–25, 27, 29, 32–34, 36–49 (most are
Mac/iPhone polish, Google Calendar, labor, docs).


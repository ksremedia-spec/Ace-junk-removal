# Keeping the iPhone and the Mac in step (build step 5)

Design written Oct 21, 2026, before the code. Kyle: "start building the
Cloudflare sync between phone and Mac, running on my Mac first with fake
data." The Google Sheet link (`google-sheet-sync.md`) plugs into the same
server later.

## In plain English

- Every phone and Mac keeps its own full copy, so Ace still works with no
  signal. When it can, it sends what changed to Ace's server and brings
  back what the others changed.
- It checks about every 30 seconds while Ace is open, a couple of seconds
  after anything is saved, when Ace opens, and when it comes back to the
  front.
- When the same record was changed on two devices, the later change wins
  (the rule Kyle chose for the sheet, Oct 21).
- A deleted record is deleted everywhere.
- Each business has one sync code, entered once per device in Settings
  (kept in the Keychain, like the Claude key). Anyone without it gets
  nothing from the server.
- First it runs on Kyle's Mac with fake data (the "local" server, Cloudflare's
  developer tool). Then on Kyle's Cloudflare account, then the client's.

## What is synced

Customers, jobs, dumpsters, dumpster history (rentals), quotes, crew and
crew hours: the seven record types in `Ace/Data`. Plus one shared settings
record (added Oct 24, audit findings 4 and 36): the overweight rate per ton
and the salaried crew's working days. Not synced:
- each device's own choices (last tab, calendar view, Assistant model,
  the unsent Assistant note, the welcome guide having been seen);
- calendar links (`calendarItemID`, `calendarWrittenAt`): each device's
  own calendar bookkeeping. Changes that arrive from another device do not
  write calendar events, so two devices never both write the same event.
  **Open:** which device writes a job's Google Calendar event once both
  are in use. Today, whichever device saves the job writes it.

**The shared settings record** (type `setting`, one record, ID
`FFB30D3F-7D27-5DA8-B403-87C81300D326`, worked out from the name
"settings"). Its fields: `{"overweightRatePerTon": 150, "salaryDays":
[2,3,4,5,6,7]}` (weekday numbers, 1 is Sunday). A field left out was never
set on any device, so each device keeps its own default ($125, Monday to
Saturday). Changing the rate in Settings stamps the record and sends it; the
later change wins, as for records. Opening Settings or typing the same value
does not count as a change. A device sends nothing until the rate or the
days are changed somewhere. Rentals still keep the rate they were picked up
with. The salary days have no screen to change them yet; the code that
changes them (`AppSettings.setSalaryDays`) already stamps and sends. The
server must list `setting` in its allowed types, or it refuses the whole
sync with "Unknown record type".

## The sync icon (Kyle, Oct 21)

A small icon in the toolbar (Mac: next to Settings; iPhone: top left of
every tab): a check mark when everything is sent and received, turning
arrows while sending, an orange warning sign when the server cannot be
reached or the sync code is wrong. Click or tap for one line ("Up to
date", "Last synced 20 seconds ago") and Sync Now. Hidden until sync is
set up. Code: `Ace/Sync/SyncStatusButton.swift`. Seen Oct 21 on the Mac
and the iPhone Simulator (check mark, the detail, the warning with a
wrong code).

## How it works

**Server** (`cloudflare/ace-sync`, a Cloudflare Worker with a D1
database). One table, `records`: record type, record ID, last-changed
time, deleted yes/no, the record's fields as JSON, and a running number
(`seq`) that goes up by one on every accepted change. One request,
`POST /v1/sync`:
- the device sends the records it changed since its last sync and the
  last running number it has seen;
- the server keeps each incoming record only if it is newer than what it
  has (one SQL statement per record, all in one batch, so the running
  numbers never clash), then sends back every record with a higher running
  number, oldest first, up to 200 at a time (`more: true` means ask again).
  A device sends at most 40 changes per request: Cloudflare's free plan
  allows 50 database queries and 10 ms of CPU per request.
- The sync code is checked on every request (`Authorization: Bearer`).
  On the server it is a secret (`SYNC_KEY`); locally it lives in the
  git-ignored `.dev.vars`.

**Device** (`Ace/Sync/`).
- Every record gets a permanent ID. Jobs already have `jobID`; the other
  six get `syncID`, given when the record is made and filled in on the
  first sync for records made before.
- Two IDs are worked out instead of random, so two devices that make "the
  same" record do not end up with two: dumpster N always has the same ID
  (both devices clicking Set up 6 dumpsters gives six, not twelve), and a
  crew member's hours for one day always have the same ID.
- A rental's ID comes from the dumpster number and the drop-off date.
  Two rentals of one dumpster dropped off the same day would share it, so
  the second one found is given its own random ID before the sync (Oct 24,
  finding 27). Rentals that already have their own ID keep it.
- What changed: the device remembers, per record, a fingerprint of what it
  last sent or received. A record whose fingerprint differs is sent. If a
  screen changed a record without stamping its "last changed" time, the
  sync stamps it at that moment, so no edit is lost.
- What was deleted: the device remembers which IDs it has synced. An ID
  that was synced and is no longer in the database was deleted here, so a
  deletion is sent. This catches every way of deleting, including a
  dumpster's history going with the dumpster, without changing each
  delete button.
- Incoming records are applied in an order that keeps links whole
  (customers and crew first, then dumpsters, jobs, quotes, rentals,
  hours). Links between records travel as IDs ("this job's customer is
  …").
- Its own bookkeeping (last running number, fingerprints, synced IDs)
  is a small file next to the database, not in it.

## Testing on Kyle's Mac (no Cloudflare account)

- Node.js 24.21.0 in `~/.ace-tools/` (downloaded Oct 21 with Kyle's OK,
  checksum checked) and Wrangler 4.148.0 in `cloudflare/ace-sync`
  (`node_modules`, not committed).
- `npm run dev` in `cloudflare/ace-sync` runs the server at port 8787 with
  its database in `.wrangler/` (not committed).
- Debug-only launch switches point an app at it:
  `-sync.url http://localhost:8787 -sync.key <the code in .dev.vars>`.
  The Simulator reaches the Mac as `localhost`; a real iPhone on the same
  Wi-Fi uses the Mac's address.

## Safety

- Nothing is sent without the sync code; the code never goes in the code
  or the repo.
- A device that has never synced and already holds records (for example
  the beta's example data) sends them; a device that starts empty only
  receives. Example data on two devices would show up twice, so tests
  start one device empty (`-debug.empty`).
- A device that had synced with one server and then meets another (a new
  address, or the same address after the server was wiped and given a new
  ID) does not send what it holds (Oct 24, finding 5). The first request
  after Ace opens carries no changes, so the new server is noticed before
  anything reaches it. What the new server has replaces the device's copy;
  everything else on the device is held. Settings › Sync then says "412
  records on this device are not on the sync server" with two choices:
  Send to Every Device, or Remove from This Device (both ask first; removing
  also brings everything down from the server again). Changing the
  overweight rate meanwhile sends the new rate. A device that never synced
  anywhere behaves as before.
- More than 20 deletions in one sync are held until confirmed in Settings ›
  Sync. Crew hours and dumpster history don't count towards the 20: they go
  with their person or dumpster (Oct 24, finding 51).
- If every record on a device is gone but its sync memory is not, Ace takes
  it as a replaced database and starts afresh instead of deleting
  everything everywhere. Known limit, left as is for version 1 (Oct 24,
  finding 52): a device that really deleted all of its last records (20 or
  fewer, dumpsters included) gets them back from the server, and the other
  devices keep them.
- A job, quote, rental, dumpster or day of hours that arrives linked to a
  record not on this device is applied with the link empty and tried again
  on every sync until the linked record arrives (Oct 24, finding 53).
- What the server keeps of a deletion (corrected Oct 24, finding 43): a
  record deleted on a phone or Mac is kept on the server only as its type,
  ID and "deleted"; its fields (name, price, notes) are gone. Nothing is
  kept for 30 days and there is no undo. A job deleted that way also leaves
  Ashley's sheet; the only way back is the sheet's own File › Version
  history, which brings the row back as a new job. (A row deleted in the
  sheet keeps its job's fields on the server.)

## Test results (Oct 21, 2026, on Kyle's Mac)

Two iPhone Simulators (17 Pro Max "A", 17e "B") and the local server.
Checked by reading each Simulator's database and the server's directly:
- A started with the example data and sent all 1,716 records (606
  customers, 1,044 jobs, 6 dumpsters, 20 rentals, 6 quotes, 5 crew, 29
  days of hours) with no duplicates (the running number ended at exactly
  1,716).
- B started empty and received all of them; every link (job → customer,
  rental → dumpster, hours → person, quote → customer) and the totals
  ($570,405 in prices, 992 paid jobs) matched A. Nothing bounced back.
- A job marked paid with a new price, and a deleted quote, on B reached A
  within 40 seconds while A was open.
- The same job changed on both: the later change won on both devices,
  in both orders.
- Server: refuses a wrong or missing sync code, keeps the newer of two
  changes, ignores an older one.

Mac app and Simulator A (same night, Kyle's Mac copy of Ace erased with
his OK):
- The Mac app started empty and received every record; its totals
  matched A exactly (1,044 jobs, $571,089, 993 paid, 5 quotes).
- Clicking Mark paid on a job in the Mac app reached the server at once
  and Simulator A on its next sync.
- A customer's phone number changed on A reached the Mac in about 22
  seconds, and the Mac's open job page showed the new number by itself.
- Once, Ace was found not running on Simulator A (no crash report);
  bringing it back to the front synced at once. Cause unknown.

**Real devices on the live server (Oct 21–22, night, verified):** the
server runs on Kyle's Cloudflare account (Worker `ace-sync` with its D1
database), with the address and sync code built into the app
(`Ace/Support/SyncServer.txt`, git-ignored). Kyle's real Mac and real
iPhone 16 Pro Max, plus the real Google test sheet connected to the live
server:
- the first sheet check on Cloudflare read all 613 rows in under half a
  second with no error (the free plan was enough at this size);
- the Mac and the iPhone each filled with 613 jobs and 493 customers and
  matched job for job (same fingerprint);
- Mark paid tapped on the real iPhone reached the Mac at once and cleared
  the red in the sheet;
- a price typed in the Google Sheet reached the Mac in about 40 s and the
  iPhone shortly after;
- three new customers' jobs typed into the sheet reached both in about
  2 minutes; both copies matched again (616 jobs).
- Bug found and fixed on the real iPhone: a first download cut short left
  the phone sure it had records it never saved; the "caught up" mark is
  now saved only after the records are.

**Not tested yet (live):** two devices syncing at the very same moment,
a long stretch with no signal, Alex's iPhone, Ashley's MacBook.

**Earlier, not tested at the time:**
- An edit made by tapping on the iPhone (the Simulator was waiting for
  Kyle's permission to be tapped); phone-side edits were written straight
  into its database, which also tested the "changed without a new time"
  path. The Mac-side edit was a real click.
- A real iPhone over Wi-Fi. It needs `NSAllowsLocalNetworking` (Apple:
  plain http to an IP address is blocked by default since iOS 17) and
  `NSLocalNetworkUsageDescription` (the "local network" question). The
  ATS setting cannot be set through this project's build settings, so it
  needs a small Info.plist file merged in. Not needed for the real
  server, which is https.
- Two devices both clicking Set up 6 dumpsters (designed to give six,
  not twelve; not tried).
- Cloudflare's real servers (free plan: 50 queries and 10 ms CPU per
  request, 100,000 requests a day; the 40-change groups are sized for it).


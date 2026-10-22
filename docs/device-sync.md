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
crew hours: the seven record types in `Ace/Data`. Not synced:
- each device's own choices (last tab, calendar view, Assistant model,
  the unsent Assistant note, the welcome guide having been seen);
- calendar links (`calendarItemID`, `calendarWrittenAt`): each device's
  own calendar bookkeeping. Changes that arrive from another device do not
  write calendar events, so two devices never both write the same event.
  **Open:** which device writes a job's Google Calendar event once both
  are in use. Today, whichever device saves the job writes it.
- Later: the overweight rate in Settings (a shared business setting).

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
- The server keeps deleted records as "deleted" rows, so a mistake can be
  looked up and undone by hand.

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

**Not tested yet:**
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


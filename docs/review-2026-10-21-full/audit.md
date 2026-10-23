# Full audit, Oct 21 2026: iPhone, Mac, sync, Google Sheet link and the reasoning behind them

How it was done: twelve reviewers each read the code, docs and screenshots for one area: device sync, the Google Sheet link, data and import, the Assistant, jobs/customers/quotes, dumpsters and labor, the calendar, the Mac app, security, the plan against the code, iPhone design and Mac design. Two skeptics checked every finding: one for the facts, one for whether Alex or Ashley would really hit it. Only findings both accepted are below, about 250 of them (my rough count), merged where several areas found the same problem. Eleven were dropped (last section). Five critics scored the app: Ashley, Alex, an Apple-style designer, a field-service software consultant and a fresh-eyes polish reviewer. I re-checked the top 10 items in the code myself, and those are marked *(checked)*.

This was a read-only review, based on code and notes; the notes were behind on the live test (corrected above). Nothing was built, run or launched. The live sync server was not contacted, and the four files that hold codes were not opened. Their presence was checked with `git check-ignore` only. The screenshots are from Oct 19–20, before the sync, sheet-link and sync-icon work. Nothing here has been seen on a real iPhone.

**Score: 6.5 out of 10** (the critics gave 6, 6, 7, 6.5 and 7).

Ace looks and feels like a calm, real Apple app on both devices. The dumpster tiles, the Mac week board and the shared colour rules are its best work, and nothing about it reads as AI. Device sync is built carefully: running numbers can't collide, a cut-off download repeats safely, and deletions are kept on the server. Correction (Claude, after the report): the reviewers read the project's notes, which had not yet recorded the live test. Sync *was* run on Kyle's real iPhone and real Mac through the live Cloudflare server and the real Google test sheet the same night, and they stayed in step (see docs/device-sync.md, "Real devices on the live server"). What has not been tested live is two devices syncing at the very same moment, which is item M6. Several ways of losing or polluting real data are still open, and most come from how sync meets the rest of the app, not from the sync engine:

- A Debug button that ships to Ashley and Alex.
- Blank dumpsters that overwrite real ones.
- A sheet link that rewrites or blanks cells in Ashley's books.
- The live sync code packed as plain text inside every build, including the next beta.

The money path also isn't closed. The overweight charge and dumpster rental prices never reach Owed or the sheet, and Mark paid doesn't record cash or check. Most fixes are small. Section 1 is what has to happen before the app goes onto anyone's phone or out as another beta.

---

## 1. Before handing it over (must do)

### The blockers

**M1. The live sync code is packed into every copy of the app, including the next beta** *(checked)* (critical)
Whoever has a built Ace.app can right-click it, choose Show Package Contents and read the server address and sync code. That code can read, change or delete every customer, job and dumpster, and through the server, Ashley's sheet. Beta.isBeta is still true. A beta built from this folder would skip the example data and download the real books, and anything a tester typed would go into them. HANDOFF's pre-release note mentions BetaRelay.txt but never SyncServer.txt. The Oct 20 DMG predates the file, so nothing has leaked yet (judged by file dates; the DMG was not opened).
How: In `SyncEngine.builtIn`, add `guard !Beta.isBeta else { return nil }`. Add a Run Script build phase that fails when `Beta.isBeta` is true and `Ace/Support/SyncServer.txt` is present (the synchronized folder has no exceptions, so the file always goes in). Before any DMG leaves your Mac, look in Contents/Resources for SyncServer.txt and BetaRelay.txt. If a copy with the code ever goes out, change SYNC_KEY on the Worker and type the new code in Settings › Sync on each device (Settings overrides the built-in file). Fix the wording in docs/device-sync.md:106 ("the code never goes in the code").

**M2. "Load sample data" (and `-sampledata`) on a synced device pushes about 1,700 fake records everywhere, including Ashley's sheet** *(checked)* (critical)
Settings › Debug is shown on every build, the Mac included. Load sample data clears the device, makes sync forget what it sent, then loads about 600 example customers and their jobs. The next sync sends all of them as new records, so they reach every device. If the sheet is linked, every example job is also inserted as a row in her real sheet, because nothing limits additions. Only rows vanishing pause the link. The six example dumpsters share IDs with the real ones and carry a newer time, so they overwrite the real board. "Clear all data" can't undo it, because it also forgets and sends no deletions. The automatic beta loader already guards against this (Beta.swift:46). This button and the `-sampledata` launch switch don't. HANDOFF checklist step 3 tells you to tap this button.
How: Wrap the Debug section in SettingsView in `#if DEBUG`, or show it only when `Beta.isBeta && !SyncEngine.shared.isSetUp`. Make `SampleData.load` return early when sync is set up. Wrap `-sampledata` in both `handleLaunchArguments` (MainView, MacMainView) and `WindowSnapshot` in `#if DEBUG` and skip them when synced. On the server (google.js step 2), pause the link with a plain reason when one run would insert more than about 20 rows or rewrite more than about 25. Fix HANDOFF checklist step 3.

**M3. Deleting a customer blanks their name and address on every one of their rows in Ashley's sheet** *(checked)* (critical)
"Their jobs are kept without a customer" means each job is re-sent with no customer. The server then rebuilds each row with an empty name and address, and an empty value clears the cell. If a row also had no price, it now looks blank, is treated as deleted, and the job is deleted in Ace too. Tidying a duplicate customer is ordinary work, so this will happen.
How: In google.js step 2, skip the name, street and city writes when the job has no customer. In `cellWrites`, never write `{}` over a cell unless that field actually changed in Ace (see M4). Add a test that deletes a customer and checks the rows keep their names.

**M4. Any change in Ace rewrites all eight cells of the row, overwriting what Ace can't hold** *(checked)* (high)
The plan's rule says "only the cells that changed are written." The code writes date, name, street, city, price, payment, check # and not-mailing every time, even when the edit was only a phone number, which isn't in the sheet. What this does on real rows:
- A blank street with "Taunton, MA 02780" becomes street "Taunton" and city "MA 02780".
- A blank name becomes "No name".
- A payment word Ace doesn't know is cleared.
- A second check number is cut.
- Any mark in not-mailing becomes "XXX".

Changing a repeat customer rewrites all of their past rows.
How: Store the last-written row values in `sheet_rows` (not just a hash), and send `updateCells` only for columns whose value changed. Never write an empty value over non-empty text. Keep the sheet's street and city as read, rather than re-splitting Ace's address at the first comma.

**M5. A blank dumpster made on a new or cleared device wipes the real dumpster board on every device** *(checked)* (high)
`Dumpster.init` stamps "changed now", and dumpster N has the same sync ID everywhere. "Set up 6 dumpsters" shows whenever the local list is empty: a new phone before its first download finishes, no signal, or after Clear all data. The Mac welcome guide tells Ashley to click it. The blank "in the yard" copies win, and everything out (customer, location, due date, price, agreed weight) is lost everywhere. Tapping during the first download can also leave twelve dumpsters, six of which never sync.
How: In `Dumpster.init` (and `clearForImport`), set `updatedAt = Date(timeIntervalSince1970: 0)`, so any real copy wins. Hide the button while `SyncEngine.shared.isSetUp && lastSynced == nil` and show "Getting dumpsters from the other devices…". Rewrite welcome step 2.

**M6. A change can slip past a device for good when two sync at once** *(checked)* (high)
The server reads the page of changes in one query and "you're up to number N" in a separate one. A save landing between the two is counted in N but never sent, and the device never asks again. The icon shows a check mark.
How: In index.js, return `latest: page.length ? page[page.length-1].seq : since` and drop the `MAX(seq)` query. Add a test with two interleaved writers.

**M7. On iPhone, a pickup or drop-off saved just before pocketing the phone isn't sent until Ace opens again** *(checked)* (high)
Sync waits 3 seconds after a save and only runs while Ace is on screen. Nothing in Ace/ asks iOS for background time. Ashley's Mac keeps showing the dumpster out, maybe for hours. A request cut off by the lock shows "Could not reach the sync server."
How: When scenePhase becomes `.background`, run `syncNow()` inside `UIApplication.shared.beginBackgroundTask`. Shorten the delay to about 1 second on iPhone. Treat `URLError.cancelled` or `networkConnectionLost` while backgrounded as "try again", not a problem.

**M8. A job or quote page left open (Mac inspector, or iPhone) quietly undoes another device's change** *(checked)* (high)
The page copies the job once when it opens and refreshes only Done and Paid. If Alex changes the price or date, and Ashley then types anything and clicks away, every field is written back with a newer time, and his change is gone on every device and in the sheet. Quotes work the same way. The Oct 21 sync test only checked the customer's phone number, which is read live and doesn't cover this.
How: In `JobEditView.persist` and `QuoteEditView`, write only the fields that differ between `form` and `original`. Add `.onChange(of: job?.updatedAt)`: if `!hasChanges`, reload `form` and `original`; otherwise refresh only the untouched fields.

**M9. A job or quote for a known customer at a different address keeps the old address and drops the one said** *(checked)* (high)
"Harborview Realty, cleanout at 12 Pine St" saves under Harborview's 300 Broadway, because the spoken address is used only when the customer's address is empty. A job has no address of its own. The crew can go to the wrong house. Realtors and landlords are common customers, and Ashley's sheet has a "Not Mailing Address" column for exactly this.
How: In `JobReviewView.performSave` and `NewQuoteView.save`, when the spoken street differs from the street on file, ask one question: "Use 12 Pine St for this job only / Change Harborview's address / New customer". At minimum, copy the spoken address into the job's notes. A per-job site address is in Decisions.

**M10. Importing the Excel file while sync or the sheet link is on duplicates jobs in Ace and in her sheet** (high)
The welcome guide's step 1 still says download the .xlsx and import, and never mentions Connect Google Sheet. The import only checks this Mac's own records. If the first download hasn't finished, if a row changed since the download, or if a row has a blank name, the import makes new copies. The server then writes them into her sheet as new rows.
How: When `SyncEngine.shared.isSetUp`, disable File › Import and the guide's Import button with "Jobs come in from the Google Sheet." Make welcome step 1 "Connect your Google Sheet" (opens Settings › Google Sheet). Keep the import only for an unsynced copy.

**M11. The overweight charge (and the dumpster rental price) never reaches a bill, and can't be added or fixed later** (high)
The charge is worked out at pickup and stored on the rental only. Owed, Unpaid, the customer balance and the sheet count jobs only. If Alex marks a dumpster picked up with no weight, which is likely when the weight comes from the scale ticket later, the charge is gone for good. Past rentals can't be opened, and the Assistant answers "Nothing to pick up". A typo (28 for 2.8) stays in history and the month total. How it gets billed needs your call (Decision 1). The correction part doesn't.
How: Add a small RentalRecordView, opened from Past rentals rows (DumpsterDetailView, CustomerDetailView), with editable actual weight, agreed weight, price and pickup date, plus Delete with a confirmation; set `updatedAt` on edit. In Assistant pickup matching, when the dumpster is in the yard and its latest rental has no weight, offer "Add the weight to the last rental".

**M12. When the sheet link stops (paused, Google sign-in expired, Cloudflare stopped a run), nothing outside Settings says so** (high)
The toolbar icon shows only device sync, so it keeps a check mark while her sheet and Ace drift apart. The iPhone footer still promises "within a minute or two". A run Cloudflare stops for CPU never records an error.
How: Return the link's `paused` and `lastError` in each `/v1/sync` reply, or have SyncEngine fetch `sheet("status")` every few minutes. Show the orange icon with one plain line ("The Google Sheet stopped syncing. Open Settings."), and flag "not checked for over 10 minutes".

**M13. The hidden row-tag test the plan put first was never run, and nothing stops a sort from scrambling jobs** (high)
If a sort leaves the hidden tags where they were while the contents move, every tagged row looks "edited in the sheet". Each job then takes another row's date, price and paid status. No row vanishes, so the 10-row pause never fires. The plan's read-only stage and its week on a copy weren't built either.
How: Run the ten-minute tag test on the ace-test sheet (sort A–Z, sort by date, cut/paste, drag, undo) and record it in docs/google-sheet-sync.md. Add a second guard next to MAX_DELETES: pause when more than about 10 tagged rows change in one run, or a tagged row changes both name and date. Add a `mode` (preview, read, both) on `google_link`, so the real sheet starts read-only with a summary on the Mac.

**M14. The Oct 31 plan isn't written down, and Ashley's Mac may not be able to run Ace** (high)
Ace needs macOS 26, and Ashley's MacBook model and macOS version are unknown. If it can't run macOS 26, her main tool won't open. Both iPhone models and device IDs, needed for Ad Hoc, are unknown. Nothing has been installed on any iPhone. Apple's speech engine, MapKit address completion and the Lock Screen/Action button entry have no code. The sheet doc itself said writing to the real sheet is "early to mid November". HANDOFF's next steps still start with "Get it running on Kyle's Mac".
How: Get Ashley's Mac model and macOS version first, then both iPhone models and UDIDs. Write a dated plan and a cut list in HANDOFF section 8 and docs/decisions.md (Decision 12).

### Handover checklist

Each line comes from the findings or the docs. Suggest writing it as docs/handover-checklist.md and linking it from HANDOFF section 8.

1. **Beta off:** `Beta.isBeta = false`; delete `Ace/Support/BetaRelay.txt`; delete the `ace-beta-relay` Worker once the beta ends. Until then, set and record a low spending limit on that Anthropic key, because the relay has no password and its address is guessable.
2. **Live code only in Ashley's and Alex's build:** SyncServer.txt never in a beta or tester build (M1). Check Contents/Resources before any DMG goes out.
3. **Debug hidden:** the Debug section and `-sampledata` are gone from their build (M2). Close HANDOFF open question 7 with a dated decision.
4. **Clean live server:** empty the test data off the live server. A fresh D1 database plus a new SYNC_KEY and a new SyncServer.txt is cleanest, since the current code has been used in test builds and on the command line.
5. **Reset test devices:** delete `ace-sync-state.json` (or run `forget()`) on your Mac and every Simulator that synced with the local test server. Otherwise they skip live records and won't upload some of their own, because sync's memory isn't tied to a server.
6. **Test sheet disconnected:** disconnect the ace-test sheet from the live server before the real one is connected.
7. **Google project published:** publish it "In production" in the agreed account. Settle whether a privacy-policy link is needed: decisions.md says yes, google-cloud-setup.md says leave it empty. Press Publish and see what Google asks for. Add the live server's `/google/callback` to the redirect URIs. Have Ashley connect only *after* publishing, because a token issued in Testing mode still ends after 7 days. Replace the test client ID and secret on the live Worker.
8. **Real sheet, carefully:** run the tag test (M13); ask Ashley the red-price question (Decision 5); connect in read-only or preview mode first, with you present; compare the job count and unpaid total with her own.
9. **Overweight rate on every device:** set it, along with salaried days once that has a screen, and do a test pickup on Alex's phone. Confirm the real rate with Alex: $125 is a placeholder.
10. **Devices:** Ashley's Mac on macOS 26; both iPhones registered for Ad Hoc with Developer Mode on; build from Product › Archive (Release), not Run.
11. **Anthropic key:** decide whose account and how the key gets onto each device (Decision 9).
12. **Workers plan:** decide free or $5 paid before the real sheet is connected. The free plan's 10 ms CPU limit is untested at 600 rows, and a stopped run leaves no error.
13. **Commit the uncommitted work** with your OK, all in one commit, since index.js now imports google.js. That's google.js, sheet.js, migration 0002, tests, SheetLinkSection, SyncStatusButton and docs. First replace your test Gmail address and project ID in docs/google-sheet-sync.md:24-26: the repo is public. Note in device-sync.md which commit is deployed.
14. **One real-server run on record:** a short session against the live Worker with fake data, your Mac plus your iPhone on cellular, with results written into device-sync.md.

---

## 2. Fix now (safe, no decision needed)

Medium items first, then low. Each is small unless noted.

**1. Sync's memory isn't tied to a server.**
What happens: a device that synced with one server and then talks to another quietly misses records and never uploads some of its own.
Who hits it: your Mac and the Simulators, when they move from the test server to live.
How: Store the server URL, plus a server ID returned by the server (a random UUID in a one-row table), in `SyncState`; reset `since` and `known` when either changes. Have the server reply `reset: true` when `since > MAX(seq)`.

**2. A save that changes nothing makes a device ignore another device's real change, for good.**
What happens: the device skips incoming changes whenever its copy is "newer", even when it has nothing to send. Booking a voice job for an existing customer, typing hours (the worker gets re-stamped), or tapping Save with nothing edited all bump the time. Alex's phone-number fix or Ashley's pay-rate change is then never applied on that device. A later real edit there can even push the stale copy everywhere.
Who hits it: anyone editing while the other device is offline, most likely Alex in the truck.
How: In `SyncEngine.run`, skip an incoming change only when the local fingerprint differs from `state.known[key].fingerprint`. Stop stamping `updatedAt` when nothing synced changed: `Labor.setHours`/`setWorked` (return early when the value is unchanged, and don't touch `worker.updatedAt`), the three Assistant save paths, and `JobFormData`/`CustomerFormData.apply` when nothing changed. Stamp DumpsterDetailView and WorkerPage from the field's own Binding setter, not from onChange.

**3. An offline pickup can be undone by a later edit elsewhere, then logged twice.**
What happens: the dumpster record syncs as a whole. Ashley's later due-date edit flips a picked-up dumpster back to Out, while the rental entry also arrives. Picking up again doubles the history and the charge.
Who hits it: Alex picking up with no signal while Ashley edits that dumpster.
How: Give each rental a fixed ID from `dumpster number + droppedOffAt` (name-based, like dumpsters), set in `markPickedUp`. In `SyncSnapshot.apply(.dumpster)`, refuse to revive a rental that already has a RentalRecord with the same `droppedOffAt`, and re-stamp it so the fix goes back up.

**4. One unreadable record stops all syncing on that device with "Could not reach the sync server".**
Who hits it: a device on an older copy of Ace once a field is added, or a writer bug.
How: Wrap each `snapshot.apply` in do/catch; keep failures in a "could not read" list in `SyncState` and continue. Give decode errors their own text ("1 change could not be read. Update Ace."). Validate required fields per type on the server.

**5. Write down the rule for adding fields later.**
What happens: an older phone editing a record wipes fields it doesn't know about, an upgrade re-sends everything stamped "now", and a new required field breaks decoding.
Who hits it: everyone, at the first version 2.
How: In docs/device-sync.md: new fields are always optional and decoded with `decodeIfPresent`. Add a `schema` number to `SyncState`; when it changes, recompute fingerprints silently without sending.

**6. Clearing or creating records while a sync is running can crash the app, duplicate dumpsters, or delete records on other devices.**
Who hits it: Clear all data, sample data or an import pressed mid-sync.
How: Give `SyncEngine` a generation counter that `forget()` bumps; `run()` checks it after every `await` and drops its results if it changed. Re-read the snapshot after the network round trip and skip models where `isDeleted` is true or `modelContext == nil`. Disable Import and Set up 6 dumpsters while `isSyncing` on a device that hasn't finished its first sync.

**7. "Clear all data" says it can't be undone, then everything comes back, and it deletes the shared calendar events.**
What happens: clear removes every job's event from the shared Google calendar, and the jobs that come back are never written again. The spec says Clear all data touches no calendar.
Who hits it: anyone clearing a synced device.
How: When sync is set up, don't call `jobDeleting` in `SampleData.clear`. Change the text to "Removes everything from this device. It comes back from the other devices at the next sync."

**8. "Remove the example data first" in the import deletes everything on the Mac, and is on by default.**
What happens: the flag that shows the switch never resets except through the import.
Who hits it: a Mac that ran an earlier beta.
How: Set `examplesLoaded = false` inside `SampleData.clear`; never show the switch when sync is set up; give `clearForImport` epoch-dated dumpsters (M5).

**9. A swipe down on the Assistant throws away a filled-in, reviewed job; the Oct 20 fix #3 was only half done.**
Who hits it: Ashley dictating during a call, and anyone with a multi-step note.
How: Add `.interactiveDismissDisabled(phase == .steps || phase == .asking || phase == .transcribing)`. In `.steps`, Cancel asks "Discard this job?". Clear `unsentNote` in `finishAll()`, not when Claude answers. Cancel the in-flight ask Task in onDisappear. Keep a short list of unsent notes rather than one slot.

**10. Venmo and Cash App said for a new job become "Not set"** *(checked)*.
How: Delete `JobReviewView.payment(from:)` and use `JobDraft.paymentType(from: draft.paymentType) ?? .unknown` on line 83.

**11. A dumpster drop-off saves with no price or agreed weight and no warning, so the overweight charge later silently shows "—".**
How: In `DumpsterDropoffView.init`, flag `agreedTons` and `price` when `Parse.tons`/`Parse.money` give nil ("No agreed weight was said. The overweight charge needs one."), and ask yes/no before saving with either empty. Add the rule to docs/assistant-actions.md and the prompt, then run check-contract.py.

**12. A swap saves with no weight without asking, unlike a pickup.**
What happens: the charge is lost for good. The swap also always uses today for the drop-off.
How: Add the same `confirmNoWeight` dialog to `DumpsterSwapForm`, and use the action's date when one was said.

**13. A weight typed in pounds or with a decimal comma becomes a huge charge.**
What happens: 5600 is read as 5,600 tons, about $700,000.
How: Give `Parse.tons` its own rules ("lb/lbs/pounds" divided by 2000; a lone comma followed by 1–2 digits is a decimal point). On every pickup and swap form, ask when the weight is over about 15 tons ("Was it 5,600 pounds (2.8 tons)?").

**14. "Paid" can land on the customer's next booked job, and "Paid 250" overwrites a $300 price.**
How: For a payment-only update, look among done-and-unpaid jobs first, then today's, then future ones. Flag a future job ("This job is booked for Tue, Oct 27. Mark it done and paid now?"). Flag the price row when the new price is lower than the old one and paid is yes ("Job was $300. Paid in full, or $50 still owed?"). Change docs/assistant-actions.md first (price on update_job means the new total), then the prompt, then run check-contract.py.

**15. A different person with the same last name is picked without asking.**
How: Return a match kind from `AssistantMatching` (exact, all words, last name only). For last-name-only or address-only matches, always show the Which-customer list, or flag the row ("Said Linda Johnson; on file: Mike Johnson").

**16. On iPhone, Mark done or Mark paid on a job opened from Upcoming, Unpaid or Not marked done may close the page.**
How: Switch job rows to `NavigationLink(value: job)` with one `.navigationDestination(for: Job.self)` on the Jobs and Calendar stacks, as QuotesView does. Check it in the Simulator.

**17. Leaving a job page throws away every edit when the end time is before the start or the job has no customer.**
How: Extend the iPhone Back interception to cover `hasChanges && (!form.endIsValid || form.customer == nil)`, with "Fix it / Discard changes". On the Mac, save everything except the bad end time and say so.

**18. A record deleted on another device while its page is open keeps a dead page that may crash; on the Mac, deleting a job from its own page leaves it on screen.**
How: Add `onDeleted` to JobEditView and pass `{ selectedJob = nil }` and `{ selectedCalendarItem = nil }` from MacMainView. After each sync save, clear any selection whose model `isDeleted` or has `modelContext == nil`. Guard `persist()` and the onChange handlers the same way, and on iPhone show "This job was deleted on another device." and dismiss.

**19. Mac menu commands fire in every open window, and a second window mirrors the first's sidebar.**
What happens: ⌘N opens New Job in each window; ⇧⌘A opens two Assistants.
How: Replace the NotificationCenter posts in AceCommands with `@FocusedValue`/`.focusedSceneValue` actions. Keep the section in `@SceneStorage`, seeded from the AppStorage value.

**20. Mac search does nothing on Calendar, Dumpsters and Labor, and the Upcoming/Unpaid/Done switch clears the search.**
How: When text is typed on a board section, switch to Customers and keep the text. In the `onChange(of: sidebarRaw)`, clear only when the old or new item has no jobs filter.

**21. The Mac inspector has no way to close it.**
How: Add a "Hide" toolbar item in each inspector, `.onExitCommand { selection = nil }` on the boards, and View › Hide Inspector (⌥⌘I).

**22. Mac save rules are mixed, and the quiet click-away save skips the overlap question.**
What happens: the job page shows Save but also saves on click-away. Edits may be lost on Quit (assumed: SwiftUI doesn't promise onDisappear on quit).
How: For existing jobs and quotes on Mac, save each change automatically (debounced) and remove Save there. Keep Save only in New sheets. Also persist on `NSApplication.willTerminateNotification`.

**23. Synced changes never update Google Calendar, and an address fixed on one device leaves the old address on events the other wrote.**
How: Split `jobSaved` into update-only and create. After applying sync changes, call update-only (by marker) for every applied job, and `customerSaved` for applied customers. In `jobsWritten(for:)`, drop the `calendarWrittenAt != nil` condition. Which device may *create* events is Decision 6.

**24. Choosing a Calendar for Jobs puts no existing jobs into it; duplicates aren't cleaned up; jobs show twice when this device's calendar is None.**
How: When a calendar is chosen, and from a "Put upcoming jobs in the calendar now" button, run `jobSaved` over today-onward jobs. The marker lookup already prevents doubles. In `jobSaved`, also run the marker search when a remembered event exists, and remove the other copies. Call `store.refreshSourcesIfNecessary()` in `refresh()`. In `events(on:hidingJobs:)`, hide by marker whatever calendar the event is in.

**25. Writing to Google Calendar silently stops if the calendar's identifier changes.**
How: Also save the calendar's title and account. If the ID stops matching, adopt the single writable calendar with that title in that account; otherwise show a quiet warning row on the Calendar screen.

**26. Sheet link: Ashley's edits during a server write land on the wrong rows; two runs can overlap; an edit made mid-write can be skipped for hours.**
How: Right before `batchUpdate`, fetch the Drive version again and abandon the run if it moved. Do the D1 reads before the grid read. Take a lease at the start of `runSheetSync` (`UPDATE google_link SET running_until = ? WHERE running_until < now`). Save `file.version` from the start of the run, not the one after the write, and drop the second `files.get`.

**27. Sheet link: Resume pauses again a minute later, and Disconnect then Connect forgets which row is which job.**
How: Replace Resume with two Mac-only choices that name the jobs: "Delete these 12 jobs in Ace too" (a one-time flag past MAX_DELETES) and "Keep them in Ace" (drop those tags). Keep `sheet_rows` and `last_seq` on Disconnect, labelled with the sheet ID, and reuse them when the same sheet is picked. Add a "Reconnect Google" action that only renews the token.

**28. Sheet link: blank-name rows never match, "Total…" customers vanish, and half-typed rows leave stray customers.**
What happens: blank-name rows are duplicated and "No name" gets written into her sheet. A customer like "Total Property Management" has their job deleted. Rows caught mid-typing leave stray customers behind.
How: Use one shared key in both languages that treats "No name" and "" as the same (google.js 184/244/266, SheetImport.swift 220-245), and write "" for "No name". Treat a row as a totals line only when the name is exactly "total" or "totals" (optionally with a colon), in sheet.js and SheetImport. Delete a sheet-made customer left with no jobs, phone or notes when its job moves.

**29. Sheet link: a sheet edit overwrites the whole job; name edits split or mix customers; matched rows are never compared.**
How: Apply only the fields whose cells changed (needs the stored row values from M4) and keep the device's change for the rest. Rename in place when the change looks like a correction, even for repeat customers, and never carry a phone across a complete name change. After a first-connect match, compare `rowFromJob(job)` with the row and reconcile.

**30. Sheet link: a renamed heading or Clear formatting changes every job at once.**
What happens: renaming a heading turns every payment into "Not set"; Clear formatting marks all 43 unpaid jobs paid.
How: Save the tab's sheetId and column positions at connection, and pause if either changes. The "more than about 25 rows changed" pause from M13 covers formatting.

**31. Sheet link smaller bugs.**
- Moving a timed job's date leaves its end on the old day: shift `endsAt` by the same amount.
- The check number in notes grows on every edit and strips hand-written "Check #": keep sheet-only values in `data.sheet`, not in notes.
- A job typed for today arrives already done: use `<` in the live link's `isPast`.
- The sign-in return accepts a callback without the state token: require `state`.
- Fixed small tag numbers can collide: start `next_tag` at a random large base.
- Mac Settings hides the server's own error: check `reply.error` before `reply.url`, show "Google access stopped. Connect again." with a button, and clear `message` on a good refresh.

**32. Sheet tests prove less than they claim.**
How: In sheet-test.mjs, snapshot `before` and assert exactly one job changed; assert `/test/last-batch` didn't change in step 3; assert the date against a fixed value (Oct 1 2026 Boston midnight is 1790827200000). Add the missing cases (deleting a customer, blank names, Total names, blank street, unknown payment text, Resume, reconnect, two runs at once, an insert between read and write). Add a small `/v1/sync` test file (two writers, page boundary, refused older change, deletion against a newer edit). Do one Ace-made new row against real Google.

**33. The docs promise safety features that don't exist.**
What's missing: the 30-day keep and restore, "a copy of every row", "only changed cells", the replaced-value note, the headings check, re-reading before writing, and a week on a copy. Device deletions also overwrite the server's stored details with `{}`.
How: In index.js, keep the old details on a delete (`data = CASE WHEN excluded.deleted = 1 THEN records.data ELSE excluded.data END`). Then either build the rest or rewrite the safety rules to say what's true today.

**34. Import correctness.**
- Red is read narrowly (fill only, strong red, no CSV): when no red is found, or the file is a .csv, warn "No red prices were found. Every job will come in as paid." Also read font colour, indexed and theme colours by hue, in sheet.js too.
- Re-imports duplicate edited jobs, and the button always says "Import 600 jobs": run a dry-run in the preview showing "N new, M already in Ace".
- Bad dates are filled in silently, and "1/5-1/7" becomes 2001: count undated rows in the preview, accept a year only from exactly three parts within 2000–2100, and read YYYY-MM-DD.
- Import is allowed before the first download: require `lastSynced != nil && !isSyncing` (see M10).

**35. If the database is ever replaced while the sync file survives, every record is deleted everywhere.**
How: Keep a database ID inside the database and in `SyncState` and call `forget()` when they differ. Refuse to send more than about 20 deletes in one sync without asking.

**36. Every sync reads and fingerprints every record on the main thread, every 30 seconds (estimated, not measured).**
How: Skip the full scan when nothing has been saved since the last sync (pull only). Later, move the scan to a background ModelContext.

**37. The sync icon turns orange in every dead zone, can say "Up to date" when stale, and Settings › Sync asks for a code that's built in.**
How: Add a grey `.offline` state for no-signal URLErrors ("Offline. Changes are kept on this iPhone."). Keep orange for 401, server errors and unsent changes older than about 15 minutes. Show `.waiting` when `lastSynced` is older than about 2 minutes. Add a `.starting` state at launch. When `SyncEngine.builtIn != nil` and nothing is typed, show "Built in" instead of the two fields (keep the fields in DEBUG).

**38. The overweight rate is kept on each device.**
How: Add a synced one-row "business settings" record (`SyncIDs.named("settings")`) holding the rate per ton and salaried days, and read it in the pickup and swap views. Until then, it's checklist item 9.

**39. Dumpster screen gaps.**
- Mark picked up or dropped off there leaves the booked job open: show "Also mark the booked pickup job done" via `bookedJob(...)`, and for swaps, look up the swap then pickup job.
- Price, agreed weight, location and customer of a rental that's out can't be corrected: make the Current rental rows editable, plus "Cancel this drop-off".
- Drop-off dates aren't checked: `DatePicker(..., in: dropOffDate...)`, and fill the Assistant's drop-off date from the note.
- "Due today" and "Overdue" don't update overnight: a `@State today` refreshed on `NSCalendarDayChanged` and scenePhase.

**40. Labor.**
- A rate or pay-type change rewrites past weeks: store the rate on each `LaborEntry`, or at least confirm the pay-type change.
- A retired salaried person keeps "working": add `retiredAt`.
- A shift range ("7-3:30") is read as 7 hours: reject text with more than one number.

**41. iPhone large-text and layout fixes.**
- The new month grid runs off the screen from xxxLarge: `min(circle, 40)` plus `.dynamicTypeSize(...xxLarge)`, like WeekStrip; Go to month uses `[.medium]`.
- Detail headers squeeze the name next to the price at accessibility sizes: an AnyLayout VStack, like JobRow.
- FlowRow gives each button its full width: propose `min(width, bounds.width)`.
- CustomerRow should stack at accessibility sizes.
- Hours boxes, "All quotes" and small dumpster cards are under 44 points: raise them.

**42. Search a phone number pasted as "+1 (508) 555-0147".**
What happens: it finds nobody, and New customer puts the number in the Name box.
How: In `SearchText`, drop the digit-count comparison.

**43. Customer delete question doesn't show what's at stake.**
How: "Delete Linda Johnson? 3 jobs and $450 owed will be kept with no customer."

**44. Assistant smaller fixes.**
- Raw error text and running out of credit: plain cases for credit/billing, 413, captive Wi-Fi and timeouts; reuse `failureText` in FollowUp.
- The prompt cache never hits: move "Today is … The time is …" out of the system prompt into the user block, and update the contract doc.
- Hands-free never stops: auto-stop after about 2 minutes or 10–15 seconds of silence.
- Cancel can offer a finished job: search only not-done, today-or-later jobs.
- "Start a new job instead" loses the day: copy `newDate` and `newTime` across.
- Silence becomes "Thank you": check with your noise recordings.
- The contract check skips the follow-up prompt: extend check-contract.py.
- The Keychain key can move to a new phone by backup: use `…ThisDeviceOnly` with update-before-add.

**45. Security hardening (low).**
- Clamp `updatedAt` to at most server time plus 5 minutes, and only update `sheet_rows` for writes the database accepted.
- Compare the sync code with `timingSafeEqual`, accept an optional `SYNC_KEY_NEXT`, and add a rate limit on 401s.
- Refuse bodies over about 512 KB and records over about 32 KB.
- Honour `GOOGLE_TEST_URL` only for localhost.
- Revoke the Google token on Disconnect and on replace.
- Default `npm run dev` to 127.0.0.1, add `dev:lan`, and accept https-only in Settings (localhost only in DEBUG).
- Add `*.dmg`, `*.app/`, `*.xcarchive/`, `*.p12`, `*.p8`, `*.mobileprovision`, `ExportOptions.plist` to .gitignore.
- Turn on two-factor sign-in for your Cloudflare, Google Cloud and GitHub accounts.

**46. Crash guards (low).**
- Replace `try!` encodes with `try?` plus report, and filter non-finite numbers in Parse and SpreadsheetReader.
- Use `Int(exactly:)` for check numbers.
- Add bounds checks in the zip reader.
- Cap `Parse.money` (finite, under about 1,000,000) and make `moneyText` safe.

**47. Versioned schema (low).**
How: Capture today's models as `SchemaV1` with an empty migration plan, and replace the `fatalError` with a "data could not be opened" screen that keeps the store file.

**48. Polish (low).**
- Late-night new jobs default to tomorrow: start today.
- The Mac midnight roll-over updates from a background thread: `.receive(on: RunLoop.main)`.
- iPhone month has no way back to this month: a Today button in the grid header.
- The week strip doesn't say "has jobs" to VoiceOver: add it, with a label setting so Labor can say "hours logged".
- VoiceOver labels: "Job done" plus a hint; "Owed 12 days"; Notes field labels; hide pill icons.
- Overlap check runs several times per keystroke: compute once per pass.
- Notice and haptics on Done swipe, quick-menu Mark done and paid, and salary taps.
- Today figure versus header disagreement: "1 left".
- Cap Not marked done at 5 with "See all".
- Owed tiles and the Dumpsters figure open their lists.
- Pull to refresh on lists.
- An A–Z index on Customers.
- Quote Reopen by swipe asks when booked; also add `allowsFullSwipe: false`.
- Mac: Delete key, a Job menu and ⌘1–⌘8; one `columnVisibility`; a scrolling import preview and "Import Spreadsheet…"; the title shown once; no doubled Unpaid/Done; right-click menus on board quotes and dumpsters plus Copy Phone Number; a tabbed Settings window; system colours for the board, checked in both modes; one shared speech engine; job/quote minimum size on the sheets, not the views; Delete key on lists.

**49. Docs drift (low).**
- HANDOFF sections 1, 3, 5–9 describe Oct 19.
- CLAUDE.md still says Today/Jobs/Customers/Dumpsters, "no onboarding", "cash, check, card" and "Claude cleans cells" (your OK needed to edit it).
- decisions.md isn't newest-first.
- platform-facts.md says caching "won't engage" and lists questions that have been answered.
- calendar-tab.md still describes UICalendarView, with no Oct 21 decision entry.
- Google ownership is stated four ways ("Kyle's project; Ashley signs in with the business Gmail" is current).
- ashley-spreadsheet.md still says Venmo and Cash App are undecided.
- The test sheet generator lacks blank names, total rows, text dates, red text, other reds and future rows.

---

## 3. Decisions for Kyle

1. **Overweight charge and rental price on the bill:** add the charge to the customer's pickup job price, or create a separate done, unpaid "Overweight, Dumpster 3" job? (Either makes Owed, Unpaid and the sheet pick it up.)
2. **Mark paid:** should it ask Cash / Check / Card / Venmo / Cash App, with the amount filled in, and skip the question when a type is already set?
3. **Dumpster jobs and the dumpster:** should marking a pickup job done offer to pick up the dumpster, and the reverse, so Alex doesn't enter things twice?
4. **What goes into Ashley's sheet:** every job type, or skip quote visits and dumpster pickups, or only jobs with a price?
5. **Red price rule (a question for Ashley):** is every unpaid job's price red, including jobs not yet done, and by hand or by rule? Until then: a future row without red comes in as unpaid, or as paid like today?
6. **Google Calendar writer:** should only Ashley's Mac create events, for every job including synced and sheet jobs, or drop calendar writing from version 1?
7. **Field-by-field merge:** do the full merge now (each field keeps its own latest change), or after Oct 31, with only the "save what changed" fix (M8) and the dumpster pickup rules (Fix 3) before then?
8. **Excel import:** keep it only for an unsynced copy, or remove it from version 1 now that the sheet link exists?
9. **Claude account and key:** your key through a relay on Ace's own server behind the sync code, or the business's key typed on each device on setup day?
10. **What each note sends to Anthropic:** keep the whole directory, or drop customer notes (gate codes) except for named customers, drop pay rates unless asked, and drop phone numbers from the directory?
11. **Debug section:** hide it behind a hidden switch (tap Version seven times), or remove it from their build entirely?
12. **Oct 31 cut list:** which version 1 items move to November: Apple's speech engine, MapKit address completion, the Lock Screen/Action button entry, the full text-size pass, two-way writing on the real sheet?
13. **Trucks and job-site addresses:** add a truck number (so the overlap warning only fires per truck) and a per-job site address?
14. **One-tap Done and Paid:** keep the full swipe and add a 4-second Undo bar, or turn off the full swipe?
15. **Partial payments:** should price on a voice update mean the job's new total, with "rest next week" kept as a note and unpaid?
16. **Assistant placement on iPhone:** a slim hold-to-talk bar above the tab bar (iOS 26 bottom accessory), or a large button pinned to the bottom of the Assistant sheet?
17. **Labor history:** keep the rate on each day's hours so raises don't rewrite past weeks?
18. **Pay week:** which day does Alex's pay week start?
19. **New year's sheet:** one sheet per year, and should Ace leave out jobs dated outside the connected sheet's year?
20. **Overnight day rule:** iPhone jumps to today, Mac keeps a picked day. Which one for both?
21. **In-the-yard tiles:** plain cards with a green dot, so colour on that row only means "look here"?

---

## 4. Design and polish ideas

Ranked by value for effort, merged from the critics and design reviewers.

1. **Mark paid asks how (an hour; many times a day).** Five big buttons with the amount at the top, Check asks for the number. Pairs with Decision 2.
2. **One message bar with Undo for every one-tap change (half a day).** Show "Job marked paid. Undo" for about 4 seconds, with the success haptic. Write Undo by hand (put the old values back and re-stamp `updatedAt`); don't use SwiftData's undo manager, which rolls `updatedAt` back and could stop the reversal syncing. Wire ⌘Z on the Mac.
3. **Today as a run sheet on iPhone (half a day).** Street and town on each day card; a "Next" card for the next not-done job with Call and Directions; at large text, today's jobs above the four figures.
4. **Calm sync status (an hour).** A grey offline state, orange only for real problems, and a small "Updated just now" line at the foot of the Calendar and Mac sidebar.
5. **Make every top figure open what it counts (an hour).** Owed opens Unpaid, Dumpsters opens Dumpsters, with a chevron on tappable tiles.
6. **Long-press a dumpster tile (two hours).** Call the renter, Directions, Extend 3 days or 1 week, and Mark picked up opening with the weight box ready.
7. **Pull down to sync, and View › Sync Now (⌘R) on the Mac (30 minutes).**
8. **"Same as last workday" in Labor (an hour).** Fill each person's hours from the previous workday, with Undo.
9. **Quiet motion where state changes (two hours).** `.contentTransition(.numericText())` on figures, `.symbolEffect` on Done/Paid, a smooth tile colour change. Nothing else moves.
10. **Read-only job page on iPhone with Edit (half a day).** Protects against thumb edits in the truck and fixes the "green Paid button undoes itself" trap: show Done and Paid as pills, and move reversing into a menu or a question.
11. **A "Books" table on the Mac (half a day).** A sortable SwiftUI Table with the sheet's columns and red unpaid prices, so Ashley can compare Ace with her sheet line by line. Add a daily "Sheet and Ace match: 613 jobs, $12,400 unpaid" line in the sync popover.
12. **Recent changes with Put back (a day).** A small server history table shown on the Mac in plain words ("Linda Johnson, Oct 20: price $300 → $350, from the sheet").
13. **Mac Job menu and keyboard (two hours).** ⌘D Done, ⇧⌘P Paid, the Delete key asks, ⌘1–⌘6 sections. A six-column flexible dumpster row on the board.
14. **Morning 7 AM notification on Alex's phone (half a day).** "Today: 4 jobs. Dumpster 2 due back (Keane). Dumpster 5 two days late."
15. **Text button next to Call (an hour).** Opens Messages with an editable "on the way" line. It's Alex's own Messages, but check against CLAUDE.md's "no customer-facing" rule first.
16. **Collect phone numbers as customers call (an hour).** A "No phone on file. Add one" button on the job page, since the sheet import has none.
17. **Mac form fields that look finished (an hour).** Compact date pickers, "$525" and "$22/hr" formatting.

---

## 5. What the critics said

- **Ashley (office): 6/10.** The Mac Calendar board, the Owed figure and the dumpster tiles make her day readable, and the sync was clearly tested with care. But the sheet link can still quietly damage her books (whole-row rewrites, blanked names on customer delete, every quote visit as a row, a Debug button that adds 1,000 fake rows), so until that's fixed she'd keep checking the sheet by hand.
- **Alex (owner, truck): 6/10.** The dumpster board and the pickup-first page are the reason he'd open the app, and hold-to-talk suits the truck. But the app still doesn't get him paid (the overweight charge goes nowhere, Mark paid doesn't ask how), and sync adds new ways to lose a pickup, so four critical fixes come before it goes on their phones.
- **Apple-style designer: 7/10.** The colour system with rules, the Mac week board and the shared components make it look like a real Apple app with no AI feel. The weak spots are interaction patterns: hidden-toggle status buttons, two editing models, a sync icon that cries wolf offline, an Assistant that opens on instructions, and Mac search and menus that don't behave like Mail.
- **Field-service software consultant: 6.5/10.** Keeping Ashley's sheet in step is the single best adoption decision he's seen, and one-tap Done/Paid beats Jobber. Shops drift back to the sheet when the money doesn't add up: dumpster rentals and overweight charges never reach Owed, "not red" means paid even for future rows, and one Settings button could fill the live data with fakes.
- **Fresh-eyes polish reviewer: 7/10.** The app is calm and consistent, so most polish ideas only change one shared piece. It needs feedback and motion on taps, Undo on every one-tap money action, and an iPhone Calendar that works as a run sheet instead of a list of names.

---

## 6. What is working well

- **Sync engine fundamentals:**
  - Running numbers are assigned inside one D1 transaction with a unique index, so they can't collide.
  - "Up to number N" is saved only after everything received is stored, so a cut-off download repeats safely.
  - Incoming changes are applied in link order (customers before jobs).
  - Deletions are worked out from "synced before, gone now", which catches cascades.
  - The server keeps deleted rows.
  - Fingerprints come from the re-encoded local record, so rounding never causes endless re-sends.
  - Requests are sized for the free plan's 50-query limit.
- **Fixed IDs** for dumpsters (by number) and crew hours (by person and day), so two devices don't make doubles.
- **Secrets stay out of git.** All four code files are git-ignored (checked), the full history has no codes, there's no CORS on the server, every query uses bound parameters, and sheet values are written as values, never formulas.
- **The Google link is narrowly scoped.** drive.file only; the phones never talk to Google; the 10-row deletion pause is tested; writes are one all-or-nothing batch; Boston time is handled across daylight saving.
- **The JavaScript sheet reader and the Swift import share the same rules**, so they agree on what a row is.
- **The import preview** shows customers, jobs, the unpaid total and missing house numbers before anything is saved, and keeps past jobs out of the calendar.
- **The Assistant never saves without a tap.** The API request follows the current rules (structured output, no temperature, no forced tool choice). The prompt and schema match the contract doc exactly. Overlaps and past dates are checked in code. Offline notes are kept.
- **Earlier audit fixes are in place:** deletes ask first and never fire on a full swipe; half-typed forms are protected; the mic turns off when the Assistant closes; overnight day roll-over; hours land on the right day; the overlap question on Back.
- **Design.swift is a real shared system:** one meaning per colour, deeper light-mode shades for sunlight, rows that stack at large text, 44-point buttons, and plain business copy with no exclamation points.
- **The dumpster page** puts the pickup first, with the weight box, a live overweight charge, a confirmation naming the amount, haptics, and Call and Directions.
- **The Mac** follows Mail's structure, with sidebar counts, an inspector, ⌘N/⌘F/⌘T, and specific delete questions. The month grid is careful (always six weeks, first weekday honoured, full VoiceOver labels).
- **The docs label honestly** what was and wasn't tested, and decisions are recorded with your own words and the reason.

---

## 7. Checked and dropped

- **CPU limit on big sheet checks:** the code is wasteful (a date formatter per row, the whole spreadsheet read), but the 600-row real-Google run worked. Kept only as a cheap clean-up (create formatters once, read only the job tab).
- **A hidden tag on two rows:** Google makes tag IDs unique per spreadsheet, so a copied row can't carry the same tag. The real gap is the untested tag behaviour (M13).
- **Debug logging on their phones:** only Debug builds save request files, and Ad Hoc installs are Release builds. Just make sure their builds come from Product › Archive.
- **A ghost rental from a double tap on pickup:** the form is replaced in the same instant, so a second tap can't land. A `guard isOut` in `markPickedUp` is still cheap insurance.
- **Hours lost when leaving the Labor screen:** switching tabs and pushing pages still end focus and save. Unproven; an onDisappear save is optional insurance.
- **The month swipe fighting page scrolling:** the code already checks for a sideways drag. Worth a ten-second check on a real iPhone.
- **The invisible Mac "New job" link being clickable:** the pointer has to be over the column to reach it, which already makes it visible.
- **No cap on mass deletions spreading:** real in the code, but both triggers are rare, the everyday clear paths call `forget()`, and recovery exists. The deletion cap is folded into Fix 35.
- **"Sheet per year" deleting a year of jobs via Resume:** Resume never bulk-deletes, it pauses again, and a new year's file is a fresh connection. Kept as Decision 19.
- **The duplicate "hidden New job link" finding from Mac design:** same as above.
- **Several severity downgrades** (not drops) were applied by the skeptics and are kept as given above. Among them: blank dumpsters (critical to high), the server race (critical to high), and the sync code in the bundle (high in most areas, critical in two; kept critical here because the next beta is planned).

---

Files read for this report: /Users/kylesilva/Documents/Ace-junk-removal/docs/review-2026-10-20-iphone/audit.md (for its style), plus Ace/Settings/SettingsView.swift, Ace/Data/SampleData.swift, Ace/Support/Beta.swift, Ace/Sync/SyncEngine.swift, Ace/Sync/SyncRecords.swift, Ace/Data/Models.swift, Ace/Dumpsters/DumpstersView.swift, Ace/Jobs/JobEditView.swift, Ace/Assistant/JobReviewView.swift, Ace/Mac/WelcomeView.swift, cloudflare/ace-sync/src/index.js, cloudflare/ace-sync/src/google.js, cloudflare/ace-sync/src/sheet.js and Ace.xcodeproj/project.pbxproj, which I used to re-check the top 10 items.
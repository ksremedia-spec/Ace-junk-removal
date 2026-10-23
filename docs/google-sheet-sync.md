# Keeping Ashley's Google Sheet and Ace in step

**Status, Oct 21 (night): built and tested against a stand-in for Google
on Kyle's Mac; not yet tried with real Google.** Server code:
`cloudflare/ace-sync/src/google.js` (sign-in, the minute-by-minute check)
and `src/sheet.js` (reading and writing Ashley's columns, the same rules as
the Mac import). Mac: Settings › Google Sheet (`Ace/Sync/SheetLinkSection.swift`).
Google setup steps: `google-cloud-setup.md`.

Tested with `test/run-sheet-test.sh` (stand-in Google `test/fake-google.mjs`,
separate test database), all 24 checks passing: connecting, matching a job
already in Ace instead of doubling it, red = not paid, payment types,
check number / not mailing / unknown house number into notes, edits both
ways, a new Ace job placed as a row in date order, a typed row becoming a
job, a customer renamed in Ace renaming the row, deletions both ways, and
12 rows vanishing at once pausing the link with nothing deleted. A
600-row first connection: 600 jobs, 480 customers, every row tagged.
Then with the real apps: the Mac app and a phone Simulator started empty,
Connect Google Sheet… was clicked on the Mac, and the 40-row sheet filled
both; Mark paid on the Mac took the red off the row in about 12 seconds;
a price typed in the sheet reached the Mac and the phone in about 70
seconds and showed on the Mac's Unpaid list.

**With real Google (Oct 21, night, Kyle's test account
scjewleryshowcase@gmail.com, project "ace-test-512402", Testing mode with
that account as the one test user):** Kyle connected "2026 ACE Books
(test)" (600 fake jobs pasted into a Google Sheet, 43 red prices) from the
Mac; the Mac app and a phone Simulator both filled with 600 jobs, 480
customers, 43 unpaid, and all 600 rows were tagged. Google did pass
`state` back through the picker. Lockstep test the same night, three
devices (Mac app, phone Simulator A "Ashley", phone Simulator B "Alex",
which filled itself from empty) plus the real sheet, all copies compared
by a fingerprint of every job after each step:
- price typed in the sheet → all three devices (about 5 s after the
  sheet check);
- 15 rows pasted into the sheet → 15 new jobs on all three (about 2 min);
- Mark paid clicked on the Mac → both phones in 28 s, sheet row unpaid
  flag cleared;
- Mark paid tapped on phone A → Mac and phone B in 24 s, sheet updated;
- a row deleted in the sheet → job gone on all three;
- a job deleted on phone A (after its "Delete this job?" question) →
  gone on the Mac, phone B and the sheet.
After every step all copies matched (end: 613 jobs, $244,250). Still
unknown: whether hidden row tags survive sorting, cutting
and pasting (Google does not say); whether Cloudflare's free plan's 10 ms
of CPU per run is enough to read a 600-row sheet (if not, the $5 a month
Workers plan allows far more).

Original plan follows. Researched Oct 21, 2026 from Google's and
Cloudflare's own documentation (links at the end); anything those pages do
not say is marked **unconfirmed**.

Why: Kyle promised Ashley and Alex that her sheet ("2026 ACE Books", tab
"Client Job List") and Ace would stay in step. She will keep using the
sheet until she trusts Ace. Layout of the sheet: `ashley-spreadsheet.md`.

## In plain English

- **Ashley connects her sheet once with "Sign in with Google"** (Kyle's
  choice, Oct 21). In Ace she clicks Connect Google Sheet, signs in to
  Google as usual, clicks Allow on one line ("See, edit, create, and
  delete only the specific Google Drive files you use with this app"),
  and picks "2026 ACE Books" from her Drive. Ace gets that one sheet and
  nothing else in her Google account. After that nobody signs in again;
  it keeps working while the sync runs.
- **Ace's Cloudflare server talks to the sheet,** every minute. It first
  asks Google "has the sheet changed?" (cheap). Only when it has does it
  read the whole tab, compare it with what it saw last time, and pass the
  changes on to Ace.
- **Changes in Ace go into the sheet** in Ashley's layout: a new job becomes
  a new row in date order, marking it paid takes the red off the price, a
  price change changes the cell.
- **Each row is tied to its job by a hidden tag** that Google keeps on the
  row and Ashley never sees. Tags stay with the row when rows are inserted
  above it, and go when the row is deleted (Google says both). What happens
  to a tag on sort, cut-and-paste, copy and drag is **not documented**, so
  that gets tested first (step 1 below). Whatever the test shows, Ace also
  matches by date, name and street when a tag is missing.
- **What stays only in Ace:** phone numbers, times, job types, dumpsters,
  quotes and crew hours. The sheet has no columns for them, and the plan
  does not add any unless Ashley wants them.
- **"In step" means within a minute or two,** not the instant she types.

## Safety rules (the sheet is her books)

1. **Never guess on her sheet.** If the headings are not where they were,
   or a lot of rows vanish at once (more than 10 in one minute), syncing
   stops and Ace shows "Sheet sync is paused" with the reason. Nothing is
   written until someone looks.
2. **Deletions follow automatically** (Kyle, Oct 21). A row deleted in
   the sheet removes the job in Ace, and a job deleted in Ace removes its
   row. Rule 1 still applies: more than 10 at once pauses syncing instead.
   Every deleted job is kept on the server for 30 days, so a mistake can
   be put back from there or from the sheet's version history.
3. **Only the cells that changed are written,** never the whole row or
   sheet, so an edit she is making in another cell is not overwritten.
4. **Two undo paths.** Google Sheets keeps its own full version history
   (File › Version history), and the server keeps a copy of every row as
   it last saw it, so any sync can be put back.
5. **Try it on a copy first.** Two-way writing runs for a week against a
   copy of her sheet before it touches the real one.

## The order of work

0. **Prerequisites.** Ace's own sync between devices through Cloudflare
   (build step 5) comes first: the server has to hold the jobs before it
   can match them to rows. Jobs already carry a permanent ID and a "last
   changed" time; customers still need a permanent ID, and Ace needs to
   remember deletions so the server can tell "deleted" from "never sent".
1. **A ten-minute test of the hidden tags** in a scratch sheet connected
   the same way (sign in, pick it): tag five rows, then sort, cut and paste, copy, drag
   and undo, and see where each tag ends up. If tags do not survive sorting
   or cut and paste, the fallback is a short job number in her empty
   column A (cell contents always move with sorting), plus the date, name
   and street match.
2. **Sheet → Ace, read only.** The server reads her sheet and Ace follows
   it. Nothing is written to her sheet yet, so it cannot harm her books.
   This replaces the one-time import and is already "in step" in one
   direction.
3. **Ace → sheet, on a copy** of her sheet for about a week.
4. **Ace → sheet on the real sheet.**
5. **Optional, later: instant updates.** A tiny script inside her sheet
   (Google Apps Script) can tell the server "something changed" the moment
   she types, instead of waiting for the next minute. The minute-by-minute
   check stays as the safety net.

**Timing (estimate, not a promise):** step 2 could land soon after device
sync. Steps 3 and 4 include a week of testing on a copy, so realistically
early to mid November, after the October 31 version 1.

## Decisions waiting on Kyle (one at a time)

1. ~~Gmail or Workspace?~~ **Answered Oct 21 (Kyle): a regular @gmail.com
   account.** (It made the robot route possible; Kyle then chose the
   sign-in route, option D, which works the same on Gmail.)
2. ~~Whose account owns the setup?~~ **Answered Oct 21 (Kyle): the
   business's Google account.** The Google Cloud project (the sign-in
   settings) is created in that account, which needs it signed in once
   for about 15 minutes, with Ashley or on her Mac. The client secret
   and Ashley's sign-in token live only in the Cloudflare server's
   secrets and database.
2b. ~~Which route?~~ **Answered Oct 21 (Kyle): "Sign in with Google"
   where Ashley picks her one sheet** (option D), not the robot account.
2c. ~~Website?~~ **Answered Oct 21 (Kyle): acejunkremovalma.com is theirs;
   skip showing the name for now** (Kyle: "skip it"). Google sign-in for
   the sheet goes ahead without it.
   Checked Oct 21: the site is WordPress (hosted behind Cloudflare), and
   its address records (DNS) are at GoDaddy (`domaincontrol.com` name
   servers). Showing "Ace Junk Removal" on Google's screen is optional:
   - Skipping it costs nothing; the one-time screen shows a web address
     instead of the name, and Kyle is with Ashley when she sees it.
   - Doing it later needs only the GoDaddy login, not the website: a TXT
     record to prove ownership in Google Search Console, and a CNAME so a
     small page such as `app.acejunkremovalma.com` (served by Ace's
     Cloudflare server, linking to a privacy policy) can be the app's
     homepage. Whether Google accepts a homepage on a subdomain this way
     is **unconfirmed**.
3. ~~Which wins when both change?~~ **Answered Oct 21 (Kyle): whichever
   change was made last, wherever it was made.** Ace knows the exact time
   of its own edits; Google does not give a time per cell, so a sheet edit
   counts from when the server notices it (within about a minute). Only
   edits to the same job less than a minute apart can come out in the
   wrong order. Ace shows a note saying what was replaced.
4. ~~Deletions?~~ **Answered Oct 21 (Kyle): copied to the other side
   automatically, without asking.** See safety rule 2.
5. Does red always mean unpaid, and does Ashley colour it by hand or
   does the sheet do it by a rule (conditional formatting)? Both can be
   read, but they are written differently.
6. One sheet per year? If so, Ace needs a place in Settings to point at
   the new year's sheet in January.

## Technical notes (for the build)

**Connection: option D below was chosen (Kyle, Oct 21).** Option A
stays here as the fallback if the sign-in route fails its tests.

**Option A (fallback): service account + JSON key.**
- The Worker signs a JWT with RS256 and swaps it at
  `https://oauth2.googleapis.com/token` (grant type
  `urn:ietf:params:oauth:grant-type:jwt-bearer`). Tokens last an hour and
  are minted again as needed; nothing is stored or refreshed.
- Cloudflare Workers' WebCrypto supports RSASSA-PKCS1-v1_5 for import and
  sign. Importing the key as `pkcs8` is the WebCrypto standard; Cloudflare's
  page does not list import formats (unconfirmed there, used widely).
- Scope `https://www.googleapis.com/auth/spreadsheets` (no consent screen
  for a service account). The cheap change check reads the sheet's Drive
  `version`, which needs a Drive scope too; which is the narrowest that
  works was not checked (**unconfirmed**, settle it in the step 1 test).
- The key lives only as a Worker secret, never in the app or the repo
  (same rule as the beta relay).
- Organization key block: enforced by default for Google Cloud
  organizations created on or after May 3, 2024. A personal Gmail project
  has no organization, so it should not apply (inference; Google does not
  say it outright).
- Cost: free. Google's limits page (updated Sept 2026) says going over the
  quota is planned to be charged later in 2026; this plan stays far under.

**Option D (researched Oct 21, at Kyle's request): "Sign in with Google"
and pick the one sheet, scope `drive.file` only.** Verdict: **mostly
yes**, the "Google hasn't verified this app" screen should not appear.
- `drive.file` is "Non-sensitive" (Sheets and Drive scope pages). Apps
  using only non-sensitive scopes need no verification
  (support.google.com/cloud/answer/13463073), and an "unverified app" is
  defined as one requesting sensitive or restricted scopes
  (support.google.com/cloud/answer/7454865). No page says outright "it
  never shows"; that follows from the definition.
- It reaches a sheet she did not create, once she picks it in Google's
  file picker (Drive auth guide). Sheets `get`, `batchUpdate`,
  `values.*`, `developerMetadata.search` and Drive `files.get` (the
  `version` check) all accept `drive.file`.
- Google added a picker for phone and desktop apps (page updated
  2026-10-12): a normal Google sign-in address with
  `trigger_onepick=true&prompt=consent`, opened in the system browser;
  it returns the picked file's ID and a code the server swaps for a
  token. Only `drive.file` may be requested, with no other scope (not
  even name or email). No embedded web views (Google policy);
  `ASWebAuthenticationSession` is the allowed way on Apple devices.
  Ashley connects once **from her Mac**, where it opens her normal
  browser. The iPhone never talks to Google: phones and Macs talk only
  to Ace's Cloudflare server, and only the server talks to the sheet
  (Kyle, Oct 21). So there is no Connect button on iPhone.
- The server keeps a refresh token (`access_type=offline`, a Web client
  with its callback on the Worker). Published "In production", it does
  not expire after 7 days; it ends after 6 months unused (a sync every
  minute prevents that), if she removes Ace's access, or after 100 newer
  tokens. That the picked file stays reachable for months is very likely
  but **unconfirmed**.
- What she sees: Google sign-in, one line "See, edit, create, and delete
  only the specific Google Drive files you use with this app", Allow,
  then her Drive files; she taps "2026 ACE Books". No checkboxes.
- **Catch: the name on that screen.** Without "brand verification" the
  screen shows the app's web domain, not "Ace Junk Removal". Brand
  verification usually takes minutes but needs a domain the business
  owns (verified in Google Search Console), a homepage and a privacy
  policy page. Whether a `workers.dev` address counts is
  **unconfirmed**; a real domain is the safe choice.
- A new year's sheet (a copy) is a new file: she picks again. Renaming or
  moving the sheet is fine.
- Setup in Google Cloud Console (business's account): new project; turn
  on the Sheets, Drive and Picker APIs; Branding (name, support email,
  homepage, privacy policy, domain); Audience External, Publish app (In
  production); Data Access: only `drive.file`; a Web application client
  with the Worker's callback; optional Verify Branding.
- Compared with option A: Ashley sees a familiar sign-in instead of an
  extra name in her Share list; more to build (sign-in page on the
  server, picker hand-off, token storage) and a website to set up for the
  business name to show.

**Option B (avoid): OAuth refresh token for Ashley's account.** In
"Testing" status the token expires after 7 days. In production it works
but adds a sign-in page, an "unverified app" warning, and more silent ways
to break (revoked access, 100-token cap, 6 months unused).

**Option C (add-on, or main route on Workspace): Apps Script bound to
the sheet.** Installable `onEdit`/`onChange` triggers plus a timed trigger
(1, 5, 10, 15 or 30 minutes). Gmail-account quotas: 90 minutes of trigger
time a day, 6 minutes a run, 20,000 web calls a day; a 1-minute trigger
must average under about 3.7 seconds a run. `onEdit` gives values only for
single-cell edits. Edits made by scripts or the API do not fire triggers,
so the server's own writes do not echo back. Whether `onEdit` fires for a
sort or a paste is unconfirmed. It can read and write row tags
(`addDeveloperMetadata`) and backgrounds (`setBackground`). The owner
authorizes it once, through an "unverified" warning on a Gmail account.

**Row tags (developer metadata).**
- Create with `batchUpdate` → `createDeveloperMetadata`, location
  `dimensionRange` of one row, visibility `PROJECT` (only Ace's Cloud
  project sees it; still not secret, Google warns).
- Limit: 30,000 characters per sheet, counting only key and value text.
  700 rows a year with a 36-character ID would hit it, so: key `"a"`, empty
  value, and the job's number in `metadataId` (an integer, not counted).
  That needs a short job number per job (a new field; the UUID stays the
  real ID).
- One read gets everything: `spreadsheets.get` with a fields mask of
  values, `formattedValue`, `effectiveFormat.backgroundColorStyle`,
  `numberFormat` and `rowMetadata.developerMetadata`.

**Reading.** Use `effectiveFormat` (includes conditional formatting) for
the red check; `backgroundColor` is deprecated, use
`backgroundColorStyle` (channels 0–1, a missing channel counts as 0;
treat red as red near 1 and green and blue low). Dates come back as
serial numbers in `effectiveValue` (base 1899-12-30, as in the importer).

**Writing.** `batchUpdate` is atomic and in order: `insertDimension` at
the date position, then `updateCells` (values + red background), then
`createDeveloperMetadata`, all in one request. There is **no
write-precondition** (no revision or ETag check), so re-read the row by
its tag right before writing and skip if it changed.

**Noticing changes.** No push from the Sheets API. Poll Drive
`files.get?fields=version` every minute (5 quota units; `headRevisionId`
does not exist for Google Sheets). Drive push channels exist but expire
within a day, say nothing about what changed, and (by an old secondary
report) can lag about 3 minutes, so polling is simpler and as fast.

**Limits.** Sheets: 300 reads and 300 writes a minute per project, 60 a
minute per user, no daily cap; 429 means back off. One version check a
minute plus a read when it changes is about 2 requests a minute.

**Ace side, found Oct 21:** `Job.jobID` (UUID) is set for every new job
and `updatedAt` is stamped on edits, including swipe and context-menu
toggles. `Customer` has no permanent ID yet. Deleting a job leaves no
record.

## Sources

- Service accounts: https://developers.google.com/identity/protocols/oauth2/service-account
- Sheets scopes: https://developers.google.com/workspace/sheets/api/scopes
- Sheets limits: https://developers.google.com/workspace/sheets/api/limits
- Developer metadata guide: https://developers.google.com/workspace/sheets/api/guides/metadata
- Developer metadata reference: https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets.developerMetadata
- Cells and formats: https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/cells
- batchUpdate: https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/batchUpdate
- Requests (insert, sort, cut, copy): https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/request
- Drive push: https://developers.google.com/workspace/drive/api/guides/push
- Drive files: https://developers.google.com/workspace/drive/api/reference/rest/v3/files
- Key creation block: https://docs.cloud.google.com/iam/docs/keys-create-delete
- Secure-by-default organizations: https://docs.cloud.google.com/resource-manager/docs/secure-by-default-organizations
- OAuth testing 7-day expiry: https://support.google.com/cloud/answer/15549945
- OAuth refresh token rules: https://developers.google.com/identity/protocols/oauth2
- Apps Script triggers: https://developers.google.com/apps-script/guides/triggers/installable
- Apps Script events: https://developers.google.com/apps-script/guides/triggers/events
- Apps Script quotas: https://developers.google.com/apps-script/guides/services/quotas
- Apps Script Range (metadata, backgrounds): https://developers.google.com/apps-script/reference/spreadsheet/range
- Workers WebCrypto: https://developers.cloudflare.com/workers/runtime-apis/web-crypto/

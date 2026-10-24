# Setup day: putting Ace on Ashley's and Alex's devices

Oct 24, 2026. Kyle runs everything from **Ace Setup** (an app on his
Desktop, built from `tools/AceSetup`, rebuilt with `tools/AceSetup/make-app.sh`).
Each step has one button that runs a script in `tools/setup/`; the scripts
can also be run by hand from the repository folder.

| Step | Button runs | What it does |
|---|---|---|
| 1 Before they arrive | `preflight.sh` | Checks Xcode, signing, Cloudflare login, the server, that the copy is not a beta. Changes nothing. |
| 2 Make the server fresh | `server-ready.sh` → `update-server.sh`, `fresh-server.sh live` | Database changes, then the newest server code; empties the server, new server ID, new sync code (into Cloudflare and `Ace/Support/SyncServer.txt`); checks the code works and that the Assistant answers. |
| 3 Build their copies | `build-business.sh` | Mac: archive, Developer ID, notarized by Apple, `Ace.dmg`. iPhone: archive and upload to TestFlight (`upload-testflight.sh`). |
| 4 Their iPhones | — | TestFlight: an internal group "Ace team" with automatic distribution; each phone installs TestFlight and taps Install. Backup: the cable install (`install-iphone.sh`, Ad Hoc, needs Developer Mode). |
| 5 Automatic updates | `testflight-job.sh install` | A daily launchd check on Kyle's Mac (3:30 AM) uploads the last committed version when the last upload is 60+ days old. `testflight-job.sh remove` turns it off. |
| 6 Ashley's Mac | (AirDrop / Finder) | Sends `Ace.dmg`. |
| 7 Google Sheet | `status.sh` | Ashley connects her sheet in Ace; the button shows what the server holds. |
| 8 Dumpsters, crew, rate | — | Done in Ace. The overweight rate and crew working days sync (Oct 24). |
| 9 Final check | `status.sh` | Records, devices, sheet link. |

## The Assistant on their devices

Kyle, Oct 24 (decided while he was away, flagged in HANDOFF): the business
copy uses Kyle's Anthropic account, like the beta did, so nobody types a key.

- The app sends Assistant requests to the Ace server (`POST /v1/claude`),
  with the sync code, like sync.
- The server checks the model (Haiku or Sonnet 5.5 only), caps
  `max_tokens` at 16,000, and passes the request to the `ace-beta-relay`
  Worker over a **service binding** (`CLAUDE` in
  `cloudflare/ace-sync/wrangler.jsonc`). That Worker holds the key as its
  secret `ANTHROPIC_API_KEY`.
- A key typed in Settings › API key on a device still wins: that device
  then talks to Anthropic directly.
- Checked locally (Oct 24): app route → Ace server (sync code checked) →
  relay → Anthropic, which answered "invalid x-api-key" to a fake key, as
  it should. **Not yet run live**: the server deploy is Kyle's button
  (step 2), and step 2 ends with a real one-word Assistant request.
- The relay's own public address still works for the old beta copies.
  Once nobody uses a beta copy, it can be closed so that only the Ace
  server can reach it: add `"workers_dev": false` to a wrangler config
  for `ace-beta-relay` and deploy it, or in the Cloudflare dashboard turn
  off the Worker's workers.dev route. Not done: ask Kyle first.

## TestFlight (decision Oct 24)

- Kyle chose TestFlight for the iPhones (over-the-air updates, no Developer
  Mode). `docs/decisions.md`.
- Verified Oct 24: the upload goes as far as Apple and stops with "App record
  with bundle identifier com.acejunkremoval.app not found on App Store
  Connect". Kyle creates the record (Apps › + › New App, needs Account Holder,
  Admin or App Manager) and invites Ashley and Alex under Users and Access.
- From Apple's help pages (read Oct 24): internal testers are App Store
  Connect users; a group can "Enable automatic distribution" so each upload
  reaches it; builds uploaded as TestFlight Internal Only can only go to
  internal groups. Not stated there: whether internal builds skip Beta App
  Review (believed yes).
- Build numbers are the upload's date and time (`CURRENT_PROJECT_VERSION`).
  The app declares `ITSAppUsesNonExemptEncryption = NO` (HTTPS only), so no
  export-compliance question on upload.
- The automatic job builds the **last committed** version, never half-done
  work, so commit changes that should ship.

## iPhone cable install (Ad Hoc, the backup): what was checked (research, Oct 24)

VERIFIED means read in Apple's documentation or the local Xcode 27.1
tools, or seen on Kyle's Mac. LIKELY means a reliable non-Apple source or
an inference.

- **Export method.** `release-testing` (the new name for Ad Hoc). VERIFIED in `xcodebuild -help`.
- **Developer Mode.** Needed for Ad Hoc on iOS 16 and later. LIKELY: Firebase and Diawi say so; no Apple page says it outright.
  - It only appears in Settings after the phone has been paired with a Mac. VERIFIED.
  - It must stay on.
- **Registering a phone.** `xcodebuild build … -destination id=<UDID> -allowProvisioningUpdates -allowProvisioningDeviceRegistration`, which is a build only. VERIFIED in the local help. The phone must be paired.
- **Checking the profile.** The exported app's `embedded.mobileprovision` lists `ProvisionedDevices`, and `install-iphone.sh` checks it. If the phone is missing, the stale Ad Hoc profile is removed and the export redone.
- **Installing.** `xcrun devicectl device install app --device <UDID> Ace.app`. VERIFIED in the local help.
- **How long it lasts.** The profile ends when the distribution certificate does: **about Aug 12 2027**. LIKELY (Kyle's App Store profile ends then). The install step prints the real date.
  - After that, Ace won't open.
  - Fix: install again over the top, which keeps the data.
  - Never delete the app first.
- **First launch needs internet.** Apple checks Ad Hoc apps when they first open. VERIFIED (Apple's provisioning-profile updates page).
- **"Untrusted Developer" prompt.** Not expected for a paid team's Ad Hoc copy. UNCONFIRMED.
  - If it appears: Settings › General › VPN & Device Management › Trust.

Sources: developer.apple.com pages "Distributing your app to registered
devices", "Enabling Developer Mode on a device", "Provisioning profile
updates"; WWDC22 "Get to know Developer Mode"; Firebase App Distribution
troubleshooting.

## Not yet tried for real (Oct 24)

- The Mac Developer ID export and notarization on Kyle's account: whether
  his Apple ID may create the Developer ID certificate (needs the Account
  Holder or Admin role). See HANDOFF for the dry-run result.
- The Ad Hoc export on Kyle's account, and installing it on a phone.
  Kyle's phones were not connected while he was away.

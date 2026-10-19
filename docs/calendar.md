# Calendar tab and Google Calendar

Research for Kyle, October 19, 2026. Kyle asked: "app need to have a fully
functional calendar tab - and it needs to integrate with google cal on mac
and iphone".

Nothing here was built or run. The research session runs on Linux with no
Xcode, so every "test" below still has to happen on a real iPhone or Mac.

Each point is labelled:

- **Verified (source: URL)**: read in Apple's or Google's own documentation.
- **Assumed**: a reasonable belief that nobody has checked.
- **Not known; how to find out**: plus the way to settle it.

How the sources were read: Apple's developer documentation
(developer.apple.com), Google's machine-readable description of the Calendar
API, and the Google Sign-In source code on GitHub were opened directly.
Apple's and Google's help sites (support.apple.com, support.google.com,
developers.google.com) are blocked from this session, so those pages were
read through the search engine's quotes of them. Those points say "via
search quotes".

## The short answer

- **Recommendation: use Apple's own calendar system, called EventKit.** Each
  person adds the business's Google account to their iPhone or Mac once, in
  Settings. Ace then puts every job into one Google calendar named "Ace
  Jobs". Apple and Google handle the syncing to calendar.google.com and to
  the other devices. Ace's Calendar screen also shows the other calendars on
  that device, such as Alex's own appointments.
- **What it costs Kyle:** no Google developer account, no sign-in screen
  inside Ace, no extra code library. Two settings lines in the project, a
  permanent ID on every job, and a duplicate guard in the code (section 3).
- **What it costs Ashley and Alex:** add the Google account in Settings once
  per device, and allow full calendar access when Ace first asks. (The exact
  button wording in Apple's prompt is Assumed, not checked.)
- **The limits:** Ace cannot create the "Ace Jobs" calendar itself. Someone
  makes it once on calendar.google.com. Changes made in Google reach the
  phone after a delay that Apple and Google control. Ace has to guard against
  two devices writing the same job twice.
- **Not chosen for version 1: talking to Google directly** (the Google
  Calendar API). It needs a Google Cloud project, a Google sign-in inside the
  app on every device, a "Google hasn't verified this app" warning to click
  through, and an offline queue we would write ourselves. It is the better
  upgrade later, run from the Cloudflare server once sync (step 5) exists,
  because one server writing is the cleanest way to rule out duplicates.

## 1. The Apple route: Google account in Settings, plus EventKit

### Where the Google account is added

- **iPhone (iOS 26):** Settings › Apps › Calendar › Calendar Accounts › Add
  Account › Google, sign in, keep Calendars switched on. Mail and Contacts
  can be switched off. Verified via search quotes (source:
  https://support.apple.com/guide/iphone/set-up-mail-contacts-and-calendar-accounts-ipha0d932e96/ios,
  https://support.apple.com/guide/iphone/change-calendar-settings-iphc37be2016/ios,
  https://support.google.com/calendar/answer/99358?hl=en&co=GENIE.Platform%3DiOS).
- **Mac (macOS 26 Tahoe):** System Settings › Internet Accounts (in the
  sidebar, you may need to scroll) › Add Account › Google, sign in, and tick
  Calendars. Or, from Apple's Calendar app, use the Calendar menu › Add
  Account. Accounts added either way show up in Internet Accounts. Verified
  via search quotes (source:
  https://support.apple.com/guide/mac-help/add-your-email-and-other-accounts-mh35565/mac,
  https://support.apple.com/guide/calendar/add-or-delete-calendar-accounts-icl4308d6701/mac).
  Apple's Internet Accounts page lists macOS Tahoe 26 among the versions it
  covers.
- **iOS 27:** Kyle's phone is on iOS 27.1. Not known whether the menu path
  changed; how to find out: Kyle follows the path above on his phone.

### Do events Ace writes reach Google Calendar on the web and other phones?

- Google says that once the account is on the iPhone, "calendar events will
  now sync directly with your Google Account". Verified via search quotes
  (source: https://support.google.com/calendar/answer/99358?hl=en&co=GENIE.Platform%3DiOS).
- An event only reaches Google if it is saved to a Google calendar, not to
  iCloud or "On My iPhone". Google: "If you add an event to a calendar that's
  not associated with your Google Account, it might not show up ... on
  calendar.google.com." Verified via search quotes (source:
  https://support.google.com/calendar/answer/6261951?co=GENIE.Platform%3DiOS&hl=en).
  This is why Ace must write to the chosen "Ace Jobs" calendar, never to
  the phone's default calendar.
- EventKit is Apple's door into the same calendar database that Apple's
  Calendar app uses; apps never touch the database directly. Verified
  (source: https://developer.apple.com/documentation/eventkit/accessing-the-event-store).
- The system syncs an event written by Ace to Google the same way it syncs
  one typed into Apple's Calendar app. Assumed (this follows from the point
  above, but no Apple page says it in so many words). How to find out: save
  a job on the iPhone, then look at calendar.google.com on a computer.
- **How fast:** Not known. One developer reported that new Google events
  took "30 seconds to several minutes" to appear in Apple's Calendar and in
  their own app, and that `refreshSourcesIfNecessary()` (EventKit's "check
  for new data" call) did not speed it up. Pulling down to refresh in
  Apple's Calendar app did. Verified via search quotes (source:
  https://developer.apple.com/forums/thread/766375). The iPhone has a Fetch
  New Data setting for accounts that do not support Push, under Settings ›
  Apps › Calendar › Calendar Accounts › Fetch New Data. Its "Automatically"
  choice fetches in the background only while charging on Wi-Fi. Verified
  via search quotes (source:
  https://support.apple.com/guide/iphone/change-calendar-settings-iphc37be2016/ios).
  Not known whether a Google account gets Push or Fetch on iOS 26 and 27;
  how to find out: open that Fetch New Data screen and read what it says
  next to the Google account. On the Mac: Calendar › Settings › Accounts ›
  Refresh Calendars. Verified via search quotes (source:
  https://support.apple.com/guide/calendar/change-accounts-settings-in-calendar-on-mac-icl26669/mac).
  Not known which intervals it offers for Google; how to find out: look on
  Ashley's Mac.
- **Offline:** Assumed: an event Ace saves with no signal is kept on the
  phone and sent to Google when the signal returns, as with any CalDAV
  account. Nothing from Apple says this. How to find out: airplane mode,
  save a job, turn airplane mode off, check calendar.google.com.

### Can Ace create the "Ace Jobs" calendar inside the Google account?

- No; someone creates it once on calendar.google.com, and Ace picks it.
  - Apps with full access can create calendars in general. Verified (source:
    https://developer.apple.com/videos/play/wwdc2023/10052/).
  - Google's calendar server for Apple-style connections (CalDAV) does not
    support the command that creates a calendar (MKCALENDAR). Verified via
    search quotes (source:
    https://developers.google.com/workspace/calendar/caldav/v2/guide).
  - Apple's Mac Calendar guide: "If you can't add a calendar for a particular
    calendar account, try adding a calendar on the account provider's
    website. For example, to create a Google calendar, go to google.com."
    Verified via search quotes (source:
    https://support.apple.com/guide/calendar/add-or-delete-calendar-accounts-icl4308d6701/mac).
  - Apple's devices reach Google calendars through CalDAV. Assumed: EventKit
    reports such accounts as a CalDAV source ("Represents a CalDAV or iCloud
    source", https://developer.apple.com/documentation/eventkit/eksourcetype/caldav),
    but that a Google account shows up that way was not checked on a device.
- Google: new calendars can only be created in a web browser, under "Other
  calendars" › + › Create new calendar; the creator becomes the owner.
  Verified via search quotes (source:
  https://support.google.com/calendar/answer/37095?hl=en).

### Sharing "Ace Jobs" between people

- If Ashley and Alex both sign in with the same business Google account,
  nothing needs sharing.
- If they each use their own Google account, the owner shares "Ace Jobs"
  with each of them as "Make changes to events" (Settings and sharing › Share
  with specific people or groups). They must open the email and accept.
  Verified via search quotes (source:
  https://support.google.com/calendar/answer/37082?hl=en).
- A shared calendar may not appear on an iPhone until it is ticked on
  Google's sync page. Google's own page mentions "the Calendar sync page"
  where you "check or uncheck the names of any calendars". Verified via
  search quotes (source:
  https://support.google.com/calendar/answer/99358?hl=en&co=GENIE.Platform%3DiOS).
  The address calendar.google.com/calendar/syncselect, and the claim that
  shared calendars are off there by default, come only from third-party
  guides. Assumed. How to find out: after sharing, open Apple's Calendar app
  on the phone and look for "Ace Jobs".

## 2. Permissions

- There are three levels of calendar access for an app: none, write-only
  (shown to people as "Add Events Only") and full. Verified (source:
  https://developer.apple.com/videos/play/wwdc2023/10052/,
  https://developer.apple.com/documentation/eventkit/accessing-the-event-store).
  The Settings labels None, Add Events Only and Full Access come from a
  third-party guide for iOS 17
  (https://www.macrumors.com/how-to/control-which-apps-have-calendar-access/);
  Assumed unchanged in iOS 26.
- The calls: `requestFullAccessToEvents()` and
  `requestWriteOnlyAccessToEvents()` (iOS 17 / macOS 14 and later). Check the
  current answer with `EKEventStore.authorizationStatus(for: .event)`:
  `.fullAccess`, `.writeOnly`, `.denied`, `.notDetermined` or `.restricted`.
  The old `requestAccess(to:)` no longer shows a prompt when built with
  current Xcode. Verified (source:
  https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:),
  https://developer.apple.com/documentation/eventkit/ekauthorizationstatus,
  https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels).
- **Reading needs full access.** "Your app can't request read-only access ...
  To read events or reminders from the event store, your app needs full
  access." Verified (source:
  https://developer.apple.com/documentation/eventkit/accessing-the-event-store).
- **Write-only is not enough even for writing jobs.** With write-only access
  the app sees one stand-in calendar instead of the real list, so it cannot
  choose "Ace Jobs". It cannot read back any event, "including events your
  app created", so it could not move or delete a job's event or check for
  duplicates. Verified (source:
  https://developer.apple.com/documentation/eventkit/accessing-the-event-store,
  https://developer.apple.com/documentation/eventkit/ekeventstore/requestwriteonlyaccesstoevents(completion:)).
  So Ace asks for full access.
- Apple: ask "only ... at a time when it is clear why the access is needed",
  and full-access requests are denied more often. Verified (source:
  https://developer.apple.com/videos/play/wwdc2023/10052/). So Ace asks the
  first time someone opens the Calendar screen, not at launch.
- If the app reads events before access is granted, it must call `reset()`
  on the event store afterwards to see data. Verified (source:
  https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)).
- **The wording shown in the prompt** goes in the Info.plist key
  `NSCalendarsFullAccessUsageDescription` (iOS 17 / macOS 14 and later).
  Without it, or with only the older `NSCalendarsUsageDescription`, iOS
  refuses access without asking. Apps whose minimum is iOS 17 or later
  should drop the older key. Verified (source:
  https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription,
  https://developer.apple.com/documentation/technotes/tn3152-migrating-to-the-latest-calendar-access-levels).
  The write-only key (`NSCalendarsWriteOnlyAccessUsageDescription`) is not
  needed if Ace only ever asks for full access.
- **Mac:** "To access Calendar data, all sandboxed macOS apps must include
  the `com.apple.security.personal-information.calendars` entitlement."
  Apple's entitlement page says to turn on App Sandbox or Hardened Runtime
  and then tick Calendar; it is one setting, shared by both. Verified
  (source:
  https://developer.apple.com/documentation/eventkit/accessing-the-event-store,
  https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.calendars).
- **The iPhone needs no entitlement**, only the Info.plist wording. Verified
  (source: same page, which lists only the Info.plist keys for iOS apps and
  the entitlement only for sandboxed Mac apps).
- **Apple's ready-made calendar screens (EventKitUI)** exist on iPhone and
  Mac Catalyst only, not in a native Mac app like Ace. So the Mac uses Ace's
  own job form, which it already has. Verified (source:
  https://developer.apple.com/documentation/eventkitui).
- If someone taps Don't Allow, the app cannot ask again; they change it in
  Settings › Privacy & Security › Calendars (iPhone) or System Settings ›
  Privacy & Security › Calendars (Mac). Assumed (third-party source for
  iOS 17 above; Mac not checked). Ace's Calendar screen should say this in
  one plain line when access is off.

## 3. Recognising Ace's events across devices (and avoiding duplicates)

### What EventKit offers

- `calendarItemIdentifier`: for use on one device only. "A full sync with
  the calendar will lose this identifier." Verified (source:
  https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemidentifier).
- `eventIdentifier`: changes if the event moves to another calendar.
  Verified (source:
  https://developer.apple.com/documentation/eventkit/ekevent/eventidentifier).
- `calendarItemExternalIdentifier`: "the calendar item's external identifier
  as provided by the calendar server", which "allows you to access the same
  event or reminder across multiple devices". Apple lists cases where
  several copies share it (imported into several calendars, a shared
  calendar plus an invitation, and others). A repeating event's occurrences
  all share one. "For Exchange servers, the identifier is different between
  iOS and macOS." Look-ups by it (`calendarItems(withExternalIdentifier:)`)
  return a list, not one item. Verified (source:
  https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier,
  https://developer.apple.com/documentation/eventkit/ekeventstore/calendaritems(withexternalidentifier:)).
- For Google calendars specifically: Not known whether the external
  identifier is the same on the iPhone and the Mac, or whether it is set the
  moment Ace saves or only after the first sync. One old report (iOS 9 era)
  saw it change after sync on an Exchange calendar; nothing was found for
  Google. Verified that the report exists, via search quotes (source:
  https://developer.apple.com/forums/thread/6636). How to find out: a Debug
  screen that saves a test event on the iPhone, shows its external
  identifier at once and again after a minute, and the same event's
  identifier on the Mac.
- Google's own name for the cross-system identifier is the iCalUID ("used to
  uniquely identify events across calendaring systems"). Verified (source:
  https://www.googleapis.com/discovery/v1/apis/calendar/v3/rest). That
  EventKit's external identifier equals Google's iCalUID: Assumed.
- **The event's link (URL) field:** Google's CalDAV guide says it "doesn't
  support the Apple iCal extension to allow user-settable URL properties".
  Verified via search quotes (source:
  https://developers.google.com/workspace/calendar/caldav/v2/guide). It is
  unclear whether that means the event's link field. Google's own event
  record has no general link field, only a "source" link that "can only be
  seen or modified by the creator of the event". Verified (source:
  https://www.googleapis.com/discovery/v1/apis/calendar/v3/rest). So:
  Assumed that a link Ace puts on an event may be lost on the way through
  Google. Do not depend on it.
- **The notes field** becomes the event's description in Google Calendar.
  Assumed (this is how it normally appears, but not checked). How to find
  out: save a job with notes, look at it on calendar.google.com and on a
  second device.

### Why duplicates can happen

Ashley saves a job on her Mac, and the Mac writes the event. Ace's own sync
(step 5) brings the job to Alex's iPhone within seconds, but Google may take
minutes to bring the event. If Alex's iPhone looked for the event in that
gap, found nothing, and wrote one, Google would end up with two.

### The guard (a design; Assumed, not built)

1. **A permanent ID on every job**, the same on every device. The app has
   none today; jobs are only told apart by SwiftData's own internal ID,
   which belongs to one device's database. Verified that no such field
   exists (source: `Ace/Data/Models.swift`). Step 5 sync needs this field
   anyway.
2. **A marker line at the end of the event's notes**, such as
   `Ace job 7F3A9C2E-...`. Plain, short, harmless if someone sees it in
   Google Calendar.
3. **One writer per change.** The device where a job was saved writes,
   moves or deletes its event. Other devices never create an event for a
   job that reached them through sync; they only tidy up (point 5).
4. **Look before writing.** Before creating an event, search "Ace Jobs" for
   the marker in a window around the job's date, and around its old date if
   it moved. Apple limits one search to four years. Verified (source:
   https://developer.apple.com/documentation/eventkit/ekeventstore/predicateforevents(withstart:end:calendars:)).
   At 600 to 700 jobs a year, searching from 60 days back to a year ahead in
   one go is small. Assumed.
5. **Tidy up the same way on every device.** If two events carry the same
   marker, keep one by a rule every device agrees on (for example, the one
   whose external identifier sorts first) and delete the rest. Do not rely
   on the creation date alone: it can be empty for synced events ("If nil,
   this property was not set or was synced in this state"). Verified
   (source:
   https://developer.apple.com/documentation/eventkit/ekcalendaritem/creationdate).
6. **Remember the event's external identifier on the job** for a quick
   look-up, but always fall back to the marker search.
7. **Watch for changes.** EventKit posts `EKEventStoreChanged` "whenever
   changes are made to the Calendar database"; it does not say what changed,
   so the app re-reads what it shows. It arrives on the main thread.
   Verified (source:
   https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/ekeventstorechanged).
   On that notice, and whenever Ace comes to the front, the Calendar screen
   reloads and the tidy-up runs. That it fires when changes arrive from
   Google while Ace is open: Assumed (the page says any change to the
   database); test on a device.
8. **Jobs with no time** become all-day events (`isAllDay`). Verified that
   the setting exists (source:
   https://developer.apple.com/documentation/eventkit/ekevent/isallday).
   Jobs with a start but no end time: Not known whether EventKit and Google
   accept an event that starts and ends at the same moment; and Kyle ruled
   out default lengths. Decision for Kyle (see the questions at the end).

## 4. The alternative: calling Google Calendar directly

### What it would take

- **Kyle, in Google Cloud (one time):** create a project, turn on the Google
  Calendar API, fill in the consent screen (app name, support email;
  audience "External" unless Ace uses Google Workspace), and create a sign-in
  client ID of type **iOS** with bundle ID `com.acejunkremoval.app`. The Mac
  app uses the same iOS type. Verified via search quotes: "For iOS and macOS
  apps the OAuth client ID application type must be configured as iOS"
  (source: https://developers.google.com/identity/sign-in/ios/start-integrating).
- **In the app:** Google's sign-in library, GoogleSignIn 10.0.0 (iOS 15 /
  macOS 12 and later). On the Mac it needs a Keychain access group added to
  the app's entitlements. Verified (source:
  https://raw.githubusercontent.com/google/GoogleSignIn-iOS/main/Package.swift,
  https://raw.githubusercontent.com/google/GoogleSignIn-iOS/main/README.md,
  https://raw.githubusercontent.com/google/GoogleSignIn-iOS/main/CHANGELOG.md).
  It also needs a web-address scheme (the client ID reversed) and a
  `GIDClientID` key in the Info.plist. Verified via search quotes (source:
  https://developers.google.com/identity/sign-in/ios/start-integrating).
  Web-address schemes cannot be set through the project's `INFOPLIST_KEY_`
  settings: there is no such setting for them. Verified (source:
  https://developer.apple.com/documentation/xcode/build-settings-reference).
  So the project would need a small Info.plist file of its own, kept out of
  the synchronized `Ace/` folder's copied resources. Assumed (not tried).
- **Which permission (scope) to ask Google for:** the narrowest that fits is
  "See, create, change, and delete events on Google calendars you own"
  (`calendar.events.owned`) or "Make secondary Google calendars, and see,
  create, change, and delete events on them" (`calendar.app.created`).
  Showing all of a person's Google events needs a read scope as well, such
  as `calendar.events.readonly`. Verified (source:
  https://www.googleapis.com/discovery/v1/apis/calendar/v3/rest).
- **Google review:** scopes that read Calendar events count as "sensitive"
  and normally need Google's review. Verified via search quotes (source:
  https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification).
  Not known whether `calendar.app.created` is sensitive; how to find out:
  the Google Cloud consent screen marks sensitive scopes when you add them.
  An app for personal use by fewer than 100 people known to the developer
  can skip the review, but every sign-in shows Google's "unverified app"
  warning, which the person clicks through, and the 100-user cap applies.
  Verified via search quotes (source:
  https://support.google.com/cloud/answer/7454865?hl=en).
- **Sign-ins that expire:** while the project is in "Testing", every sign-in
  (and its refresh token, the long-lived pass the app keeps) expires after 7
  days, so the project must be switched to "In production". A refresh token
  also stops working if unused for six months, if revoked, or when one
  account has more than 100 for the same client. Verified via search quotes
  (source: https://developers.google.com/identity/protocols/oauth2,
  https://support.google.com/cloud/answer/15549945?hl=en).
- **Cost and limits:** no charge for normal use. Projects created on or
  after May 1, 2026 get 10,000 requests a minute per project, 600 a minute
  per user, and 1,000,000 a day; Google plans charges for going over, later
  in 2026, with 90 days' notice. Verified via search quotes (source:
  https://developers.google.com/workspace/calendar/api/guides/quota). Ace
  would use at most a few thousand requests a day. Assumed.

### What it does better

- The app chooses each event's ID itself (lowercase letters a to v and
  digits, 5 to 1,024 characters, unique per calendar). Using the job's
  permanent ID makes a second copy of the same job very unlikely. Google
  warns it "cannot guarantee that ID collisions will be detected at event
  creation time", so this is strong but not absolute. Verified (source:
  https://www.googleapis.com/discovery/v1/apis/calendar/v3/rest).
- Hidden fields on an event (`extendedProperties.private`), searchable
  (`privateExtendedProperty`), instead of a visible marker line. The app can
  create "Ace Jobs" itself (`calendars.insert`). It can ask for "only what
  changed since last time" (`syncToken`). Verified (same source).
- It does not depend on what is set up in each device's Settings.

### What it does worse

- Offline: nothing is queued for us; Ace would keep its own list of
  unsent changes and retry. Assumed (that is how a direct web connection
  behaves).
- A Google sign-in screen inside Ace on each device, with the "unverified
  app" warning.
- If a sign-in expires or is revoked, calendar writes stop until someone
  signs in again.
- Showing Google events in Ace means writing our own Google sync, on top of
  the Cloudflare sync.
- Much more code, plus a third-party library, before the October 31
  deadline.

### The server version (later)

Once Ace's Cloudflare sync exists (step 5), the Cloudflare Worker could be
the only thing that writes to Google: the business account owner signs in
once in a browser, the Worker keeps the refresh token as a secret (as the
demo relay keeps the Anthropic key), and it writes each job with the job's
permanent ID as the event ID. No duplicates from several devices, and
events get written even when every phone is off. The phones and the Mac
would still read calendars through EventKit for the Calendar screen.
Assumed design. Google's note on creating calendars says not to make a
"service account" (a robot Google identity) the owner of a calendar, so
the Worker should act as the real business account. Verified (source:
https://www.googleapis.com/discovery/v1/apis/calendar/v3/rest).

### Side by side

| | Apple route (EventKit) | Google directly (from each device) |
|---|---|---|
| Kyle's one-time setup | None outside Xcode | Google Cloud project, consent screen, client ID, switch to "In production" |
| Ashley and Alex, per device | Add Google account in Settings; allow full access in Ace | Sign in to Google inside Ace; click through the "unverified" warning |
| Creating "Ace Jobs" | By hand on calendar.google.com | Ace can do it |
| No signal | Apple keeps the change and sends it later (Assumed) | Ace must queue and retry itself |
| Duplicates | Guarded by marker, one-writer rule and tidy-up | Guarded by choosing the event ID |
| Other Google events in Ace | Free (whatever is on the device) | Our own sync code |
| Mac | Same code; no Apple event screens on Mac | Same code; Keychain group needed |
| Speed of Google changes arriving | Apple's schedule (minutes) | Ours (on open, or on a timer) |
| What breaks it | Account removed from Settings; "Ace Jobs" hidden or unshared; access turned off | Sign-in expired or revoked; Google policy changes |
| Extra library | None | GoogleSignIn |

## 5. Recommendation and setup steps

**Use the Apple route for version 1.** It needs no Google developer setup,
no sign-in screen in Ace, no warning screens, no tokens that expire, and no
extra library. Apple and Google do the syncing, including when there is no
signal (Assumed). It shows Alex's and Ashley's other calendars beside the
jobs for free. It matches the rule that the app should behave like Apple
built it. The duplicate guard in section 3 is the one piece of real care it
needs. If duplicates or slow updates turn out to bother Ashley in practice,
move the writing to the Cloudflare Worker after step 5, as described above.

### Once, on a computer (whoever owns the business Google account)

1. Go to calendar.google.com. On the left, next to "Other calendars", click
   + › Create new calendar. Name it "Ace Jobs" and click Create calendar.
2. Only if Ashley or Alex use their own Google accounts: open "Ace Jobs" ›
   Settings and sharing › Share with specific people or groups › add their
   email › choose "Make changes to events" › Send. They accept from the
   email.
3. Only if "Ace Jobs" later does not appear on someone's iPhone: on a
   computer signed in as that person, open
   calendar.google.com/calendar/syncselect, tick "Ace Jobs", and save
   (Assumed address; see section 1).

### Each iPhone (Ashley's and Alex's)

1. Settings › Apps › Calendar › Calendar Accounts › Add Account › Google.
   Sign in. Keep Calendars on (Mail and Contacts can be off). Save.
2. Open Apple's Calendar app, tap Calendars at the bottom, and check that
   "Ace Jobs" is listed under the Google account with a tick.
3. Settings › Apps › Calendar › Calendar Accounts › Fetch New Data: if the
   Google account shows Fetch, choose the shortest interval offered.
4. In Ace, open the Calendar screen and allow full access when asked. In
   Ace's Settings, pick "Ace Jobs" as the calendar for jobs.

### Ashley's Mac

1. System Settings › Internet Accounts › Add Account › Google. Sign in in
   the window that opens. Tick Calendars.
2. Open Apple's Calendar app and check that "Ace Jobs" is listed. In
   Calendar › Settings › Accounts, choose the Google account and set Refresh
   Calendars to the shortest interval offered.
3. In Ace, open Calendar and allow full access. In Ace's Settings, pick
   "Ace Jobs".

## 6. What in this project is affected

Read from the project file and the Mac entitlements file; nothing was
changed.

- **The Mac app is sandboxed.** `Ace/Ace-macOS.entitlements` turns on the
  App Sandbox, microphone, outgoing network, and reading files the person
  picks. Hardened Runtime is on (`ENABLE_HARDENED_RUNTIME = YES`). The
  entitlements file is used for Mac builds only
  (`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`). Verified (source:
  `Ace/Ace-macOS.entitlements`, `Ace.xcodeproj/project.pbxproj`).
- **The Info.plist is generated by Xcode** (`GENERATE_INFOPLIST_FILE = YES`).
  Its entries are build settings named `INFOPLIST_KEY_...`, written into both
  the Debug and Release settings of the Ace target, as the microphone
  wording is today. Verified (source: `Ace.xcodeproj/project.pbxproj`).

To add for the Apple route (not done):

1. `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription` in both target
   configurations, next to the microphone line. Apple's build-setting list
   includes it. Verified (source:
   https://developer.apple.com/documentation/xcode/build-settings-reference).
   Suggested wording, plain and with no first person: "Ace shows your
   calendars next to your jobs and adds jobs to the calendar you choose."
2. `com.apple.security.personal-information.calendars` set to true in
   `Ace/Ace-macOS.entitlements`. Nothing for the iPhone.
3. No new package. EventKit is part of the system.
4. A permanent ID field on `Job` (section 3), plus a place to remember each
   job's event identifier. Assumed: SwiftData adds new fields with a default
   to existing installs by itself, as with `endsAt`.
5. Settings rows: "Calendar for Jobs" (pick from the device's writable
   Google calendars) and "Show Calendars" (which other calendars appear in
   Ace). On the Mac this is a plain list with switches, since Apple's
   calendar chooser is not available there.

Things that need Kyle's decision:

- **The iPhone tab bar already has five tabs** (Today, Jobs, Quotes,
  Customers, Dumpsters). With six or more, the iPhone shows the first four
  plus a "More" tab that holds the rest. Verified for Apple's tab bar
  (source: https://developer.apple.com/documentation/uikit/uitabbarcontroller).
  That SwiftUI's tab view on iPhone does the same: Assumed. A sixth tab
  would push two tabs behind More, against the "nothing deeper than two
  taps" rule.
- **What the Calendar screen looks like.** SwiftUI has Apple's month-grid
  date picker (`.graphical`) on iPhone and Mac. Verified (source:
  https://developer.apple.com/documentation/swiftui/graphicaldatepickerstyle).
  A day or week grid with hour lines, like Apple's Calendar app, does not
  come ready-made and would be custom-drawn, which CLAUDE.md rules out.
  Assumed. A standard-controls version: the month picker above a list of
  the chosen day, with Ace jobs, dumpster drop-offs and due-backs, and
  other calendars' events in grey. Ace jobs come from Ace's own records,
  and the "Ace Jobs" copies are hidden on that screen, or every job would
  show twice. Assumed design.

The GitHub build check does not sign the app, so these changes do not
affect it. Assumed.

## Questions for Kyle, and the answers so far

1. One Google account for the business, already on Ashley's and Alex's
   phones and Ashley's Mac? Kyle, 2026-10-19: "im assuming yes but TBD".
   Working assumption: yes, so "Ace Jobs" needs no sharing (setup step 2 is
   skipped). To be confirmed with Ashley and Alex.
2. Where Calendar goes: Kyle chose **Calendar replaces Today**.
3. Changes made in Google Calendar: Ace stays the master copy; they do not
   flow back (told to Kyle, not objected to).
4. A job with a start but no end: an event with no length, following Kyle's
   "no defaults"; test 6 below checks Google keeps it.
5. Other calendars: every calendar on the device, each with a switch in
   Ace's Settings.

The build is in `calendar-tab.md`.

## Tests to run on a real device (to settle the unknowns)

1. Add the Google account on Kyle's iPhone and Mac. Note the exact menu
   path on iOS 27.1 and the Fetch or Push setting shown for Google.
2. On the iPhone, save a test event to "Ace Jobs" with a link and notes.
   On calendar.google.com and on the Mac, check: does it arrive, how long
   does it take, are the notes intact, did the link survive?
3. Compare the event's external identifier on the iPhone right after saving,
   a minute later, and on the Mac.
4. Airplane mode, save an event, airplane mode off: does it reach Google?
5. Move the event on calendar.google.com while Ace is open on the iPhone:
   does Ace get the change notice, and how long does it take?
6. Try an event whose start and end are the same moment: does Google keep
   it, and how does it look?

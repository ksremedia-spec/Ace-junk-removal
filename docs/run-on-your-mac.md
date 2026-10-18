# Running the app on your iPhone

Written for Kyle. This takes about 15 minutes the first time, mostly waiting
for downloads. Nothing here has been run by me: the cloud computer that wrote
the project has no Xcode, so the first real build happens on your Mac. If any
step fails, copy the exact error text and send it to me.

## What you need

- Your iPhone 16 Pro Max on **iOS 26 or newer** (Settings → General → About →
  iOS Version), and a cable. Note which it is: 26.x or 27.x.
- Your Mac with **Xcode** (Mac App Store, free, about 15 GB). Which version
  depends on the phone (I verified these against Apple's Xcode support page;
  see `platform-facts.md`):
  - Phone on **iOS 27**: you very likely need **Xcode 27.1**, which runs only
    on an Apple silicon Mac with **macOS 26.6 or newer**. (Likely, not
    verified: Xcode 26 cannot install onto an iOS 27 phone.)
  - Phone on **iOS 26**: **Xcode 26.x** is enough. Xcode 26.0–26.3 run on
    macOS 15.6 or newer (Intel Macs included); 26.4–26.6 need macOS 26.2 or
    newer. The build check used 26.6.
  - To check: Xcode menu → About Xcode, and Apple menu → About This Mac.
- Internet, for the first build (Xcode downloads WhisperKit) and the first run
  (the app downloads a speech model).
- An Anthropic API key, for the Claude test panel. The speech test works
  without one.

## One-time setup

1. **Get the project onto your Mac.** Either download the zip I sent you and
   unzip it, or from GitHub click the green Code button → Download ZIP. You
   should end up with a folder containing `Ace.xcodeproj`.
2. **Open it.** Double-click `Ace.xcodeproj`. If Xcode asks whether to trust
   the project or "enable" anything, click Trust.
3. **Wait for the package download.** The first time, the bottom status bar
   says "Resolving packages" for a minute or two. That is WhisperKit arriving.
4. **Pick your team.** In the left sidebar click the blue **Ace** project icon
   at the very top. In the middle pane choose the **Ace** target, then the
   **Signing & Capabilities** tab. Under **Team**, pick your Apple account
   (the same one you used for the construction app). Leave "Automatically
   manage signing" ticked. If Xcode says the bundle identifier is already
   taken, change `com.acejunkremoval.app` to anything unique, like
   `com.yourname.ace`.
5. **Put the iPhone in Developer Mode** (once per phone). Plug it in. On the
   phone: Settings → Privacy & Security → Developer Mode → on → restart.
   iOS 16 and later require this before an app from Xcode can run.
6. **Choose the phone as the destination.** At the top of the Xcode window,
   next to "Ace", click the device name and pick your iPhone (not a
   Simulator). The speech engine runs CPU-only in the Simulator and is not
   representative; always use the real phone.

## Every time you want to run it

1. Press the **Run** button (▶) or ⌘R. The first build takes a few minutes.
2. The first time, the phone shows "Untrusted Developer". On the phone go to
   Settings → General → VPN & Device Management → your Apple ID → Trust.
   Then press Run again.
3. The app opens on the **Ace** screen with two sections: Assistant and Debug.

## Using the Debug screens

**Speech test**
1. Pick a model. Start with `base.en`: it is small and quick. Tap **Load
   model**. The download shows a percentage, then "Preparing model for this
   device", which can take a few minutes the very first time (Apple's chip
   compiles the model once; later launches are fast).
2. Type a label, tap **Record**, say a job like you would on the phone, tap
   **Stop**. The clip is saved in the list.
3. Tap **Transcribe** on the clip. The transcript and the seconds it took
   appear under the clip. Tap **Transcribe again** to repeat; try the
   `large-v3 626MB` model when you want the accuracy comparison.
4. Tap **Use in Claude test** to carry the transcript over.

**Claude test**
1. First add the key: Ace → Assistant → API key → paste → Save key. It is
   stored in the phone's Keychain only.
2. Open Claude test. The transcript is already there; edit it if you like.
3. Tap **Fill the form with both models**. Haiku and Sonnet run at the same
   time. Each shows its time, token counts, the filled-in fields, and any
   yes/no questions it raised. Flagged fields are shown in the warning color.

## If something fails

- **"No such module 'WhisperKit'"**: the package did not download. File →
  Packages → Resolve Package Versions, wait, then Run again.
- **Signing errors**: redo step 4 and make sure a Team is selected.
- **"Could not launch" or "Untrusted Developer"**: step 2 under Every time.
- **The app installed but disappears after a week**: that is normal with a
  free Apple account (apps from Xcode expire after 7 days). Press Run again.
  A paid Apple Developer account removes this limit; see `platform-facts.md`.
- Anything else: send me the full error text from Xcode's red marker or the
  Report navigator (⌘9).

## What I know and don't know about this build

- I verified: the project compiles for iPhone and for Mac on GitHub's cloud
  Mac with Xcode 26.6 (the "Build check" under the repository's Actions tab,
  run #1, 2026-10-18). Every push that touches the app re-runs that check.
- I verified: the code was reviewed against the WhisperKit 1.1.1 source and
  the current Anthropic documentation.
- I don't know: how it behaves on a real phone. Compiling is not running.
  Nothing has run on a device yet; the first time is on your iPhone.

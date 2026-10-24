# Ship audit, Oct 24 2026: what was fixed

98 agents read the app, the server and the docs. A second agent checked
each finding, which left 90 confirmed: 3 critical, 7 high, 36 medium and
44 low. Four fix agents and the main session fixed them the same day. The
numbers below are the audit's own numbers.

Everything below was built for iPhone (Simulator) and Mac, and the sheet
tests pass (62 checks). "Simulator" means it was also tapped through in
the iPhone Simulator. Nothing was run on the Mac by hand.

## Critical and high
- **1–3, 7, 10, 41, 47, 80. Beta switch on, open relay.** Fixed. `Beta.isBeta = false`; the relay address file is out of the app. The Assistant goes through the Ace server with the sync code (`/v1/claude`), and `check-before-sending.sh --business-copy` really checks now. Simulator: Settings says "Through the Ace server".
- **4, 28, 36. Overweight rate per device.** Fixed. A new `setting` sync record carries the rate and the crew's working days. Simulator: synced in both directions and used for the pickup charge. Rentals keep the rate they were picked up with.
- **5, 11. Old test data re-uploaded to a fresh server.** Fixed. When the server ID changes, the device holds its records and Settings › Sync offers Send or Remove. Simulator: checked after a wipe. A device that never synced still sends what it has, by design.
- **6, 44. A sort plus Resume scrambles jobs.** Fixed on the server. A pure re-ordering is recognised and only re-paired; a sort mixed with edits pauses with "undo the sort". Tested against the stand-in Google only.
- **8, 9. A deleted job stays open on the Mac.** Fixed: the page clears, and nothing writes to a deleted job. Built only.

## Medium (fixed)
- **12, 74.** A copy with the built-in server shows "Server: Built in".
- **13.** Going to the background waits for a running sync, then sends what's left.
- **14, 42.** More than 10 deletions from Ace pause before reaching the sheet.
- **15.** Disconnect and Connect keep the row tags. Error text offers "Connect Again…".
- **16.** Blank dates in the sheet are filled in before Ace moves rows.
- **17.** Totals rows are skipped (partly: a SUM range is a setup-day check).
- **18.** Light reds and theme reds read as unpaid. The theme read has not been tried with real Google.
- **19.** Locking the phone mid-request no longer kills the Assistant's request.
- **20.** Speech that errors at the end keeps the words heard, and the audio is released.
- **21.** An end time before the start asks, instead of throwing away every edit.
- **22.** Undo after a delete does nothing.
- **23.** The check number is kept while notes are being typed.
- **24, 37.** The job page stays open after Mark done / paid. Simulator: from the Next card.
- **25.** Duplicate Google Calendar events are settled to one.
- **27.** Two rentals on the same day no longer share an ID.
- **29, 40.** The month grid fits at large text. Simulator: at the largest text size.
- **30.** Resume asks first, on the Mac only.
- **31.** ⌘F works from any screen.
- **32.** Menu commands act on the front window only.
- **33, 64.** ⌘Z undoes typing again.
- **34.** ⌘Q saves an open job or quote.
- **38, 63.** Undo puts back only what it changed. Simulator: Mark done, then Undo.
- **39.** The job site is shown instead of the home address. Simulator: on the Next card and the job page.
- **43, 46.** The docs say what is really built.

## Low (fixed)
- **51.** Crew hours and dumpster history don't count toward the deletion hold.
- **53.** Missing links are restored when the record arrives.
- **54, 55, 56.** Sheet write safety, tag numbers, and picking the right tab.
- **59, 60.** Voice not ready or microphone off is now explained.
- **65.** An old check number is removed when paid another way.
- **67, 68, 69.** Reopening a booked quote asks first. A deleted customer leaves the job page. 28 tons asks "Was it 2.8?" (Simulator).
- **70, 71, 72, 73.** Overdue updates at midnight, Extend counts from today, due-back can't be before drop-off, and pounds are not rounded.
- **75.** Menu items are greyed out with no window open.
- **78, 79.** A bigger Undo button, and a readable green in dark mode.
- **82.** Built copies and signing files are git-ignored.
- **87.** A sheet test that couldn't fail now can.
- **Extra.** A setup script had the live server address in it; it moved to a git-ignored file.

## Left as they are (low, or waiting on an answer)
- **26.** An offline dumpster pickup can be undone by a later edit elsewhere. It needs a rule in sync; rare.
- **45, 58.** Red fills that come from conditional formatting, and future jobs showing red. These wait on how Ashley colours her sheet.
- **48, 49, 76.**
  - Test settings in Settings: these are hidden on a live copy.
  - The welcome guide's Import shortcut.
- **50 (part), 52, 57, 62, 66, 77, 81, 83–86, 88–90.** Small or doc-only. 90 was partly done in HANDOFF.
- **The month title wraps to two lines at the largest text size.** Readable.

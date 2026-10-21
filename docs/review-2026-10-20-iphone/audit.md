# iPhone audit, Oct 20 2026

How it was done: 13 reviewers (one per area, phone only) read the code and the screenshots in this folder; every finding was checked by two skeptics (facts, and would Alex or Ashley really hit it) and kept only if both agreed; five judges (Alex, Ashley, an iPhone designer, a field-service consultant, a visual designer) scored the app; one lead merged it all. Same method as the Oct 19 Mac audit.

Everything here comes from Simulator screenshots and reading the code. Nothing was run on a real iPhone. Claude checked the top items against the code by hand (marked *checked*).

**Score: 6 out of 10** (all five judges).

On a phone, Ace already looks clean, calm and like a real Apple app. The five tabs make sense, nothing important is more than two taps away, the dumpster tiles and the Labor "Today" list are close to right, and nothing looks like AI. It is not yet the right design for Alex in the truck. Several of his most-used buttons sit off the right edge of the screen (Directions on the job page) or are smaller than Apple's minimum tap size. Logging a pickup weight means scrolling past a long form. A few one-swipe actions delete or change things with no question asked. Ashley is better served, but booking from the phone still loses typing too easily: a swipe down closes the form and everything is gone. Some real bugs would bite on the first week of use: the Calendar and Labor tabs reopen on yesterday after the phone sits overnight, hours can be saved to the wrong day, and the microphone can stay on after the Assistant sheet is swiped away. All five reviewers gave it 6 out of 10. The fixes below are mostly small, and doing the "do now" list would likely make it an 8. Everything here was judged from Simulator screenshots and from reading the code. Nothing has been built after these findings or run on a real iPhone.

## Fix now (safe, no decision needed)

### 1. Ask before a swipe deletes a job, a customer, or marks a quote lost *(checked)*

A long sideways swipe, easy with gloves or a bumpy ride, deletes a job (and its calendar event) or a customer, or marks a quote lost. It happens at once, with no question and no undo. The job, customer and quote pages all ask first; the phone lists do not.

How: Ace/Jobs/JobsView.swift (JobSwipeActions): change the trailing swipe to .swipeActions(edge: .trailing, allowsFullSwipe: false). Delete sets a @State flag that opens the same confirmationDialog("Delete this job?") JobEditView uses, and only that dialog calls job.remove. Ace/Customers/CustomersView.swift: replace .onDelete with a per-row trailing swipe (allowsFullSwipe: false) that sets a pendingDelete customer, and one confirmationDialog on the List with the Edit sheet's wording ("Delete this customer? Their jobs are kept without a customer."). Ace/Quotes/QuotesView.swift: make the trailing swipe allowsFullSwipe: false, and have Lost open "Mark this quote lost?" before calling markLost. Leave the leading Done swipe as a full swipe.

### 2. Let the phone find lost quotes again

On iPhone, a quote marked lost can never be seen again, even by search, yet the confirmation promises "Search still finds it". With no sync yet, a quote lost by mistake is gone on every device.

How: Ace/Quotes/QuotesView.swift: add lostMatches = QuoteList.shown(filtered, status: .lost) and, after the main sections, if !searchText.isEmpty && !lostMatches.isEmpty, a Section("Lost") listing row(quote) (rows already get the Reopen swipe). Change the empty-state check so "No matching quotes." does not show above a Lost match. Same file: QuoteRow(quote:, showStatus: filter != .booked) so every Booked row doesn't repeat the green pill.

### 3. Turn the microphone off whenever the Assistant sheet closes *(checked)*

Only the Cancel button stops listening. A swipe down leaves the mic on (orange dot, battery drain), and the next note picks up the old audio and words, so the wrong job can be filled in.

How: Ace/Assistant/AssistantView.swift: add .onDisappear { stop the recorder if recording; listeningLive = false; Task { await engine.cancelListening() } }. Make Cancel call cancelListening() instead of stopListening(). Ace/Speech/WhisperKitEngine.swift startListening: replace guard !isListening else { return } with a reset that stops the old stream and clears the buffer, liveConfirmed and liveTentative before starting fresh. Add .interactiveDismissDisabled while a filled step form is showing, so a swipe can't throw away a reviewed job; Cancel there asks "Discard this job?". Needs a check on a real iPhone: tap to listen, swipe away, confirm the orange dot goes off.

### 4. Release the audio after listening, and handle a call that interrupts a note

The audio session is never given back after live listening, so music or a podcast over the truck's Bluetooth stays cut off and the car can stay in phone-call mode. A call during a hands-free note leaves the screen saying "Listening." while nothing is recorded.

How: Ace/Speech/WhisperKitEngine.swift (#if os(iOS)): after the streamer stops in stopListening and cancelListening, call AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation). Use one category and option set (playAndRecord, allowBluetooth, defaultToSpeaker) for both the live path and Ace/Speech/AudioRecorder.swift. Observe AVAudioSession.interruptionNotification: on .began while listening, end the note the same way letting go of the button does, keeping what was heard. Mark it unverified until tried on a real iPhone with AirPods and the truck's Bluetooth.

### 5. Hours typed in a box go to the day they were typed for *(checked)*

If Alex types Chris's 8 for Monday and then taps Tuesday in the week strip before Done, the 8 is saved on Tuesday and Monday is left empty. Pay comes out wrong with no sign of it.

How: Ace/Labor/LaborCells.swift (HoursCell): add .onChange(of: day) { oldDay, _ in if focused { Labor.setHours(Labor.parseHours(text), for: worker, on: oldDay, in: context) }; text = stored }. Make sure the commit that runs when focus ends can't then write to the new day. Optionally also commit when scenePhase leaves .active while focused. Don't rely on .id(day).

### 6. Calendar and Labor move to the new day after the phone sits overnight *(checked)*

iOS keeps the app in memory overnight, so next morning the Calendar day card shows yesterday's jobs under yesterday's date while the top figure counts today. Labor shows yesterday's boxes, inviting today's hours to be typed over yesterday's.

How: Ace/MainView.swift: add @State lastActiveDay = Dates.startOfToday() and a rollToTodayIfDayChanged() that, when the day has changed, sets calendarDay to today. Call it in the existing .onChange(of: scenePhase) on .active and from .onReceive of .NSCalendarDayChanged. Ace/Labor/LaborView.swift: the same check on its own day (its own scenePhase and lastSeen), plus a plain "Today" toolbar button when another day is chosen, as Calendar has. Must be checked on a real iPhone left in the background overnight.

### 7. Deleting a job or quote right after editing it no longer writes back onto the deleted record *(checked)*

After an edit, Delete runs and then the page's "save on leaving" code writes the edits onto the deleted record. That can crash the app or put a ghost event back on the Calendar for Jobs.

How: Ace/Jobs/JobEditView.swift and Ace/Quotes/QuoteEditView.swift: add @State private var deleted = false, set it first in delete() (before remove or onDeleted), and guard onDisappear (and the isDone/isPaid onChange handlers) with !deleted. Also set original = form there as a second guard. Check in the Simulator: edit a note, Delete, confirm no crash and no event left in the jobs calendar.

### 8. Going Back from a job you just double-booked asks the overlap question first

Leaving a job page saves it, which is deliberate (like Notes). But that path skips the "This overlaps... Save anyway?" check, so a double-booking goes in silently, against the CLAUDE.md rule.

How: Ace/Jobs/JobEditView.swift, iOS only: while !isNew && hasChanges && timingChanged && !overlapping.isEmpty (and not yet answered), use .navigationBarBackButtonHidden(true) and a leading "Back" button that runs trySave(), so the existing alert asks "Save anyway" / "Change the time". In every other case, Back and swipe-back stay as they are. Add one line to docs/decisions.md: "iPhone: leaving a job page saves it; if the change makes a new overlap, Back asks the overlap question first." Leave the Mac alone.

### 9. Stop a swipe down or Cancel from throwing away a half-typed booking

Ashley fills in a new job, quote, customer or person while a caller waits, and one brush of the sheet or a tap on Cancel loses it all. Reminders and Calendar ask first.

How: JobEditView and QuoteEditView: .interactiveDismissDisabled(isNew && hasChanges) (hasChanges compares to the prefill, so an untouched sheet still swipes away). Ace/Customers/CustomerEditView.swift: make CustomerFormData Equatable, keep an original copy, same modifier. Ace/Labor/WorkerViews.swift NewWorkerSheet: hasChanges = name or rate typed. In all four, Cancel opens confirmationDialog("Discard this job?" / quote / customer / person) with "Discard changes" (destructive) and "Keep editing" when there are changes, and closes at once otherwise. A blocked swipe just springs back; the question comes from Cancel.

### 10. Show every action button on the job, quote and customer pages *(checked)*

The header's action row scrolls sideways with no hint. On the widest iPhone, Directions is already off-screen on the job page and cut in half on the quote page. On the iPhone 17e, Call and New job are cut too.

How: Ace/Support/Design.swift DetailHeader, inside #if os(iOS): replace the horizontal ScrollView and .scrollClipDisabled() with a small wrapping Layout (about 30 lines, next to the other shared pieces, Space.s spacing) so buttons move to a second line instead of running off. FlowRow from Ace/Assistant/FollowUp.swift can move there. Keep the Mac's ScrollView. Keep labels on one line. In JobEditView, also make the Customer section's Phone and Address rows tappable (call / Maps) with a long-press Copy. Re-take iphone-06, -09 and -17 on the 17e at normal and largest text.

### 11. Make every tap target at least 44 points *(checked)*

The action capsules (Call, Directions, Mark done, Mark paid, Mark picked up, Book job), Hold to talk and the week arrows are about 32-35 points, under Apple's 44-point minimum. That is hard with gloves in a moving truck.

How: Design.swift ActionButtonStyle: under #if os(iOS), add .frame(minHeight: 44) after the padding and before the Capsule background (the capsule grows a little; the Mac is unchanged). Ace/Assistant/HoldToTalk.swift: the same, plus a large option (full width, min height 56, title3 semibold) used for the main recording button in AssistantView, on its own row. Ace/Calendar/WeekStrip.swift: both arrows .frame(width: 44, height: 44).contentShape(Rectangle()).

### 12. Fix the small hold-to-talk bugs

On first use, the microphone permission box cancels the touch, and the button then says "Release to send" with nothing held, and the next press does nothing. "Hold to answer" never checks permission, so a denied or busy microphone reads as "Nothing heard". Auto-Lock can stop a hands-free note partway.

How: HoldToTalk.swift: keep the @State logic and add @GestureState fingerDown with .updating; .onChange(of: fingerDown) clears pressing and pressedAt on a cancelled touch, and switches to "Tap to send" if the mic is already on. AssistantView.startRecording: if permission was undetermined, ask and return to idle with "Microphone on. Hold to talk.". FollowUp.swift MissingSection: if permission is denied, hide Hold to answer and show "Microphone access is off. Turn it on in Settings › Privacy & Security › Microphone, or tap Type it.". WhisperKitEngine: replace try? on startStreamTranscription with do/catch and a startFailed flag that the views report as "The microphone did not start.". AssistantView (iOS): UIApplication.shared.isIdleTimerDisabled = true while recording, back to false on every exit.

### 13. Keep a failed voice note, and say plainly what went wrong

With no signal the note lives only on screen. Close the sheet and it is gone, and the error text shows raw service messages ("error 529. Overloaded", "invalid x-api-key") that Alex can't act on.

How: AssistantView.ask catch: if typedNote is empty, set typedNote = transcript. Save the note to @AppStorage("assistant.unsentNote") before sending, clear it on success or Start over, and restore it in onAppear with a caption "Not sent yet.". Catch URLError (.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost) and show "No signal. The note is kept. Send again when there is signal.". Ace/Assistant/ClaudeClient.swift errorDescription: 401/403 → "The Assistant key on this phone isn't working. Ask Kyle. (401)"; 429/5xx → "The Assistant is busy. Tap Send again in a minute. (529)"; unreadable → "The answer could not be read. Send again."; refused → "This note could not be handled. Try saying it another way.". Keep the raw detail in a DEBUG log only, or as a code at the end, so Kyle can still diagnose.

### 14. Assistant review fixes: house numbers, repeated questions, the date gap, pastes

"42B" never clears the "No house number" question, and a ZIP code counts as a house number. "Fix it" on an address question opens nothing. A Skip in the Missing card is forgotten, so Save asks again. Changing only the time quietly clears the "No date" question. Pasting text with line breaks sends at once. The house-number box is labelled just "Number" right under the phone question.

How: Ace/Assistant/AssistantMatching.swift SpokenAddress: one isHouseNumber rule (^[0-9]+[a-z]?$), used for houseNumber and streetWord. A 5-digit last word is not a house number. JobReviewView.answeredNo: pick(gap == .address && gaps.contains(.houseNumber) ? .houseNumber : gap). Lift skipped: Set<Gap> from MissingSection (FollowUp.swift) to JobReviewView as a binding, and leave out the code question and Claude's matching question for skipped gaps (houseNumber covers "address"); keep past-date and double-booking questions. JobReviewView: replace .onChange(of: date) with a check that only a change of day sets dateSet. AssistantView typed note: count Return as Send only when exactly one newline was added; otherwise swap newlines for spaces and keep editing. JobReviewView.swift:135 and AssistantQuoteViews.swift:122: prompt "House number". FollowUp.swift Gap.question: "No house number. What's the house number?" and "No phone number. What's the phone number?". In field(), don't repeat Claude's footnote under a field already listed in Missing.

### 15. Assistant dumpster and hours screens: no silent wrong picks

A drop-off of a dumpster still marked out quietly preselects a different dumpster, with false wording. "Pereira" attaches to whichever Pereira sorts first. A pickup with no weight saves with one tap, losing the overweight charge. An hours note with two Chrises or a retired worker adds a duplicate person. Lines without hours are dropped without saying so.

How: Ace/Assistant/DumpsterDropoffView.swift: preselect only a spoken dumpster that is in the yard (keep the single-dumpster case); otherwise start at 0 with Text("Choose").tag(0), and use the notes "Dumpster 4 is still out at <customer>. Mark it picked up first, or choose another.", "There is no Dumpster 9.", "No dumpster number was said. Which one went?". Same for the swap screen (AssistantDumpsterViews.swift). Customer: auto-pick only with one candidate (or one with a booked drop-off today); otherwise show WhichCustomerList. DumpsterPickupView: put the weight section first and, when no weight was given, ask "No weight entered. Mark Dumpster N as picked up without one?" (same on Swap). AssistantLaborView: when several active people or a retired person match, show a Who picker ("Two people named Chris. Which one?", "Tyler Gomes is retired. Bring him back?"). Name skipped lines in the save message ("Hours saved for 3 people. Not saved: Marcus."). AssistantMatching.matchCustomers: replace the raw substring tier with whole-word matching.

### 16. Dumpster page: pickup first, plus Call and Directions

At every pickup Alex has to scroll past the header, an unlabelled size/note box and a repeat of the header's facts before he reaches the weight box, which on the largest iPhone is below the fold. The page has no way to call the renter or drive there.

How: Ace/Dumpsters/DumpsterDetailView.swift, when dumpster.isOut: order is header, then pickupSection (with a read-only Agreed weight row above the weight box), then a shorter Current rental (drop Customer, Location and Price, which the header shows; keep Dropped off, Due back, Agreed weight, notes), then the size/note section, then Past rentals. Header: hasActions: dumpster.isOut with Call (customer.phoneURL) and Directions (dumpster.location, falling back to the customer's address), with .buttonStyle(.action()). Make the Customer row a NavigationLink to CustomerDetailView. Leave the in-the-yard order as is.

### 17. Dumpster page: labels, warnings, confirmations and smaller fixes

Fields show only grey hints, so "450" and "2" on a drop-off are unlabelled. A "don't send out" note is invisible on the tiles and can run off the header card. With no agreed weight, an overweight pickup shows nothing at all. Choosing a different customer keeps the first customer's address. Nothing says the save worked. A round charge shows as "$100.00".

How: DumpsterDetailView: LabeledContent rows for Actual weight (unit tons), Price ($), Agreed weight (tons) in drop-off and pickup, and the same in DumpsterDropoffView and DumpsterPickupView, keeping each field's title for VoiceOver. Size/note section: header "About this dumpster", footer "Stays with the dumpster between rentals.", labelled Size and Condition rows, and .onChange setting updatedAt. When a weight is typed and agreedWeightTons is nil: an orange line "No agreed weight on this rental. No overweight charge.", the Agreed weight row editable, and the confirm question saying so. Track autoFilledLocation so a customer change replaces an auto-filled address. Add a "Picked up" DatePicker (default today, no future dates, not before drop-off) and pass on: (Assistant pickup too; leave swap). After save, show one line until leaving: "Dumpster 1 picked up. Overweight charge $137.50." / "Dumpster 3 dropped off at 7 Bay Rd.". Add a fullWidth option to ActionButtonStyle (min height 50) for Mark picked up and Mark dropped off. Header: condition note on its own wrapping warning line, not a fixed pill. Ace/Calendar/BoardCards.swift DumpsterTile: show the condition note as a Tint.owed line on every tile. Ace/Data/Models.swift Overweight.charge: round to cents.

### 18. Jobs list: Unpaid rows, mark paid by swipe, search across all lists *(checked)*

The phone never tells a row which list it is in, so every Unpaid row shows Done + Unpaid pills that cut off the date and town, and "days owed" never shows. Marking a job paid needs opening the job, and in Unpaid the right swipe says "Not done". Search only looks in the chosen segment, so a past customer shows "No matching jobs.". The Calendar card's owed mark can never appear.

How: JobsView.row: JobRow(job:, showDate:, context: filter). JobSwipeActions: pass the filter; leading "Paid" button (dollarsign.circle, Tint.paid) first in Unpaid (and second elsewhere), saving like JobQuickMenu, with a success haptic through a closure that toggles a @State on JobsView. Change the Done tint off green. Add .contextMenu { JobQuickMenu(job:) } to JobsView.row and CustomerDetailView job rows. While searchText is not empty, ignore the segment and show "Upcoming" and "Past" sections; prompt "Name, phone, address or notes". Ace/Jobs/JobsFilter.swift JobDay.title: "Today" / "Tomorrow" / "Yesterday" in place of the long date. Ace/Calendar/BoardCards.swift JobCard: check owedAmount > 0 before isDone, so the orange $ shows.

### 19. Job page: one control for Paid, sensible time default, customer row that opens the customer *(checked)*

Mark paid saves at once while the Paid switch below waits for Save, and they can disagree on screen. Turning on "Set a time" for an untimed job starts at 12:00 AM. Tapping the teal customer name opens a 600-name picker where one stray tap moves the job to someone else. Mark done and Mark paid look disabled (grey on grey).

How: Ace/Jobs/JobEditView.swift: show Toggle("Paid") only when isNew, and make the header price colour read job?.isPaid ?? form.isPaid; add one line to docs/decisions.md. .onChange(of: form.hasTime): if on and form.date is exactly midnight, set it to JobTimes.combine(day:, time: Dates.nextFullHour()) and refresh the end suggestion if none is set. iOS, existing job: the Customer row becomes a NavigationLink to CustomerDetailView, with "Change customer" as a plain row below and in a context menu. Ace/Customers/CustomerPickerView.swift: optional confirmChange; when an existing job or quote picks a different customer, ask "Move this job to Al Gallo?" (Move job / Cancel); show the current customer first with its checkmark; rows use .buttonStyle(.plain) so names are black and details grey, not teal. Not-yet buttons use .action() (accent); Done uses .action(Tint.done) grey, Paid stays green.

### 20. Quotes: smaller fixes

The "4 open" tile can open on the Booked list. Reopen on a booked quote asks nothing and keeps the job, so booking again makes a second job. Deleting right after editing can crash. "Quote saved." never shows after editing from the list. Save stays lit after Book job. The tile reads "0 open / None priced". The quote price shows a bare "1200".

How: CalendarView: wrap onShowQuotes so it sets quotesFilter = .open before pushing; update the stale comment in QuotesView. QuoteEditView: when quote.job != nil, Reopen asks "Reopen this quote? The job on Tue, Oct 21 stays on the schedule.", and Book job asks "This quote already has a job on Tue, Oct 21." with Open that job / Book another / Cancel. Add original = form in booked(with:). The deleted flag as in the job fix. QuotesView: push a QuoteRoute(quote:) wrapper with its own destination that posts "Quote saved.". TodayFigures.openQuotesDetail: "None waiting" when empty. Price row in QuoteEditView and JobEditView: LabeledContent("Price") with a "$0" prompt on iOS.

### 21. Customers: search, keyboards and phone numbers

Typing "42 elm" matches everyone whose phone contains 42. "souza lakeville", "al souza" and "conceicao" find nothing. A pasted "+1 (508)..." doesn't match the stored number and creates a duplicate. Names come out "Lisa souza" with autocorrected surnames. A 9-digit phone saves silently. "New customer" after a failed search starts blank.

How: Ace/Support/Formatting.swift: PhoneFormat.digits(_:) (digits only, drop a leading 1 from 11 digits) used by PhoneFormat.formatted, Customer.phoneDigits, matchCustomers, existingCustomer and the search filters; PhoneQuery.digits(_:) that returns digits only when the query is mostly a phone number (3 or more digits after stripping spaces, dashes, dots, parentheses, +); PhoneFormat.problem(_:) → "Phone number has 9 digits, not 10." shown in warning colour under phone fields (still saves). Ace/Data/Models.swift: Customer.matches(_:) where every word must match name or address (localizedStandardContains, so accents are ignored) or phone digits, used in CustomersView and CustomerPickerView; apply the same per-word rule in JobSearch and QuoteSearch. An iOS-only wordsCapitalized() helper (textInputAutocapitalization(.words)) plus .autocorrectionDisabled() on customer and crew name and address fields; do not add textContentType. CustomerEditView: optional prefill; in the picker, label the top row New customer "Souza" and pass the search text as name or phone. Change the 508-555-0123 prompt to "Phone number" (CustomerEditView, WorkerViews).

### 22. Customer page wording and layout

It says "Billed $0 · Nothing priced" above a $550 job. The tile detail is cut ("Last Sun, Nov 8, 2…"). The name shows twice at the top. Past job rows cut off the time.

How: Ace/Customers/CustomerDetailView.swift billedDetail: keep "Has a dumpster now" and "$X a job", otherwise "Nothing billed yet". jobsDetail: "Last Nov 8" this year, "Last Nov 2024" for past years; "Has a dumpster now" → "Dumpster out". JobRow: when showCustomer is false, the date line may use 2 lines. Inline navigation title (see the polish item).

### 23. Labor: retired crew still counted, hours sanity check, labels, delete rule

Retiring someone mid-week removes the money still owed to them from this week's totals and from past weeks. "85" for 8.5 saves as 85 hours, and a stray dot erases a day. The person page shows a bare "20" for the rate. Delete is offered for a salaried person with months of work. The four figures push the day's hours boxes off the first screen.

How: Ace/Labor/LaborView.swift: weekPeople = crew plus retired hourly people with hours in the shown week; show them in the day and week cards with a "Retired" caption; pass them to LaborFigures only for Hourly hours and Hourly pay (Working today and Crew stay on the active crew). Reorder to WeekStrip, day card, figures, This week, and update docs/labor.md. Ace/Labor/LaborCells.swift HoursCell.commit: non-empty text that doesn't parse restores the saved value; over 24 is not saved, the old value comes back with a warning haptic (put the rule in Labor.validHours, also used by AssistantLaborView). Ace/Labor/WorkerViews.swift: LabeledContent rows Name, Phone, "Rate, $ an hour"; Delete only when there are no entries and (not salaried or created today), with the message "Their hours and days are removed from past weeks. Retire keeps them."; in the rate onChange, write and touch() only when the parsed value differs.

### 24. Calendar page fixes

In Month view, the chosen day's jobs sit below the screen. Three of the four figures look tappable but do nothing. At the largest text size the figure details are cut mid-word. The Today figure and the day header give different counts once a job is done.

How: Ace/Calendar/CalendarView.swift: wrap in ScrollViewReader, put .id("calendar") on the calendar card, and in Month mode scroll it to the top when a day is picked or Month is chosen. TodayFigures: optional onShowOwed and onShowDumpsters next to onShowQuotes (the Mac passes none). Move the Jobs filter up to MainView as a binding so Owed opens Jobs on Unpaid; Dumpsters switches tab. Add a showsChevron option to StatTile for tiles that open something. Ace/Support/Design.swift StatTile: .lineLimit(typeSize.isAccessibilitySize ? 3 : 1). Today tile: once any job today is done, show "1 job left" / "$450 to go · 1 done" ("All done" when finished); the day header adds "· 1 done". AssistantRecords.totalsLine: use Labor.week(containing:) for "done this week", and add the open/done split.

### 25. Readability in sunlight and at large text

Warnings use Apple's pale orange (about 2:1). Dumpster tile details and job-card times are about 3:1. The dumpster number stays a fixed 30 pt, so at large text it is the smallest thing on the tile. Greyed job badges are white on light grey. Customer rows, detail headers and the Missing card's buttons don't rearrange at large text.

How: Design.swift: add Tint.warning = Tint.owed and replace raw .orange / Color.orange in the Assistant files, JobTimes.swift and DumpsterDetailView (the overweight amount uses Tint.owed); .action(.orange) → .action(Tint.warning). DumpsterTile: customer line in .primary, address and rental lines in Color.primary.opacity(0.7), a darker light-mode shade for due-today and overdue text only on the tile, the number via @ScaledMetric(relativeTo: .largeTitle) capped at about 56, and lineLimit 3 at accessibility sizes. JobType.tint: Color(light:dark:) pairs (darker blue, indigo, purple, brown in light mode). TypeBadge muted fill: solid Color(.systemGray). DetailHeader and CustomerRow: AnyLayout switch to a stack at accessibility sizes, as JobRow does (price on its own line, title up to 3 lines; CustomerRow hides the avatar). FollowUp.swift Missing buttons and AssistantView's Send again / Start over: ViewThatFits or AnyLayout to stack at large sizes. Check on the 17e at the largest size, light and dark.

### 26. Copy and label clean-up

Small wording slips make the app look unfinished: "Overweight charge,..." is cut off in Settings, Assistant screens use "New Job" while the rest say "New job", two "Skip" buttons do different things, the Dumpsters summary says "1 out" when three are out, and the toolbar Assistant button shows no word, against CLAUDE.md.

How: Ace/Settings/SettingsView.swift: label "Overweight rate", value "$" + field (capped width or fixedSize) + "per ton" in secondary. Ace/Assistant/AssistantPlan.swift step titles and the Assistant buttons in sentence case ("New job", "Dumpster drop-off", "Mark picked up", "Book job", "Delete job"). Bottom-bar Skip → "Skip step", Missing-card Skip → "Not now" (update docs/assistant-actions.md). Ace/Dumpsters/DumpstersView.swift summary: "3 of 6 out · 1 overdue · 1 due today" ("6 in the yard" when none out). Ace/MainView.swift: Assistant label as HStack { Image("apple.intelligence"); Text("Assistant") } with .accessibilityLabel, no tint; use icon only at accessibility sizes if it doesn't fit; check all five tabs on the 17e.

### 27. Clear all data removes the calendar events and says what it deletes

Clear all data deletes crew, hours, quotes and rental history too, but only mentions customers, jobs and dumpsters, and it leaves every job event behind in the shared calendar.

How: Ace/Data/SampleData.swift clear(): call CalendarStore.shared.jobDeleting(job) for each job before deleting; in Load sample data, clear before setting the jobs calendar to None. SettingsView dialog: "Delete all customers, jobs, quotes, dumpsters, people and hours on this iPhone?" with "Delete everything" and "This cannot be undone.". Whether to hide the whole section is for Kyle (see proposals).

### 28. Directions open driving directions

Directions opens an Apple Maps search pin, sometimes a list of towns, so it takes extra taps in Maps while driving.

How: Ace/Data/Models.swift Customer.directionsURL: query items daddr=<address> and dirflg=d, built by a shared helper (for example Maps.directions(to:)) that the dumpster page also uses. Update the doc comments. Apple Maps only for now.

### 29. Small visual polish that changes no workflow

Detail pages repeat their title (large "Job" over "Linda Johnson", "Al & Lisa Souza" twice), pushing content down on the small phone. Card insets differ (12 vs 16 points), so text doesn't line up from card to card.

How: #if os(iOS) .navigationBarTitleDisplayMode(.inline) on CustomerDetailView, DumpsterDetailView, JobEditView, QuoteEditView and WorkerPage (tab roots keep large titles; new job/quote sheets go inline too). Ace/Calendar/BoardCards.swift BoardListCard: on iOS use .padding(Space.xs) so title and rows start 12 points in, like the other cards.

## Needs Kyle's decision

### 1. Put the overweight charge on the bill (half a day)

It is worked out at pickup and then goes nowhere: it is not in Owed, the Unpaid list or the customer's balance. On a dumpster business this is the money most easily lost. HANDOFF already lists it as waiting on you.

How: One question for you: does Ashley bill the overweight on the pickup job, or as its own line? Then change Dumpster.markPickedUp once (all three pickup paths use it): add the charge to that customer's open pickup job (or make a done, unpaid pickup job), add a note, and the confirmation says "Overweight $137.50 added to Scott Johnson's pickup job.".

### 2. Link a dumpster job to the dumpster itself (half a day)

A "Dumpster drop-off" job and Dumpster 3 are separate records. Doing one doesn't update the other, so Alex enters things twice and the tiles drift (Dumpster 1 shows overdue while a pickup is booked for tomorrow). Only the Assistant links them today.

How: On the dumpster page, find the booked drop-off or pickup job the way the Assistant does, show its time and notes, offer "Also mark the booked job done" (on by default), and fill price and location from it. A bigger version: a "Drop off dumpster" / "Pick up Dumpster 1" button on the job page itself.

### 3. Fix and undo dumpster mistakes, and swap from the dumpster page (half a day)

After Mark picked up or dropped off nothing can be corrected: a wrong tile, a mistyped weight (28 for 2.8) or wrong price stays in history. A swap without signal means a full pickup plus a retyped drop-off.

How: Editable price, agreed weight and location on a rental that is out; "Cancel drop-off"; past rentals open a small sheet to fix weight, dates and price, delete, or "Undo pickup" for the newest one. Add a "Swap for another dumpster" button that reuses one shared swap function.

### 4. Hide the Debug section and model settings on Ashley's and Alex's phones (an hour)

Settings shows Debug (Speech test, Claude test, Load sample data, Clear all data) plus Effort and Speech model. This is HANDOFF open question 7, and you still need them for the step 1 tests.

How: A hidden switch (tap the Version row seven times, or an Xcode launch argument), off on their phones, that shows the Debug section and the Claude model, Effort and Speech model pickers.

### 5. A bigger, thumb-reachable Assistant (half a day)

The Assistant is the hands-busy way to log things, but it sits in the top-right corner of a 6.9-inch phone and Hold to talk is near the top of the sheet. Three judges want a bar above the tab bar; CLAUDE.md asks for an understated button.

How: Option A: keep the toolbar button and pin a large Hold to talk button at the bottom of the Assistant sheet, with the help text cut to one line plus a "More" disclosure. Option B: an iOS 26 bar above the tab bar that you hold to talk from any tab. The Lock Screen and Action button entry (step 8) still comes later.

### 6. Mark paid asks cash, check or card (an hour)

Paid is the moment at the curb, but marking paid never records how, so the payment type stays "Not set" and Ashley can't reconcile the cash.

How: Mark paid (header, swipe, long press) opens three big buttons: Cash, Check, Card, with the amount prefilled. A partial payment is possible later.

### 7. A Text button for "on my way" and booking confirmations (an hour)

Texting the customer is the most common thing after driving. Today only the Assistant can do it. This is Alex's own Messages, not customer-facing.

How: A Message button next to Call on job, customer and dumpster pages, opening Messages with a short editable line ("Ace Junk Removal: on the way, about 20 minutes.").

### 8. Morning reminders for dumpsters due back or overdue (half a day)

Nothing reminds anyone unless the app is opened. A refutation noted the app does open on today and asking for permission adds a prompt, so this is your call.

How: A local notification at a chosen time ("Dumpster 2 is due back today: Tom & Sue Keane, 119 Winthrop St."), one switch in Settings. It only fires on the phone that has the data until sync is built.

### 9. Today as a run sheet: address on cards, next stop on top (half a day)

Calendar job cards show no address, so Alex has to open each job to know where to go. At the largest text size, today's jobs are several screens down below the figures.

How: Add street and town to each card with a small map button; optionally a larger "Next" card for the next not-done job. At accessibility sizes, put the day card before the figures.

### 10. Trucks and job-site addresses (a day)

About 5 trucks, but the overlap check flags any two jobs at the same time, so the warning fires on normal parallel jobs. Jobs can only use the customer's address, which is wrong for realtors and estate cleanouts.

How: A Truck row (1-5) on each job, with overlaps checked per truck (this revisits the Oct 19 "any overlap" decision), and a Job address field prefilled from the customer.

### 11. A duplicate-customer check on the typed form (an hour)

Ashley can type a returning caller in again, splitting their history. HANDOFF already lists it for you.

How: On saving a new customer, match on phone (10 digits) or name plus house number and street (your Assistant rule), and ask "Linda Johnson, 42 Elm St, is already a customer. Use that one?".

### 12. Open quotes on the customer's page (an hour)

A caller says "you gave me a price last week", and neither the customer page nor Customers search shows quotes.

How: A Quotes section on CustomerDetailView, only when the customer has open quotes, each opening the quote.

### 13. A "No price" list for done jobs never priced (an hour)

A job marked done before a price is entered drops out of every money list, so nothing reminds Ashley to bill it.

How: A "No price" card under "Not marked done" and a section in Jobs, plus a "No price" pill, for done, unpaid, unpriced jobs (quote visits excepted). Unpaid and Owed stay as they are.

### 14. Keep the old rate on past hours (half a day)

A raise or a switch to salary rewrites the pay shown for every past week.

How: Store the rate on each hours entry and ask "Use $22 for past weeks too?" when a rate changes; confirm before switching someone with hours to salary.

### 15. Labor wording and unknown names (an hour)

"Working today 2 of 5" counts hourly people only once hours are typed. An unknown name like "Marcus" is added to the crew by default (as docs/labor.md specifies), so a misheard name becomes a new person.

How: Rename the tile to "Logged today" (or keep the title and show "3 hourly not logged"). For an unknown name, a "Who is Marcus?" chooser listing the crew plus "Someone new", nothing preselected. That changes the spec.

### 16. Only tint the dumpsters that need attention (an hour)

Three green "In the yard" tiles get as much colour as the overdue one. The spec (docs/calendar-tab.md) says tiles are in their status colour, so this changes it.

How: In-the-yard tiles on the plain card colour with a small green dot; tinted fill only for due today, overdue and out.

### 17. Which maps app does Alex use? (an hour)

Directions only opens Apple Maps. If Alex drives with Google Maps or Waze, an option would save copying addresses.

How: One question. If it is not Apple Maps, add a Settings choice and the Info.plist entries.

## Everyday gaps the app does not cover yet

- The overweight charge is calculated and then lost: it never reaches Owed, Unpaid or the customer's balance.
- Marking a dumpster drop-off, pickup or swap job done by hand doesn't move the dumpster, and moving the dumpster doesn't close the job (only the Assistant links them).
- Mark paid doesn't record cash, check or card, or a partial payment.
- Nothing can be corrected after Mark picked up / dropped off: no edit of past rentals, no undo.
- Swapping a dumpster by hand is a full pickup plus a retyped drop-off.
- No Text button for "on my way" or booking confirmations, except through the Assistant.
- No reminder or notification for dumpsters due back or overdue.
- Calendar job cards show no address or map button, so planning the next stop means opening each job.
- A note spoken without signal is only kept by the do-now fix; nothing sends it automatically later.
- No truck assignment, so the overlap check can't tell a real double-booked truck from two trucks working at once.
- No job-site address separate from the customer's address.
- No duplicate-customer check when typing a new customer.
- Quotes can't be seen from the customer's page.
- Done jobs with no price fall out of every money list.
- No quick "extend 3 / 7 days" for a rental; it takes the dumpster page and a date picker.
- No photos (before/after, weigh ticket). Not in version 1; worth raising with Alex later.
- Labor: no "same as yesterday" and no way to send the week's hours and pay to whoever writes checks.
- Customer list has no A-Z index or last-name sort for browsing 600-700 names (search works well).
- Settings still shows Debug and model settings (open question 7).

## Where reviewers disagreed, and the call made

- Back from an edited job: one fix wanted a Cancel/Done pair or a general "Save changes?". My call: keep "leaving saves" (as decided on Oct 19, like Notes) and ask only when the change creates a new overlap. A blanket question would slow Alex down.
- Deleting from a swipe: an undo bar versus a confirmation. I chose the confirmation (no full-swipe delete) because it is standard and needs no new UI. For customers I kept the swipe with a question rather than removing it.
- Assistant button: CLAUDE.md says it is labelled "Assistant"; three judges want a bar above the tab bar; one refutation called the missing word a matter of taste. I put the word back in the toolbar now (it is a written rule) and sent the bigger bottom bar or button to you.
- Swiping the Assistant sheet away: one reviewer said never block it. I chose to stop the microphone whenever it closes and to block the swipe only while a filled form is showing, with Cancel asking first.
- Debug section: one finding wanted it hidden now. It is your open question 7 and you still need it for the step 1 tests, so it is in the proposals. Only the calendar-event clean-up and the clearer dialog are in do-now.
- Name and address fields: some fixes added AutoFill content types. I left them out, because iOS would offer the phone owner's own name and address on customer forms.
- Hours limits: proposals ranged from warning over 16 to refusing over 24. I chose to refuse only over 24, with no 16-hour rule and no guessing that "85" means 8.5.
- Unknown worker name in the Assistant's hours: one reviewer kept the spec (add to crew, switch on), another wanted a "Who is Marcus?" chooser. Do-now only names skipped lines and fixes the two-Chris and retired cases; the chooser is a spec change for you.
- Dumpster tiles: judges want in-the-yard tiles uncoloured; the spec says status colour. I fixed only text contrast now and sent the colour change to you.
- Calendar page order: judges want today's jobs above the four figures; refutations noted it is the documented design and the Quotes tile is the way into Quotes. I left the normal order alone and sent the large-text reorder to you.
- Labor page order: one fix also dropped the Crew tile. I moved the day above the figures and kept all four tiles.
- Pickup date: one fix defaulted to the due-back day. I chose today, because most pickups are logged as they happen.
- Two finders said .interactiveDismissDisabled makes the swipe "ask". It only blocks it; the question comes from Cancel, and I worded the fixes that way.
- Several judge suggestions were already refuted in review (overdue dumpsters in the day list, a visible check button on every Calendar card, a payment submenu in the long-press menu). I didn't bring them back. Note: iphone-03 is a copy of iphone-02, so the "Not marked done" card was never seen in a screenshot.

## What the critic says the audit missed (to check later)

- A database change in a later build could stop the phone app from opening at all, and its records are not backed up anywhere. Ace/AceApp.swift opens the database with fatalError and has no VersionedSchema or SchemaMigrationPlan (a grep finds none). If Kyle installs a new build whose model change SwiftData cannot migrate on its own (a renamed property, or one that becomes non-optional with no default), Ashley's or Alex's iPhone would crash at launch every time, with real data inside. Until sync exists there is no backup or export, so the only way out would be deleting the app, which deletes the data too. The audit never looked at what happens when a build is updated. How to check: Read Ace/AceApp.swift init() and Ace/Data/Models.swift. In the Simulator: install the current build, add a job, then change a stored property (for example make Job.notes non-optional with no default), rebuild over the top and launch. See whether it crashes. Decide on versioned schemas and a non-crashing fallback (a 'database could not be opened' screen plus a copy of the store) before real data goes on the phones.
- Nobody looked at what happens when iOS kills the app in the background. JobEditView and QuoteEditView save only in onDisappear, which does not run when iOS kills the app. MainView holds a WhisperKitEngine for the whole session (@State engine), so the speech model stays in memory: about 150 MB for base, about 630 MB for large. That makes Ace an early target when Alex switches to Maps or takes a call. If that happens, an edited job, a half-typed new job and a reviewed Assistant form are all lost. On relaunch only the tab comes back: Jobs, Customers and Dumpsters keep no navigation path. CLAUDE.md says the app opens to the last screen. How to check: In the Simulator, open a job, change the notes, press Home, then stop the app from Xcode and relaunch. Is the edit kept, and which screen opens? Repeat with the Assistant review form showing. On a real iPhone, use Xcode's memory gauge with the model loaded, then open Maps navigation and see whether Ace gets killed. Check MainView.swift (engine, the paths without bindings) and JobEditView.swift:144-146.
- Edits are silently thrown away when the customer is missing or the end time is invalid. JobEditView.swift:145 saves on leaving only if form.customer != nil && form.endIsValid, and Save (line 116) is disabled when there is no customer. The audit's delete-customer fix promises 'Their jobs are kept without a customer'. After that, those jobs cannot be saved at all: any change Alex or Ashley makes vanishes on Back with no message. The same happens to any job whose end time ends up before its start. QuoteEditView.swift:142 has the same customer guard. A dumpster still out to a deleted customer becomes 'No customer' on its tile, with no way to call. Nobody walked deleting a customer and then working with that customer's jobs, dumpster and quotes. How to check: In the Simulator with sample data: delete a customer who has a job, an out dumpster and an open quote. Open the job, change the note, tap Back, reopen it. Then set an end time before the start on a normal job and tap Back. Then look at the Dumpsters tile and the quote row.
- First launch with an empty database and no API key was never seen. Every screenshot used sample data (-sampledata) and '-debug.speechready', so these states are unknown: the Calendar with no jobs, a Labor tab with no crew, the Dumpsters 'Set up 6 dumpsters' button, the Assistant with no customers, and Settings showing Load sample data and Clear all data. Each device creates its own six Dumpster records, which will become 12 when sync arrives unless the dumpster number decides which record is which. With no key (iphone-19), Hold to talk and Send are still active. The notice uses jargon ('Anthropic API key') and has no button. Settings is reachable only from the Calendar tab's gear (MainView.swift toolbarItems showSettings:true on Calendar only), so from any other tab the notice points somewhere that isn't there. How to check: Erase the Simulator app's data and launch with no arguments on the 17e. Screenshot all five tabs, Settings and the Assistant. Type a note and tap Send with no key: what message appears, and is the note kept? Read AssistantView.swift:279-284 and ClaudeClient.swift:59. Open the Assistant from the Jobs tab and try to follow the 'Settings › API key' instruction.
- The speech model's first run on a real phone has not been seen. The 'Voice ready.' in the screenshots is faked by -debug.speechready. In the real first run (WhisperKitEngine.load), the base model (about 150 MB, default in AppSettings.swift:16) or a 630 MB large model downloads over cellular with no warning and no Wi-Fi-only choice. The first load also needs internet for a tokenizer file. Compiling the model on the device can take minutes. The download is an ordinary request, so leaving the app stops it. On a phone low on storage, the failure shows error.localizedDescription as-is. Alex will probably open the Assistant for the first time in the truck. How to check: On a real iPhone with Wi-Fi off, delete the app, reinstall, and open the Assistant. Watch the downloading and loading states, time them, and note cellular data in iOS Settings › Cellular. Leave the app halfway through and come back. Fill the device's storage to under 200 MB and try again. Read the failure text. Also try it on whichever iPhone Alex actually owns.
- Nothing was tested at real volume: 600-700 customers a year, against about 7 in the sample data. Every CustomerRow computes customer.amountOwed by walking that customer's jobs. Search refilters the whole @Query on every keystroke. Each Assistant note sends the whole customer directory with phones and addresses (AssistantRecords.swift:106-109 says 'every customer on file') plus each customer's 8 most recent jobs. After an import of years of history that could be tens of thousands of input tokens per note, sent over patchy cellular with a 90-second timeout (ClaudeClient.swift:97), mostly missing the 5-minute prompt cache between stops. It also sends every customer's details to the API on every note. The audit's 'search works well' was judged on a handful of names. How to check: Add a test launch argument (or reuse test-data/) that creates 700 customers and 2,000 jobs in the Simulator. Scroll Customers and Jobs and type in search on the 17e. Send one Assistant note from the Claude test screen and read the input token count and the time taken. Decide on a cap, for example only the customers matched by AssistantRecords.mentionedCustomers.
- Yesterday's statuses stick overnight on more than the Calendar and Labor days. The audit's overnight fix only resets calendarDay and the Labor day. Dumpster status() (due today, overdue), DumpstersView's summary, the Jobs Upcoming/Past split and TodayFigures all compare against Date() only when the view redraws, and nothing redraws at midnight or on return to the app unless data changes. Next morning a dumpster due back today can still read 'Out', and an overdue one 'Due today', which is the main purpose of the dumpster tracker. How to check: Read Ace/Dumpsters/DumpstersView.swift (summary, status()) and Ace/Calendar/TodayFigures.swift: is there any TimelineView, scenePhase refresh or NSCalendarDayChanged observer? In the Simulator: give a dumpster a due-back date of today, leave the app in the background, let the Mac clock pass midnight (or post .NSCalendarDayChanged), reopen and compare the tile with a fresh launch.
- Landscape and the narrowest iPhone were never checked. The project allows landscape on iPhone (project.pbxproj:283 lists LandscapeLeft and LandscapeRight), and a phone in a truck dash mount is often sideways. No screenshot shows landscape: the week strip, the two-column dumpster tiles, the Assistant sheet, or forms with the keyboard up (which leaves very little height). The smallest phone checked was the 17e (I'm assuming about 390 points wide). As far as I know, iOS 26 still runs on the iPhone SE 2nd and 3rd generation, which are 375 points wide with a Home button and a shorter screen. Which iPhones Ashley and Alex own is unknown, and that also matters for WhisperKit speed on older chips. How to check: In the Simulator, rotate (Cmd+Left Arrow) on each tab, on a job page with the keyboard up, and in the Assistant. Add an iPhone SE (3rd generation) simulator if Xcode offers one and screenshot every tab and the job and dumpster pages at normal and largest text. Ask Kyle one question: which iPhone models do Ashley and Alex have? Then decide whether to lock the iPhone to portrait.
- The overweight charge was never walked end to end with realistic input. Parse.tons is Parse.money (Formatting.swift:74-80): it strips commas and has no upper limit. A weigh ticket read in pounds, '4,620', is saved as 4,620 tons, and the confirm question shows a charge of about $577,000. There is no unit check and no 'that looks like pounds' question. The rate is a $125-a-ton placeholder (AppSettings.swift:9) that nobody has confirmed. It is stored per device in UserDefaults, so Alex's phone, which does the pickups, can quietly use a different rate from Ashley's. How to check: In the Simulator, open an out dumpster with a 2-ton agreed weight and type 4620, then 4,620, then 2.8 into the pickup weight. Read the confirm question and the saved rental. Ask Kyle: do Alex's weigh tickets show tons or pounds, and what is the real rate? Check that Settings › Overweight rate on each phone matches.
- Typing hours for a whole crew in a row was not walked on the phone. HoursCell (LaborCells.swift:41 and :51) applies .focused twice: once inside .decimalKeyboard()'s KeyboardDone modifier and once with its own @FocusState. So it is uncertain whether the keyboard's Done button appears, and whether tapping it commits the value. The decimal pad has no Return key, so .onSubmit(commit) never fires on iPhone and there is no move to the next person. With the keyboard up on a 17e, the lower crew rows sit behind the keyboard and the tab bar. The screenshots show the Labor tab only at rest. How to check: In the Simulator on the 17e with six active people: tap the first Today box, type 8, then try to reach and fill the next five boxes. Note whether Done appears above the keyboard, whether the lower rows can be scrolled into view, and whether every value is saved after tapping Done, after switching tabs, and after pressing Home.
- One of the audit's do-now fixes may make voice notes worse. The audio item says to use 'playAndRecord, allowBluetooth, defaultToSpeaker' for both recording paths. allowBluetooth sends recording through the hands-free profile, which uses the car's or AirPods' narrowband microphone and puts the car stereo into phone-call mode. That could lower WhisperKit accuracy, and it is the call-mode problem the item is trying to fix. No finding tested this. It should be checked both ways on the truck's Bluetooth before it is written into the code. How to check: Read the 'Release the audio after listening' item against Ace/Speech/AudioRecorder.swift and WhisperKitEngine.swift. On a real iPhone, connected to the truck's Bluetooth and then to AirPods, record the same note with and without allowBluetooth. Compare the transcripts and whether the stereo switches to call mode, and record the result in docs/.
- Some of the synthesis's claims have no screenshot behind them. The small-dark-* and small-largest-text-* sets show only the five tab screens (9 files). No job page, quote page, customer page, dumpster page, sheet or Assistant screen was captured on the 17e, at the largest text size, or in dark mode. So 'On the iPhone 17e, Call and New job are cut too', the large-text claims about detail headers and the Missing card, and the dark-mode tile comments on detail pages are inferred from code. iphone-03 is a byte-for-byte copy of iphone-02 (same md5), and there is no iphone-04. The Assistant screens were filled from saved answers, so the live record, transcribe and send flow, and the asking and error states, were never seen. How to check: Run md5 on docs/review-2026-10-20-iphone/iphone-02* and iphone-03* to confirm the copy. Re-take iphone-06, -09, -11, -11b, -17, -19 and -20 on the iPhone 17e at the largest text size in light mode and again in dark mode, plus the missing Calendar bottom and 'Not marked done' card. Downgrade any claim those pictures don't confirm to 'assumed'.

Totals: 191 findings survived both checks; 110 were refuted or duplicates. 638 agents in all.

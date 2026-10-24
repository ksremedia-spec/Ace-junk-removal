import EventKit
import Foundation
import Observation

/// Ace's one door into the device's calendars (Apple's EventKit): calendar
/// access, the calendars on the device, other calendars' events for the
/// Calendar screen, and the copy of each job in the Calendar for Jobs. The
/// spec is docs/calendar-tab.md; the research behind it is docs/calendar.md.
///
/// Ace is the master copy: it writes a job's event whenever the job is saved
/// on this device and deletes it when the job is deleted here. Changes made
/// in Google Calendar never flow back into the job.
@MainActor
@Observable
final class CalendarStore {
    static let shared = CalendarStore()

    enum Access {
        case notSet, full, off

        /// What Settings shows next to Calendar Access.
        var text: String {
            switch self {
            case .notSet: return "Not set"
            case .full: return "Full access"
            case .off: return "Off"
            }
        }
    }

    /// The one event store the whole app uses (Apple: make one and keep it).
    let store = EKEventStore()

    private(set) var access: Access = .notSet
    /// Every event calendar on the device, by account, then by name. Empty
    /// without full access.
    private(set) var calendars: [EKCalendar] = []
    /// The Calendar for Jobs. Empty means None.
    private(set) var jobsCalendarID = ""
    /// Calendars switched off under Show Calendars.
    private(set) var hiddenCalendarIDs: Set<String> = []
    /// Goes up whenever the calendar database changes, so screens that list
    /// events read them again.
    private(set) var changeCount = 0

    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    /// The last line of every job's event: "Ace job" and the job's ID. How
    /// Ace recognises its own events on any device.
    nonisolated static let markerPrefix = "Ace job "

    /// Sample data and screenshot runs never touch a real calendar.
    private static let writesBlocked: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-sampledata") || args.contains("-screenshot")
    }()

    private init() {
        jobsCalendarID = UserDefaults.standard.string(forKey: AppSettings.jobsCalendarKey) ?? ""
        hiddenCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: AppSettings.hiddenCalendarsKey) ?? [])
        access = Self.currentAccess()
        reloadCalendars()
        // Posted on the main thread whenever anything in the calendar
        // database changes, including changes arriving from Google. It does
        // not say what changed, so the screens read again.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.storeChanged()
            }
        }
    }

    // MARK: - Access

    nonisolated private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .full
        case .notDetermined:
            return .notSet
        default:
            // Denied, restricted, or "Add Events Only", which cannot read
            // calendars or pick one.
            return .off
        }
    }

    /// Shows Apple's calendar question. Only Settings › Calendar calls this;
    /// Ace never asks at launch.
    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        access = Self.currentAccess()
        if access == .full {
            // Apple: after access is granted, reset the store to see data.
            store.reset()
        }
        reloadCalendars()
        changeCount += 1
    }

    /// Reads the access level and the calendars again. Called when the app
    /// comes to the front, since access can be changed in Settings meanwhile.
    func refresh() {
        let current = Self.currentAccess()
        if current != access {
            if current == .full { store.reset() }
            access = current
        }
        // Asks Google for changes now rather than on its own schedule, so
        // another device's job events arrive sooner. Anything new comes in
        // through the change notice above.
        if access == .full { store.refreshSourcesIfNecessary() }
        reloadCalendars()
        changeCount += 1
    }

    private func storeChanged() {
        reloadCalendars()
        changeCount += 1
    }

    private func reloadCalendars() {
        guard access == .full else {
            calendars = []
            return
        }
        calendars = store.calendars(for: .event).sorted { a, b in
            let accountA = a.source?.title ?? ""
            let accountB = b.source?.title ?? ""
            if accountA != accountB { return accountA.localizedStandardCompare(accountB) == .orderedAscending }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    // MARK: - Settings

    /// The Calendar for Jobs, or nil for None, without access, or when the
    /// chosen calendar is no longer on the device.
    var jobsCalendar: EKCalendar? {
        guard access == .full, !jobsCalendarID.isEmpty else { return nil }
        return store.calendar(withIdentifier: jobsCalendarID)
    }

    /// A Calendar for Jobs is chosen but has gone (removed, or the account
    /// was taken off the device). Settings shows "Not found".
    var jobsCalendarMissing: Bool {
        access == .full && !jobsCalendarID.isEmpty && jobsCalendar == nil
    }

    /// Calendars that can be picked as the Calendar for Jobs.
    var writableCalendars: [EKCalendar] {
        calendars.filter(\.allowsContentModifications)
    }

    /// Every calendar except the Calendar for Jobs, for Show Calendars.
    var otherCalendars: [EKCalendar] {
        calendars.filter { $0.calendarIdentifier != jobsCalendarID }
    }

    /// Empty for None.
    func setJobsCalendar(_ identifier: String) {
        jobsCalendarID = identifier
        UserDefaults.standard.set(identifier, forKey: AppSettings.jobsCalendarKey)
        changeCount += 1
    }

    func isShown(_ calendar: EKCalendar) -> Bool {
        !hiddenCalendarIDs.contains(calendar.calendarIdentifier)
    }

    func setShown(_ shown: Bool, for calendar: EKCalendar) {
        if shown {
            hiddenCalendarIDs.remove(calendar.calendarIdentifier)
        } else {
            hiddenCalendarIDs.insert(calendar.calendarIdentifier)
        }
        UserDefaults.standard.set(Array(hiddenCalendarIDs).sorted(), forKey: AppSettings.hiddenCalendarsKey)
        changeCount += 1
    }

    /// "Ace Jobs · acejunk@gmail.com": the calendar with its account.
    static func label(for calendar: EKCalendar) -> String {
        guard let account = calendar.source?.title, !account.isEmpty else { return calendar.title }
        return calendar.title + " · " + account
    }

    // MARK: - Other calendars' events

    /// The day's events from the calendars shown in Ace, all-day ones first,
    /// then by start time. Events in the Calendar for Jobs that are copies
    /// of jobs on this device (`jobIDs`) are left out; the job is already
    /// listed. Empty without full access.
    func events(on day: Date, hidingJobs jobIDs: Set<UUID>) -> [OtherEvent] {
        // Read so that a screen calling this updates when anything changes.
        _ = changeCount
        guard access == .full else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let shown = calendars.filter { $0.calendarIdentifier == jobsCalendarID || isShown($0) }
        guard !shown.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: shown)
        return store.events(matching: predicate)
            .filter { event in
                guard event.calendar?.calendarIdentifier == jobsCalendarID,
                      let id = Self.jobID(inNotes: event.notes) else { return true }
                return !jobIDs.contains(id)
            }
            .map { OtherEvent($0, on: start) }
            .sorted { a, b in
                if a.coversDay != b.coversDay { return a.coversDay }
                if a.event.startDate != b.event.startDate { return a.event.startDate < b.event.startDate }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
    }

    // MARK: - Writing jobs

    /// Writes or updates the job's event in the Calendar for Jobs. Every
    /// path that saves a job on this device calls this after saving. Does
    /// nothing without full access or a Calendar for Jobs, and never during
    /// sample-data or screenshot runs. A failure is ignored: the job itself
    /// is already saved.
    func jobSaved(_ job: Job) {
        guard !Self.writesBlocked, access == .full, let calendar = jobsCalendar else { return }
        if job.jobID == nil { job.jobID = UUID() }
        guard let jobID = job.jobID else { return }

        // Always look for copies another device wrote, not only on the first
        // write: a phone can write its own copy before Google has brought the
        // Mac's down, and then both devices remember different events
        // (audit Oct 21, item 24).
        var found = markedEvents(jobID: jobID, in: calendar, near: job.scheduledAt)
        if let remembered = rememberedEvent(of: job, jobID: jobID) {
            if remembered.calendar?.calendarIdentifier == calendar.calendarIdentifier {
                if !found.contains(where: { $0.calendarItemIdentifier == remembered.calendarItemIdentifier }) {
                    // Outside the search window, e.g. the job moved far off.
                    found.append(remembered)
                    found.sort(by: Self.keptFirst)
                }
            } else {
                // The Calendar for Jobs was changed since this event was
                // written: the copy in the old calendar goes.
                try? store.remove(remembered, span: .thisEvent, commit: true)
            }
        }
        // Two devices wrote the same job: every device keeps the same one
        // and deletes the others.
        for extra in found.dropFirst() {
            try? store.remove(extra, span: .thisEvent, commit: true)
        }
        let event = found.first ?? EKEvent(eventStore: store)
        if event.calendar?.calendarIdentifier != calendar.calendarIdentifier {
            event.calendar = calendar
        }
        fill(event, from: job, jobID: jobID)
        do {
            try store.save(event, span: .thisEvent, commit: true)
            job.calendarItemID = event.calendarItemIdentifier
            job.calendarWrittenAt = Date()
        } catch {
            // Access turned off, calendar read-only or removed: the job is
            // saved anyway, and the next save tries again.
        }
        try? job.modelContext?.save()
    }

    /// Deletes the job's event (and any extra copies). Called just before
    /// the job itself is deleted on this device, by `Job.remove(from:)`.
    func jobDeleting(_ job: Job) {
        guard !Self.writesBlocked, access == .full, let jobID = job.jobID else { return }
        var events: [String: EKEvent] = [:]
        if let event = rememberedEvent(of: job, jobID: jobID) {
            events[event.calendarItemIdentifier] = event
        }
        if let calendar = jobsCalendar {
            for event in markedEvents(jobID: jobID, in: calendar, near: job.scheduledAt) {
                events[event.calendarItemIdentifier] = event
            }
        }
        for event in events.values {
            try? store.remove(event, span: .thisEvent, commit: true)
        }
    }

    /// Rewrites the events of the customer's jobs after their name, phone
    /// or address was saved (the customer form, the Assistant). Only jobs
    /// this device has written, from 60 days back onward; an event that is
    /// already up to date is left alone.
    func customerSaved(_ customer: Customer) {
        for job in jobsWritten(for: customer) {
            if let jobID = job.jobID,
               let event = rememberedEvent(of: job, jobID: jobID),
               event.calendar?.calendarIdentifier == jobsCalendarID,
               isUpToDate(event, with: job, jobID: jobID) {
                continue
            }
            jobSaved(job)
        }
    }

    /// The customer's jobs whose events carry the customer's name, phone
    /// and address: written on this device, from 60 days back onward. Empty
    /// when nothing can be written. `Customer.remove(from:)` uses it to
    /// rewrite those events without the customer.
    func jobsWritten(for customer: Customer) -> [Job] {
        guard !Self.writesBlocked, access == .full, jobsCalendar != nil else { return [] }
        let today = Dates.startOfToday()
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: today) ?? today
        return customer.jobs.filter {
            $0.jobID != nil && $0.calendarWrittenAt != nil && $0.scheduledAt >= cutoff
        }
    }

    private func isUpToDate(_ event: EKEvent, with job: Job, jobID: UUID) -> Bool {
        (event.title ?? "") == Self.title(for: job)
            && (event.location ?? "") == Self.location(for: job)
            && (event.notes ?? "") == Self.notes(for: job, jobID: jobID)
    }

    /// The event remembered on the job, if it is still there and its marker
    /// line names this job.
    private func rememberedEvent(of job: Job, jobID: UUID) -> EKEvent? {
        guard let itemID = job.calendarItemID,
              let event = store.calendarItem(withIdentifier: itemID) as? EKEvent,
              Self.jobID(inNotes: event.notes) == jobID else { return nil }
        return event
    }

    /// Events in `calendar` whose marker line names this job, from 60 days
    /// back to a year ahead (and around the job's own day if it is outside
    /// that). The one every device keeps comes first: the one whose
    /// server identifier sorts first.
    private func markedEvents(jobID: UUID, in calendar: EKCalendar, near date: Date) -> [EKEvent] {
        var found: [String: EKEvent] = [:]
        for window in Self.searchWindows(around: date) {
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
            for event in store.events(matching: predicate) where Self.jobID(inNotes: event.notes) == jobID {
                found[event.calendarItemIdentifier] = event
            }
        }
        return found.values.sorted(by: Self.keptFirst)
    }

    /// The order every device agrees on: the event whose server identifier
    /// sorts first is the one kept.
    private static func keptFirst(_ a: EKEvent, _ b: EKEvent) -> Bool {
        let keyA = a.calendarItemExternalIdentifier ?? ""
        let keyB = b.calendarItemExternalIdentifier ?? ""
        return keyA != keyB ? keyA < keyB : a.calendarItemIdentifier < b.calendarItemIdentifier
    }

    /// One search may cover at most four years (Apple's limit), so the
    /// job's own day gets a second, short search when it is far off.
    private static func searchWindows(around date: Date) -> [DateInterval] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -60, to: today) ?? today
        let end = calendar.date(byAdding: .year, value: 1, to: today) ?? today
        var windows = [DateInterval(start: start, end: end)]
        let day = calendar.startOfDay(for: date)
        if day < start || day >= end,
           let before = calendar.date(byAdding: .day, value: -1, to: day),
           let after = calendar.date(byAdding: .day, value: 2, to: day) {
            windows.append(DateInterval(start: before, end: after))
        }
        return windows
    }

    /// Puts the job into the event: title, address, times, notes, no alerts.
    private func fill(_ event: EKEvent, from job: Job, jobID: UUID) {
        event.title = Self.title(for: job)
        let address = Self.location(for: job)
        event.location = address.isEmpty ? nil : address

        if job.hasTime {
            // A job with only a start time is an event that starts and ends
            // then; no length is made up (docs/calendar-tab.md).
            event.isAllDay = false
            event.startDate = job.scheduledAt
            if let end = job.endsAt, end > job.scheduledAt {
                event.endDate = end
            } else {
                event.endDate = job.scheduledAt
            }
        } else {
            let day = Calendar.current.startOfDay(for: job.scheduledAt)
            event.isAllDay = true
            event.startDate = day
            event.endDate = day
        }

        event.notes = Self.notes(for: job, jobID: jobID)
        for alarm in event.alarms ?? [] {
            event.removeAlarm(alarm)
        }
    }

    /// "Linda Johnson · Junk removal", or "Junk removal" with no customer.
    private static func title(for job: Job) -> String {
        let name = job.customer?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? job.jobType.rawValue : name + " · " + job.jobType.rawValue
    }

    /// The customer's address; empty with no customer or no address.
    private static func location(for job: Job) -> String {
        job.customer?.address.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The phone number; "$450 · Cash · Unpaid" (or "Paid", or "Done ·
    /// Paid"); the job's notes; and last, "Ace job" with the job's ID.
    private static func notes(for job: Job, jobID: UUID) -> String {
        var lines: [String] = []
        if let phone = job.customer?.phone, !phone.isEmpty {
            lines.append(phone)
        }
        var money: [String] = []
        if let price = job.price { money.append(Money.text(price)) }
        if job.paymentType != .unknown { money.append(job.paymentType.rawValue) }
        if job.isDone { money.append("Done") }
        money.append(job.isPaid ? "Paid" : "Unpaid")
        lines.append(money.joined(separator: " · "))
        let notes = job.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { lines.append(notes) }
        lines.append(markerPrefix + jobID.uuidString)
        return lines.joined(separator: "\n")
    }

    /// The job ID in an event's marker line, or nil when it has none.
    nonisolated static func jobID(inNotes notes: String?) -> UUID? {
        guard let notes else { return nil }
        for line in notes.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(markerPrefix) {
                return UUID(uuidString: String(trimmed.dropFirst(markerPrefix.count)))
            }
        }
        return nil
    }
}

import EventKit
import Foundation
import SwiftData
import SwiftUI

// What the Calendar screen lists for one day, worked out from Ace's own
// records and the device's other calendars. Shared by the iPhone screen
// (CalendarView) and the Mac board (MacBoard). The spec is
// docs/calendar-tab.md.

/// One day's jobs, dumpster comings and goings, and quotes to call back.
struct DaySchedule {
    /// The start of the day.
    let day: Date
    /// Every job that day, done ones included: jobs without a time first,
    /// then in time order.
    let jobs: [Job]
    /// Drop-offs and due-backs of dumpsters out now; drop-offs and pickups
    /// from past rentals.
    let dumpsterItems: [DumpsterDayItem]
    /// Open quotes to call back. For today, every one due today or earlier;
    /// for another day, the ones with a follow-up on that day.
    let callBacks: [Quote]

    init(day: Date,
         jobs: [Job],
         dumpsters: [Dumpster],
         rentals: [RentalRecord],
         quotes: [Quote],
         calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        self.day = start

        self.jobs = jobs
            .filter { calendar.isDate($0.scheduledAt, inSameDayAs: start) }
            .sorted(by: Self.timeOrder)

        var items: [DumpsterDayItem] = []
        for dumpster in dumpsters where dumpster.isOut {
            if let date = dumpster.droppedOffAt, calendar.isDate(date, inSameDayAs: start) {
                items.append(DumpsterDayItem(kind: .dropOff, dumpster: dumpster, customer: dumpster.customer,
                                             location: dumpster.location, record: dumpster.persistentModelID))
            }
            if let date = dumpster.dueBackAt, calendar.isDate(date, inSameDayAs: start) {
                items.append(DumpsterDayItem(kind: .dueBack, dumpster: dumpster, customer: dumpster.customer,
                                             location: dumpster.location, record: dumpster.persistentModelID))
            }
        }
        for rental in rentals {
            guard let dumpster = rental.dumpster else { continue }
            if calendar.isDate(rental.droppedOffAt, inSameDayAs: start) {
                items.append(DumpsterDayItem(kind: .dropOff, dumpster: dumpster, customer: rental.customer,
                                             location: rental.location, record: rental.persistentModelID))
            }
            if calendar.isDate(rental.pickedUpAt, inSameDayAs: start) {
                items.append(DumpsterDayItem(kind: .pickedUp, dumpster: dumpster, customer: rental.customer,
                                             location: rental.location, record: rental.persistentModelID))
            }
        }
        self.dumpsterItems = items.sorted {
            ($0.dumpster.number, $0.kind.rawValue) < ($1.dumpster.number, $1.kind.rawValue)
        }

        if !QuoteFeatures.followUps {
            self.callBacks = []
        } else if calendar.isDateInToday(start) {
            self.callBacks = QuoteList.followUp(quotes)
        } else {
            self.callBacks = quotes.filter { quote in
                guard quote.status == .open, let followUp = quote.followUpOn else { return false }
                return calendar.isDate(followUp, inSameDayAs: start)
            }
        }
    }

    /// "Thursday, October 22"
    var title: String { Dates.longDay(day) }

    /// Jobs without a time first, then by start time.
    static func timeOrder(_ a: Job, _ b: Job) -> Bool {
        if a.hasTime != b.hasTime { return !a.hasTime }
        return a.scheduledAt < b.scheduledAt
    }

    /// Start of each day with at least one job not yet done, for the dots
    /// under the iPhone month.
    static func daysWithOpenJobs(_ jobs: [Job], calendar: Calendar = .current) -> Set<Date> {
        Set(jobs.filter { !$0.isDone }.map { calendar.startOfDay(for: $0.scheduledAt) })
    }
}

/// "Dumpster 3 drop-off", "Dumpster 3 due back" or "Dumpster 3 picked up".
struct DumpsterDayItem: Identifiable {
    enum Kind: Int {
        case dropOff, dueBack, pickedUp

        var text: String {
            switch self {
            case .dropOff: return "drop-off"
            case .dueBack: return "due back"
            case .pickedUp: return "picked up"
            }
        }
    }

    struct ItemID: Hashable {
        let record: PersistentIdentifier
        let kind: Kind
    }

    let kind: Kind
    let dumpster: Dumpster
    let customer: Customer?
    let location: String
    let id: ItemID

    init(kind: Kind, dumpster: Dumpster, customer: Customer?, location: String, record: PersistentIdentifier) {
        self.kind = kind
        self.dumpster = dumpster
        self.customer = customer
        self.location = location
        self.id = ItemID(record: record, kind: kind)
    }

    var title: String { "Dumpster \(dumpster.number) " + kind.text }
}

/// An event from one of the device's other calendars, as listed for one
/// day. Two copies are the same when they are the same occurrence of the
/// same event, so a selection survives the list being read again.
struct OtherEvent: Identifiable, Hashable {
    let event: EKEvent
    let id: String
    let title: String
    /// "9:00 to 10:00 AM · Alex", "All day · Alex", "Until 10:00 AM · Alex"
    let timeLine: String
    /// All day, or running from before the day to after it. Listed first.
    let coversDay: Bool

    init(_ event: EKEvent, on day: Date, calendar: Calendar = .current) {
        self.event = event
        let start: Date = event.startDate ?? day
        let end: Date = event.endDate ?? start
        id = event.calendarItemIdentifier + "|" + String(start.timeIntervalSinceReferenceDate)
        let name = event.title ?? ""
        title = name.isEmpty ? "No title" : name

        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let startsBefore = start < dayStart
        let endsAfter = end > dayEnd
        let time: String
        if event.isAllDay || (startsBefore && endsAfter) {
            time = "All day"
            coversDay = true
        } else if startsBefore {
            time = "Until " + JobTimes.text(start: end, end: nil)
            coversDay = false
        } else if endsAfter {
            time = "From " + JobTimes.text(start: start, end: nil)
            coversDay = false
        } else {
            time = JobTimes.text(start: start, end: end)
            coversDay = false
        }
        let calendarName = event.calendar?.title ?? ""
        timeLine = calendarName.isEmpty ? time : time + " · " + calendarName
    }

    static func == (lhs: OtherEvent, rhs: OtherEvent) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The calendar's own colour.
    var color: Color { Self.color(of: event.calendar) }

    static func color(of calendar: EKCalendar?) -> Color {
        guard let cgColor = calendar?.cgColor else { return .secondary }
        return Color(cgColor: cgColor)
    }

    /// "Thursday, October 22, 9:00 to 10:00 AM", "Thursday, October 22, all
    /// day", or both ends for an event over several days.
    static func whenText(_ event: EKEvent, calendar: Calendar = .current) -> String {
        guard let start = event.startDate, let end = event.endDate else { return "" }
        if event.isAllDay {
            // An all-day event ends at the very end of its last day.
            let lastDay = end > start ? end.addingTimeInterval(-1) : start
            if calendar.isDate(start, inSameDayAs: lastDay) {
                return Dates.longDay(start) + ", all day"
            }
            return Dates.shortDay(start) + " to " + Dates.shortDay(lastDay) + ", all day"
        }
        if calendar.isDate(start, inSameDayAs: end) {
            return Dates.longDay(start) + ", " + JobTimes.text(start: start, end: end)
        }
        return Dates.shortDay(start) + ", " + JobTimes.text(start: start, end: nil)
            + " to " + Dates.shortDay(end) + ", " + JobTimes.text(start: end, end: nil)
    }
}

// MARK: - Rows

/// An other-calendar event: a dot in the calendar's colour, the title, and
/// the time with the calendar's name.
struct OtherEventRow: View {
    let item: OtherEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(item.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .foregroundStyle(.primary)
                Text(item.timeLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// "Dumpster 3 drop-off" with the customer and the location.
struct DumpsterDayRow: View {
    let item: DumpsterDayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.headline)
            if let customer = item.customer {
                Text(customer.name)
                    .font(.subheadline)
            }
            if !item.location.isEmpty {
                Text(item.location)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A read-only page for an event from another calendar: title, calendar,
/// date and time, location and notes. The Mac's detail column uses it;
/// Apple's own event screens are not available in a Mac app.
struct CalendarEventPage: View {
    let event: EKEvent

    private var title: String {
        let name = event.title ?? ""
        return name.isEmpty ? "No title" : name
    }

    private var notes: String {
        (event.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var location: String {
        (event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                Text(title)
                    .font(.headline)
                LabeledContent("Calendar") {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(OtherEvent.color(of: event.calendar))
                            .accessibilityHidden(true)
                        Text(event.calendar?.title ?? "")
                    }
                }
                LabeledContent("When") {
                    Text(OtherEvent.whenText(event))
                        .multilineTextAlignment(.trailing)
                }
                if !location.isEmpty {
                    LabeledContent("Location") {
                        Text(location)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            } footer: {
                if notes.isEmpty {
                    Text("To change it, use the Calendar app.")
                }
            }
            if !notes.isEmpty {
                Section {
                    Text(notes)
                        .textSelection(.enabled)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("To change it, use the Calendar app.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}

/// Date components for one day, in the form Apple's month view uses.
enum CalendarDays {
    static func components(_ date: Date, calendar: Calendar = .current) -> DateComponents {
        calendar.dateComponents([.calendar, .era, .year, .month, .day], from: date)
    }
}

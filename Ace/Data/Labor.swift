import Foundation
import SwiftData

// The crew and the hours they work (Alex, Oct 20: "keep track of how many
// hours each guy worked every day"). Hourly crew have their hours typed or
// said per day; salaried crew count as working every work day unless
// marked off. People are retired, not deleted, so past hours stay. The
// spec is docs/labor.md.

// MARK: - Crew

enum PayType: String, CaseIterable, Codable, Identifiable {
    case hourly = "Hourly"
    case salary = "Salary"

    var id: String { rawValue }
}

@Model
final class Worker {
    var name: String
    var payTypeRaw: String
    /// Dollars an hour, for the week's pay. Optional; hourly crew only.
    var hourlyRate: Double?
    var phone: String = ""
    var notes: String = ""
    /// False once they have left (seasonal help); kept for their past hours.
    var isActive: Bool = true
    var createdAt: Date
    var updatedAt: Date

    /// The record's permanent ID, the same on every device (sync,
    /// docs/device-sync.md). Given when the record is made; records from
    /// before it existed get one on the first sync. Optional with no default,
    /// like `Job.jobID`, so an upgraded database does not give them all one value.
    var syncID: UUID? = nil

    @Relationship(deleteRule: .cascade, inverse: \LaborEntry.worker)
    var entries: [LaborEntry] = []

    init(name: String, payType: PayType = .hourly, hourlyRate: Double? = nil) {
        self.name = name
        self.payTypeRaw = payType.rawValue
        self.hourlyRate = hourlyRate
        self.createdAt = Date()
        self.updatedAt = Date()
        self.syncID = UUID()
    }

    var payType: PayType {
        get { PayType(rawValue: payTypeRaw) ?? .hourly }
        set { payTypeRaw = newValue.rawValue }
    }

    var isSalaried: Bool { payType == .salary }

    func entry(on day: Date, calendar: Calendar = .current) -> LaborEntry? {
        entries.first { calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// Hourly: the hours logged that day, nil when none.
    func hours(on day: Date) -> Double? {
        guard !isSalaried else { return nil }
        guard let hours = entry(on: day)?.hours, hours > 0 else { return nil }
        return hours
    }

    /// Salaried: whether a day with nothing marked counts as worked: a
    /// work day from the day they were added on.
    func usuallyWorks(on day: Date, calendar: Calendar = .current) -> Bool {
        Labor.isSalaryDay(day, calendar: calendar) && day >= calendar.startOfDay(for: createdAt)
    }

    /// Salaried: their usual day unless marked otherwise. Hourly: any
    /// hours logged.
    func worked(on day: Date, calendar: Calendar = .current) -> Bool {
        if isSalaried {
            guard let entry = entry(on: day) else { return usuallyWorks(on: day, calendar: calendar) }
            return !entry.isOff
        }
        return hours(on: day) != nil
    }

    /// "Hourly, $22 an hour", "Hourly", "Salary".
    var payText: String {
        guard !isSalaried, let hourlyRate else { return payType.rawValue }
        return "Hourly, " + Money.text(hourlyRate) + " an hour"
    }
}

/// One person's day: hours for hourly crew, or a day off for salaried crew.
@Model
final class LaborEntry {
    var worker: Worker?
    /// The start of the day.
    var day: Date
    var hours: Double?
    /// Salaried crew only: not working that day. On a day outside the
    /// salaried work week, an entry that is not off means they worked it.
    var isOff: Bool = false
    var note: String = ""
    var updatedAt: Date

    /// The entry's permanent ID for the sync. Worked out from the person
    /// and the day on the first sync (`SyncIDs.labor`), so hours typed for
    /// the same person and day on two devices are one entry, not two.
    var syncID: UUID? = nil

    init(worker: Worker?, day: Date, hours: Double? = nil, isOff: Bool = false) {
        self.worker = worker
        self.day = Calendar.current.startOfDay(for: day)
        self.hours = hours
        self.isOff = isOff
        self.updatedAt = Date()
    }
}

// MARK: - Working it out

enum Labor {
    static func isSalaryDay(_ day: Date, calendar: Calendar = .current) -> Bool {
        AppSettings.salaryDays.contains(calendar.component(.weekday, from: day))
    }

    /// The seven days of the week holding `day`, in the calendar's order.
    static func week(containing day: Date, calendar: Calendar = .current) -> [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return [calendar.startOfDay(for: day)] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Sets an hourly person's hours for a day; nil or 0 clears them.
    static func setHours(_ hours: Double?, for worker: Worker, on day: Date, in context: ModelContext) {
        let value = (hours ?? 0) > 0 ? hours : nil
        // Nothing changed: no new stamp, so a real change from another
        // device is not overruled (audit Oct 21, fix-now 2).
        if worker.entry(on: day)?.hours == value, value != nil || worker.entry(on: day) == nil { return }
        if let entry = worker.entry(on: day) {
            if value == nil, entry.note.isEmpty {
                context.delete(entry)
            } else {
                entry.hours = value
                entry.updatedAt = Date()
            }
        } else if let value {
            let entry = LaborEntry(worker: nil, day: day, hours: value)
            context.insert(entry)
            entry.worker = worker
        }
        try? context.save()
    }

    /// Marks a salaried person as working a day or not: off on a work day,
    /// or in on a day outside the work week.
    static func setWorked(_ worked: Bool, for worker: Worker, on day: Date, in context: ModelContext) {
        // What a day with no entry means: worked on a work day, off otherwise.
        let usual = worker.usuallyWorks(on: day)
        let existing = worker.entry(on: day)
        if worked == usual {
            if let existing {
                if existing.note.isEmpty {
                    context.delete(existing)
                } else {
                    existing.isOff = !worked
                    existing.updatedAt = Date()
                }
            }
        } else if let existing {
            existing.isOff = !worked
            existing.updatedAt = Date()
        } else {
            let entry = LaborEntry(worker: nil, day: day, isOff: !worked)
            context.insert(entry)
            entry.worker = worker
        }
        try? context.save()
    }

    /// Hours over some days (hourly crew).
    static func hours(_ worker: Worker, over days: [Date]) -> Double {
        days.reduce(0) { $0 + (worker.hours(on: $1) ?? 0) }
    }

    /// Days worked so far (up to today) over some days.
    static func daysWorked(_ worker: Worker, over days: [Date]) -> Int {
        let today = Dates.startOfToday()
        return days.filter { $0 <= today && worker.worked(on: $0) }.count
    }

    /// Hourly pay over some days, when a rate is set.
    static func pay(_ worker: Worker, over days: [Date]) -> Double? {
        guard !worker.isSalaried, let rate = worker.hourlyRate else { return nil }
        return hours(worker, over: days) * rate
    }

    /// "8", "7.5", "7.25"
    static func hoursText(_ hours: Double) -> String {
        hours.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "8 hrs", "1 hr"
    static func hoursLabel(_ hours: Double) -> String {
        hoursText(hours) + (hours == 1 ? " hr" : " hrs")
    }

    /// Reads "8", "7.5", "7 1/2", "7:30" (hours and minutes) or "8h".
    static func parseHours(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if let match = trimmed.firstMatch(of: /^(\d+):(\d{2})$/), let h = Double(match.output.1), let m = Double(match.output.2) {
            return h + m / 60
        }
        if let match = trimmed.firstMatch(of: /^(\d+)\s+1\/2/), let h = Double(match.output.1) {
            return h + 0.5
        }
        return Parse.money(trimmed)
    }

    /// What typed hours mean for the day: `.clear` for an empty box,
    /// `.hours` for a real day's work, `.invalid` for text that is not a
    /// number or is more than 24 hours ("85" for 8.5, a stray dot). An
    /// invalid entry keeps what was there before (Oct 20 phone audit).
    enum HoursInput: Equatable {
        case clear
        case hours(Double)
        case invalid
    }

    static func validHours(_ text: String) -> HoursInput {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .clear }
        guard let hours = parseHours(trimmed), hours >= 0 else { return .invalid }
        if hours == 0 { return .clear }
        return hours <= 24 ? .hours(hours) : .invalid
    }
}

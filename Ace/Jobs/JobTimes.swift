import Foundation
import SwiftData
import SwiftUI

// A job's times and clashes between jobs. The spec is docs/job-length.md:
// a job with a start time can also have an end time, picked or spoken;
// nothing is assumed when it has none. Saving a timed job warns when it
// clashes with another unfinished timed job that day.

extension Job {
    /// "9:00 to 11:00 AM" with an end time, "9:00 AM" without. Empty for a
    /// job with no time.
    var timeRangeText: String {
        hasTime ? JobTimes.text(start: scheduledAt, end: endsAt) : ""
    }
}

enum JobTimes {
    // Fixed US formats, the same in the lists and in the records sent to
    // Claude.
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "a"
        return formatter
    }()

    /// "9:00 AM" without an end (or with one that is not after the start);
    /// "9:00 to 11:00 AM" when both are in the same half of the day;
    /// "11:00 AM to 1:00 PM" across noon.
    static func text(start: Date, end: Date?) -> String {
        let startClock = clockFormatter.string(from: start)
        let startPeriod = periodFormatter.string(from: start)
        guard let end, end > start else { return startClock + " " + startPeriod }
        let endClock = clockFormatter.string(from: end)
        let endPeriod = periodFormatter.string(from: end)
        if startPeriod == endPeriod && Calendar.current.isDate(start, inSameDayAs: end) {
            return startClock + " to " + endClock + " " + endPeriod
        }
        return startClock + " " + startPeriod + " to " + endClock + " " + endPeriod
    }

    /// The day of `day` at the clock time of `time`, seconds dropped. An end
    /// picked on a time-only picker is always put on the job's own day.
    static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day) ?? day
    }

    /// The end on the start's day, or nil when there is no end time.
    static func end(start: Date, hasEnd: Bool, endTime: Date) -> Date? {
        hasEnd ? combine(day: start, time: endTime) : nil
    }

    /// False when an end is set and is not after the start.
    static func endIsValid(start: Date, hasEnd: Bool, endTime: Date) -> Bool {
        guard hasEnd else { return true }
        return combine(day: start, time: endTime) > start
    }

    /// Where the Ends picker starts when "Set an end time" is turned on:
    /// one hour after the start, or 11:59 PM when that would pass midnight.
    /// Only a starting point; nothing is saved until Save.
    static func suggestedEnd(after start: Date, calendar: Calendar = .current) -> Date {
        let hourLater = start.addingTimeInterval(3600)
        if calendar.isDate(hourLater, inSameDayAs: start) { return hourLater }
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: start) ?? start
    }

    /// The Assistant's `endTime` ("12:00") on the day of `start`. Nil when
    /// empty or unreadable.
    static func end(fromClock text: String, on start: Date, calendar: Calendar = .current) -> Date? {
        guard let clock = JobDraft.clock(from: text) else { return nil }
        return calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: start)
    }
}

enum JobOverlap {
    /// Other unfinished jobs with a time, on the same day as `start`, that
    /// clash with a job at `start` (ending at `end`, if it has an end),
    /// earliest first. `excluding` is the job being changed.
    static func find(start: Date, end: Date?, excluding: Job?, in jobs: [Job], calendar: Calendar = .current) -> [Job] {
        let skipID = excluding?.persistentModelID
        return jobs
            .filter { other in
                guard !other.isDone, other.hasTime else { return false }
                if let skipID, other.persistentModelID == skipID { return false }
                guard calendar.isDate(other.scheduledAt, inSameDayAs: start) else { return false }
                return clashes(start, end, other.scheduledAt, other.endsAt, calendar: calendar)
            }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /// The rule in docs/job-length.md, "What counts as a clash". Two spans
    /// clash when they overlap at all; ending exactly when the other starts
    /// is fine. A job with no end time (or an end not after its start) is
    /// its start moment only: it clashes with a span that contains that
    /// moment, or with a job starting at the same time. Compared to the
    /// minute.
    static func clashes(_ startA: Date, _ endA: Date?, _ startB: Date, _ endB: Date?, calendar: Calendar = .current) -> Bool {
        let a = minute(startA, calendar)
        let b = minute(startB, calendar)
        let spanA = spanEnd(endA, after: a, calendar)
        let spanB = spanEnd(endB, after: b, calendar)
        if let endA = spanA, let endB = spanB {
            return a < endB && b < endA
        }
        if let endA = spanA {
            return a <= b && b < endA
        }
        if let endB = spanB {
            return b <= a && a < endB
        }
        return a == b
    }

    private static func minute(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.start ?? date
    }

    /// The end to the minute, or nil when there is none or it is not after
    /// the start (then the job counts as its start moment).
    private static func spanEnd(_ end: Date?, after start: Date, _ calendar: Calendar) -> Date? {
        guard let end else { return nil }
        let rounded = minute(end, calendar)
        return rounded > start ? rounded : nil
    }

    /// "Overlaps Linda Johnson, Junk removal, 9:00 to 11:00 AM." with
    /// ", and 2 more" when there are others. Nil when nothing clashes.
    static func note(_ overlapping: [Job]) -> String? {
        guard let first = overlapping.first else { return nil }
        var text = "Overlaps " + name(of: first) + ", " + first.jobType.rawValue + ", " + first.timeRangeText
        if overlapping.count > 1 { text += ", and \(overlapping.count - 1) more" }
        return text + "."
    }

    /// "This overlaps Linda Johnson, 9:00 to 11:00 AM. Save anyway?" Nil
    /// when nothing clashes.
    static func question(_ overlapping: [Job]) -> String? {
        guard let first = overlapping.first else { return nil }
        return "This overlaps " + name(of: first) + ", " + first.timeRangeText + ". Save anyway?"
    }

    private static func name(of job: Job) -> String {
        job.customer?.name ?? "a job with no customer"
    }
}

/// The note under the times while the job clashes with another, in the
/// warning colour. Shows nothing when nothing clashes.
struct OverlapNote: View {
    let overlapping: [Job]

    var body: some View {
        if let note = JobOverlap.note(overlapping) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(Tint.warning)
        }
    }
}

/// "Set an end time" and, while it is on, "Ends". Turning it on puts the
/// picker one hour after the start, as a starting point only. An end not
/// after the start shows "Ends before it starts." in the warning colour;
/// the screen blocks Save until it is fixed. `note` is Claude's question
/// about the end time, if any.
struct EndTimeRows: View {
    @Binding var hasEnd: Bool
    @Binding var endTime: Date
    let start: Date
    var note: String? = nil

    private var endNote: String? {
        if !JobTimes.endIsValid(start: start, hasEnd: hasEnd, endTime: endTime) {
            return "Ends before it starts."
        }
        return note
    }

    var body: some View {
        Toggle("Set an end time", isOn: Binding(
            get: { hasEnd },
            set: { turnOn in
                if turnOn && !hasEnd { endTime = JobTimes.suggestedEnd(after: start) }
                hasEnd = turnOn
            }
        ))
        if hasEnd {
            FlaggedRow(endNote) {
                DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
            }
        }
    }
}

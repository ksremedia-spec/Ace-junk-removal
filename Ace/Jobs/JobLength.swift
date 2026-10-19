import Foundation
import SwiftData
import SwiftUI

// How long a job takes, the time range it covers, and overlaps between jobs.
// The spec is docs/job-length.md: every job with a time has a length (its
// own, or its type's default), and saving a timed job warns when it overlaps
// another unfinished timed job that day.

extension JobType {
    /// How long this kind of job takes when no length is set. Assumptions to
    /// be checked with Ashley and Alex.
    var defaultMinutes: Int {
        switch self {
        case .junkRemoval: return 120
        case .demolition: return 240
        case .dumpsterDropOff: return 30
        case .dumpsterPickup: return 30
        case .dumpsterSwap: return 60
        case .estimate: return 30
        case .other: return 30
        }
    }
}

extension Job {
    /// Minutes the job takes: its own length, or its type's default.
    var lengthMinutes: Int {
        durationMinutes > 0 ? durationMinutes : jobType.defaultMinutes
    }

    /// When the work ends: the start plus the length.
    var endsAt: Date {
        scheduledAt.addingTimeInterval(TimeInterval(lengthMinutes * 60))
    }

    /// "9:00 to 11:00 AM", or "11:00 AM to 1:00 PM" across noon. Empty for a
    /// job with no time.
    var timeRangeText: String {
        hasTime ? JobLength.rangeText(from: scheduledAt, to: endsAt) : ""
    }
}

enum JobLength {
    /// The lengths the How long picker offers, in minutes.
    static let standard = [30, 60, 90, 120, 150, 180, 240, 300, 360, 480]

    /// The standard lengths, with `current` added in order when it is not
    /// one of them (7 hours from the Assistant, say).
    static func choices(including current: Int) -> [Int] {
        guard current > 0, !standard.contains(current) else { return standard }
        return (standard + [current]).sorted()
    }

    /// "30 minutes", "1 hour", "1½ hours", "7 hours", "1 hour 15 minutes".
    static func label(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        let rest = minutes % 60
        let wholeHours = hours == 1 ? "1 hour" : "\(hours) hours"
        if rest == 0 { return wholeHours }
        if rest == 30 { return "\(hours)½ hours" }
        return wholeHours + " \(rest) minutes"
    }

    /// The Assistant's `hours`: "2" → 120, "1.5" → 90. Nil when empty,
    /// unreadable or not above zero.
    static func minutes(fromHours text: String) -> Int? {
        guard let hours = Parse.money(text), hours > 0 else { return nil }
        let minutes = Int((hours * 60).rounded())
        return minutes > 0 ? minutes : nil
    }

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

    /// "9:00 to 11:00 AM" when both ends are in the same half of the same
    /// day, else "11:00 AM to 1:00 PM".
    static func rangeText(from start: Date, to end: Date) -> String {
        let startClock = clockFormatter.string(from: start)
        let endClock = clockFormatter.string(from: end)
        let startPeriod = periodFormatter.string(from: start)
        let endPeriod = periodFormatter.string(from: end)
        if startPeriod == endPeriod && Calendar.current.isDate(start, inSameDayAs: end) {
            return startClock + " to " + endClock + " " + endPeriod
        }
        return startClock + " " + startPeriod + " to " + endClock + " " + endPeriod
    }
}

enum JobOverlap {
    /// Other unfinished jobs with a time, on the same day as `start`, whose
    /// time overlaps `start` for `minutes`, earliest first. `excluding` is
    /// the job being changed. A job that ends exactly when another starts
    /// does not overlap it.
    static func find(start: Date, minutes: Int, excluding: Job?, in jobs: [Job], calendar: Calendar = .current) -> [Job] {
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        let skipID = excluding?.persistentModelID
        return jobs
            .filter { other in
                guard !other.isDone, other.hasTime else { return false }
                if let skipID, other.persistentModelID == skipID { return false }
                guard calendar.isDate(other.scheduledAt, inSameDayAs: start) else { return false }
                return start < other.endsAt && other.scheduledAt < end
            }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /// "Overlaps Linda Johnson, Junk removal, 9:00 to 11:00 AM." with
    /// ", and 2 more" when there are others. Nil when nothing overlaps.
    static func note(_ overlapping: [Job]) -> String? {
        guard let first = overlapping.first else { return nil }
        var text = "Overlaps " + name(of: first) + ", " + first.jobType.rawValue + ", " + first.timeRangeText
        if overlapping.count > 1 { text += ", and \(overlapping.count - 1) more" }
        return text + "."
    }

    /// "This overlaps Linda Johnson, 9:00 to 11:00 AM. Save anyway?" Nil
    /// when nothing overlaps.
    static func question(_ overlapping: [Job]) -> String? {
        guard let first = overlapping.first else { return nil }
        return "This overlaps " + name(of: first) + ", " + first.timeRangeText + ". Save anyway?"
    }

    private static func name(of job: Job) -> String {
        job.customer?.name ?? "a job with no customer"
    }
}

/// The note under How long while the job overlaps another, in the warning
/// colour. Shows nothing when nothing overlaps.
struct OverlapNote: View {
    let overlapping: [Job]

    var body: some View {
        if let note = JobOverlap.note(overlapping) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }
}

/// "How long", for a job with a time. `minutes` 0 follows the job type's
/// default length; picking a length sets it by hand.
struct JobLengthPicker: View {
    @Binding var minutes: Int
    let jobType: JobType

    private var shown: Int {
        minutes > 0 ? minutes : jobType.defaultMinutes
    }

    var body: some View {
        Picker("How long", selection: Binding(get: { shown }, set: { minutes = $0 })) {
            ForEach(JobLength.choices(including: shown), id: \.self) { value in
                Text(JobLength.label(value)).tag(value)
            }
        }
    }
}

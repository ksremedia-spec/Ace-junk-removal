import Foundation

/// One action in the form the new-job, job-update and dumpster screens
/// take. Made from an `AssistantAction` (see `jobDraft(issues:)`); Claude
/// itself now answers with an `AssistantPlan`. `kind` says which screen:
/// a new job, an update to a job that already exists, a dumpster pickup or
/// a dumpster drop-off. Empty strings mean "the note did not say".
struct JobDraft: Codable, Equatable {
    struct Issue: Codable, Equatable, Identifiable {
        var field: String
        var question: String

        var id: String { field + question }
    }

    enum Kind: String, CaseIterable {
        case job, question, update, pickup, dropoff, other
    }

    var kind: String         // job, question, update, pickup, dropoff or other
    var answer: String       // for questions and "other", else ""
    var customerName: String
    var phone: String
    var address: String
    var jobType: String
    var date: String        // YYYY-MM-DD or ""
    var time: String        // HH:MM (24-hour) or ""
    var endTime: String = "" // HH:MM (24-hour) when the job ends, or ""
    var price: String       // digits only, e.g. "300", or ""
    var paymentType: String // cash, check, card, unknown
    var paid: String        // paid, unpaid, unknown
    var notes: String
    // Updates to an existing job.
    var done: String        // yes, no or ""
    var newDate: String     // YYYY-MM-DD or ""
    var newTime: String     // HH:MM or ""
    // Dumpster pickups and drop-offs.
    var dumpsterNumber: String // "1" through "6" or ""
    var actualTons: String     // digits like "2.8" or ""
    var agreedTons: String     // digits like "2" or ""
    var dueBack: String        // YYYY-MM-DD or ""
    var issues: [Issue]

    /// The kind as an enum. Anything unexpected is treated as a new job, the
    /// safest screen to land on.
    var noteKind: Kind { Kind(rawValue: kind.lowercased()) ?? .job }

    var isQuestion: Bool { noteKind == .question }

    /// The same note read as a new job, for "Start a new job instead".
    var asNewJob: JobDraft {
        var copy = self
        copy.kind = Kind.job.rawValue
        return copy
    }

    // MARK: Reading what Claude sent

    /// "2026-10-19" → that day at midnight, local time. Nil for anything else.
    static func day(from text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "09:30" → hour 9, minute 30. Nil for anything else.
    static func clock(from text: String) -> (hour: Int, minute: Int)? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    static func paymentType(from text: String) -> PaymentType? {
        switch text.lowercased() {
        case "cash": return .cash
        case "check": return .check
        case "card": return .card
        default: return nil
        }
    }
}

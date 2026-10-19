import Foundation
import SwiftData

// Finds the records a spoken note refers to: "Johnson's done" needs the
// Johnson job on the books, "picked up 3" needs Dumpster 3. Plain functions
// over the SwiftData models, no UI. The screens call them on the main
// actor, where the models live; nothing here needs an isolation attribute.

// MARK: Customers

/// Customers the note could mean: by phone first, then by name, then by
/// address. Best match first.
func matchCustomers(_ draft: JobDraft, in customers: [Customer]) -> [Customer] {
    let digits = draft.phone.filter(\.isNumber)
    if digits.count >= 7 {
        let byPhone = customers.filter { $0.phoneDigits == digits || $0.phoneDigits.hasSuffix(digits) }
        if !byPhone.isEmpty { return byPhone }
    }

    let spoken = SpokenName(draft.customerName)
    if !spoken.words.isEmpty {
        let exact = customers.filter { SpokenName($0.name).text == spoken.text }
        if !exact.isEmpty { return exact }
        let contains = customers.filter { SpokenName($0.name).text.contains(spoken.text) }
        if !contains.isEmpty { return contains }
        if let last = spoken.words.last {
            let byLastWord = customers.filter { SpokenName($0.name).words.last == last }
            if !byLastWord.isEmpty { return byLastWord }
        }
    }

    let spokenAddress = SpokenAddress(draft.address)
    if let number = spokenAddress.houseNumber, let street = spokenAddress.streetWord {
        return customers.filter { customer in
            let words = SpokenAddress.words(of: customer.address)
            return words.contains(number) && words.contains(street)
        }
    }
    return []
}

// MARK: Jobs

/// Jobs the note could mean, best first. With a customer match: that
/// customer's jobs on the spoken date, else not-done jobs today, else the
/// not-done jobs nearest to today, else the most recent done job. With no
/// customer match: today's not-done jobs for everyone, narrowed by job type
/// when one was said.
func matchJobs(_ draft: JobDraft, customers: [Customer], allJobs: [Job], today: Date) -> [Job] {
    let calendar = Calendar.current
    let spokenDay = JobDraft.day(from: draft.date)
    let spokenType = JobType.allCases.first { $0.rawValue.caseInsensitiveCompare(draft.jobType) == .orderedSame }

    if customers.isEmpty {
        let day = spokenDay ?? today
        return allJobs.filter { job in
            guard !job.isDone, calendar.isDate(job.scheduledAt, inSameDayAs: day) else { return false }
            if let spokenType { return job.jobType == spokenType }
            return true
        }
    }

    let ids = Set(customers.map(\.persistentModelID))
    let theirs = allJobs.filter { job in
        guard let customer = job.customer else { return false }
        return ids.contains(customer.persistentModelID)
    }

    if let spokenDay {
        let thatDay = theirs.filter { calendar.isDate($0.scheduledAt, inSameDayAs: spokenDay) }
        if !thatDay.isEmpty {
            return thatDay.sorted { a, b in
                if a.isDone != b.isDone { return !a.isDone }
                return a.scheduledAt < b.scheduledAt
            }
        }
    }

    let notDone = theirs.filter { !$0.isDone }
    let todayJobs = notDone.filter { calendar.isDate($0.scheduledAt, inSameDayAs: today) }
    if !todayJobs.isEmpty { return todayJobs.sorted { $0.scheduledAt < $1.scheduledAt } }
    if !notDone.isEmpty {
        return notDone.sorted { abs($0.scheduledAt.timeIntervalSince(today)) < abs($1.scheduledAt.timeIntervalSince(today)) }
    }
    if let latestDone = theirs.filter(\.isDone).max(by: { $0.scheduledAt < $1.scheduledAt }) {
        return [latestDone]
    }
    return []
}

// MARK: Dumpsters

/// Dumpsters the note could mean. `wantOut` true is a pickup: the numbered
/// dumpster if it is out, else the out dumpsters whose customer or location
/// matches what was said (all of them when nothing was said). `wantOut`
/// false is a drop-off: the dumpsters in the yard, the spoken number first.
func matchDumpster(_ draft: JobDraft, dumpsters: [Dumpster], wantOut: Bool) -> [Dumpster] {
    let number = Int(draft.dumpsterNumber.filter(\.isNumber))

    if !wantOut {
        let inYard = dumpsters.filter { !$0.isOut }.sorted { $0.number < $1.number }
        guard let number else { return inYard }
        return inYard.filter { $0.number == number } + inYard.filter { $0.number != number }
    }

    let out = dumpsters.filter(\.isOut).sorted { $0.number < $1.number }
    if let number {
        return out.filter { $0.number == number }
    }

    let words = SpokenName(draft.customerName).words + SpokenAddress.words(of: draft.address)
    let keywords = words.filter { $0.count >= 3 || $0.first?.isNumber == true }
    guard !keywords.isEmpty else { return out }
    return out.filter { dumpster in
        let haystack = SpokenName(dumpster.customer?.name ?? "").words + SpokenAddress.words(of: dumpster.location)
        return keywords.contains { haystack.contains($0) }
    }
}

// MARK: Words

/// A name reduced for matching: lowercased, without Mr/Mrs/Ms/Dr or a
/// possessive, so "Mrs. Johnson's" matches "Linda Johnson".
struct SpokenName {
    private static let honorifics: Set<String> = ["mr", "mrs", "ms", "miss", "dr"]

    let words: [String]

    init(_ text: String) {
        words = text.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { word -> String in
                var cleaned = String(word)
                if cleaned.hasSuffix("'s") || cleaned.hasSuffix("’s") { cleaned = String(cleaned.dropLast(2)) }
                return cleaned.filter { $0.isLetter || $0.isNumber || $0 == "-" }
            }
            .filter { !$0.isEmpty && !Self.honorifics.contains($0) }
    }

    var text: String { words.joined(separator: " ") }
}

/// The parts of a spoken address that are worth matching on.
struct SpokenAddress {
    let words: [String]

    init(_ text: String) {
        words = Self.words(of: text)
    }

    /// "7 Bay Road, Marshfield" → ["7", "bay", "road", "marshfield"].
    static func words(of text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// The first all-digit word, e.g. "7".
    var houseNumber: String? {
        words.first { $0.allSatisfy(\.isNumber) }
    }

    /// The first word after the house number that is not a number, e.g. "bay".
    var streetWord: String? {
        guard let index = words.firstIndex(where: { $0.allSatisfy(\.isNumber) }) else { return nil }
        return words.dropFirst(index + 1).first { !$0.allSatisfy(\.isNumber) }
    }
}

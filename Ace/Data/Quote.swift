import Foundation
import SwiftData

// A quote is a price given to someone who has not said yes yet. It stays on
// the Quotes list until it is booked (it becomes a job) or lost. The spec is
// docs/quotes.md.

/// Where a quote stands. Stored as its raw value, like the job type.
enum QuoteStatus: String, CaseIterable, Codable, Identifiable {
    case open = "Open"
    case booked = "Booked"
    case lost = "Lost"

    var id: String { rawValue }

    /// The choices above the Quotes list. Lost quotes are not listed (Kyle,
    /// 2026-10-19: "lose the lost quotes tab"); Mark Lost takes a quote off
    /// the Open list.
    static let listed: [QuoteStatus] = [.open, .booked]
}

/// Quote follow-ups (call-back days) are switched off for now (Kyle,
/// 2026-10-19: "get rid of quotes follow up for now"). The data stays, so
/// setting this back to true brings them back everywhere.
enum QuoteFeatures {
    static let followUps = false
}

@Model
final class Quote {
    // Every property has a default value, so a phone that already has the
    // app adds quotes to its database without losing anything.
    var customer: Customer?
    var jobTypeRaw: String = JobType.junkRemoval.rawValue
    /// What was quoted, one line: "Garage cleanout, about two loads".
    var details: String = ""
    var price: Double?
    /// The day the price was given.
    var quotedOn: Date = Date()
    /// The day to call them back, if one was set.
    var followUpOn: Date?
    var statusRaw: String = QuoteStatus.open.rawValue
    var notes: String = ""
    /// The job it became, once booked. Deleting the job clears this and
    /// leaves the quote booked (the rule is declared on `Job.quote`).
    var job: Job?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// The record's permanent ID, the same on every device (sync,
    /// docs/device-sync.md). Given when the record is made; records from
    /// before it existed get one on the first sync. Optional with no default,
    /// like `Job.jobID`, so an upgraded database does not give them all one value.
    var syncID: UUID? = nil

    init(customer: Customer? = nil,
         jobType: JobType = .junkRemoval,
         details: String = "",
         price: Double? = nil,
         quotedOn: Date = Dates.startOfToday(),
         followUpOn: Date? = nil,
         status: QuoteStatus = .open,
         notes: String = "") {
        self.customer = customer
        self.jobTypeRaw = jobType.rawValue
        self.details = details
        self.price = price
        self.quotedOn = quotedOn
        self.followUpOn = followUpOn
        self.statusRaw = status.rawValue
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
        self.syncID = UUID()
    }

    var jobType: JobType {
        get { JobType(stored: jobTypeRaw) }
        set { jobTypeRaw = newValue.rawValue }
    }

    var status: QuoteStatus {
        get { QuoteStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - Changes

extension Quote {
    /// The job made from this quote was saved: the quote is booked and
    /// points at it. A quote whose customer was deleted takes the job's.
    func markBooked(with job: Job) {
        status = .booked
        self.job = job
        if customer == nil { customer = job.customer }
        updatedAt = Date()
    }

    func markLost() {
        status = .lost
        updatedAt = Date()
    }

    /// Back on the open list. A booked quote keeps its link to the job,
    /// which stays on the schedule; it is shown again only if re-booked.
    func reopen() {
        status = .open
        updatedAt = Date()
    }
}

// MARK: - Text for the screens

extension Quote {
    /// "Junk removal · $450" or "Junk removal · No price".
    var typeAndPriceText: String {
        jobType.rawValue + " · " + (price.map(Money.text) ?? "No price")
    }

    /// Open, with a follow-up day of today or earlier.
    func isFollowUpDue(today: Date = Dates.startOfToday()) -> Bool {
        guard QuoteFeatures.followUps, status == .open, let followUpOn else { return false }
        return Calendar.current.startOfDay(for: followUpOn) <= today
    }

    /// "Follow up today", "Follow up was Fri, Oct 16" or "Follow up Thu,
    /// Oct 22". Nil when no follow-up day is set.
    func followUpText(today: Date = Dates.startOfToday()) -> String? {
        guard let followUpOn else { return nil }
        let day = Calendar.current.startOfDay(for: followUpOn)
        if day == today { return "Follow up today" }
        if day < today { return "Follow up was " + Dates.shortDay(followUpOn) }
        return "Follow up " + Dates.shortDay(followUpOn)
    }

    /// "Quoted Mon, Oct 12 · Follow up Thu, Oct 15". The follow-up part is
    /// left off once the quote is booked or lost.
    func datesText(today: Date = Dates.startOfToday()) -> String {
        var text = "Quoted " + Dates.shortDay(quotedOn)
        if QuoteFeatures.followUps, status == .open, let followUp = followUpText(today: today) {
            text += " · " + followUp
        }
        return text
    }
}

// MARK: - Search and grouping (shared by the iPhone and Mac lists)

enum QuoteSearch {
    /// Quotes whose customer name, phone or address, or whose details,
    /// contain `text`. Empty text keeps everything.
    static func filter(_ quotes: [Quote], _ text: String) -> [Quote] {
        let search = SearchText(text)
        guard !search.isEmpty else { return quotes }
        return quotes.filter { quote in
            search.matches(texts: [quote.customer?.name ?? "", quote.customer?.address ?? "", quote.details, quote.notes],
                           phoneDigits: quote.customer?.phoneDigits ?? "")
        }
    }
}

enum QuoteList {
    /// The quotes with this status. Open ones oldest quote first; booked
    /// and lost ones newest first.
    static func shown(_ quotes: [Quote], status: QuoteStatus) -> [Quote] {
        let matching = quotes.filter { $0.status == status }
        switch status {
        case .open:
            return matching.sorted { oldestFirst($0, $1) }
        case .booked, .lost:
            return matching.sorted { oldestFirst($1, $0) }
        }
    }

    /// Open quotes whose follow-up day is today or earlier, earliest first.
    static func followUp(_ quotes: [Quote], today: Date = Dates.startOfToday()) -> [Quote] {
        quotes.filter { $0.isFollowUpDue(today: today) }
            .sorted { a, b in
                let dayA = a.followUpOn ?? .distantFuture
                let dayB = b.followUpOn ?? .distantFuture
                return dayA != dayB ? dayA < dayB : oldestFirst(a, b)
            }
    }

    /// Every other open quote, in the order given (oldest quote first).
    static func waiting(_ quotes: [Quote], today: Date = Dates.startOfToday()) -> [Quote] {
        quotes.filter { !$0.isFollowUpDue(today: today) }
    }

    /// "5 open · $3,250", "2 lost · $900". The money is left off when no
    /// quote has a price; nil for an empty list.
    static func header(_ shown: [Quote], status: QuoteStatus) -> String? {
        guard !shown.isEmpty else { return nil }
        var text = "\(shown.count) " + status.rawValue.lowercased()
        let total: Double = shown.reduce(0) { $0 + ($1.price ?? 0) }
        if total > 0 { text += " · " + Money.text(total) }
        return text
    }

    private static func oldestFirst(_ a: Quote, _ b: Quote) -> Bool {
        a.quotedOn != b.quotedOn ? a.quotedOn < b.quotedOn : a.createdAt < b.createdAt
    }
}

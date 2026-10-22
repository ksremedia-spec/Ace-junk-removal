import Foundation
import SwiftData

// The things the business keeps track of (quotes are in Quote.swift).
// Stored on the device with SwiftData (Apple's on-device database), so the
// app works offline. Every record carries `updatedAt` so a later sync to the
// Cloudflare backend can tell what changed.

// MARK: - Customer

@Model
final class Customer {
    var name: String
    var phone: String
    var address: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    /// The record's permanent ID, the same on every device (sync,
    /// docs/device-sync.md). Given when the record is made; records from
    /// before it existed get one on the first sync. Optional with no default,
    /// like `Job.jobID`, so an upgraded database does not give them all one value.
    var syncID: UUID? = nil

    @Relationship(deleteRule: .nullify, inverse: \Job.customer)
    var jobs: [Job] = []

    // Declared so that deleting a customer clears these references instead of
    // leaving a dumpster or a past rental pointing at a deleted record.
    @Relationship(deleteRule: .nullify, inverse: \Dumpster.customer)
    var dumpsters: [Dumpster] = []

    @Relationship(deleteRule: .nullify, inverse: \RentalRecord.customer)
    var rentals: [RentalRecord] = []

    /// Deleting a customer leaves their quotes without a customer, as with jobs.
    @Relationship(deleteRule: .nullify, inverse: \Quote.customer)
    var quotes: [Quote] = []

    init(name: String, phone: String = "", address: String = "", notes: String = "") {
        self.name = name
        self.phone = phone
        self.address = address
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
        self.syncID = UUID()
    }

    /// Phone number reduced to digits, for matching "508-555-0147" to
    /// "5085550147" (and "+1 508..." to the same).
    var phoneDigits: String {
        PhoneFormat.digits(phone)
    }

    /// Whether this customer fits a search: see `SearchText`.
    func matches(_ search: SearchText) -> Bool {
        search.matches(texts: [name, address], phoneDigits: phoneDigits)
    }
}

// MARK: - Job

enum JobType: String, CaseIterable, Codable, Identifiable {
    case junkRemoval = "Junk removal"
    case demolition = "Demolition"
    case dumpsterDropOff = "Dumpster drop-off"
    case dumpsterPickup = "Dumpster pickup"
    case dumpsterSwap = "Dumpster swap"
    /// A visit to look at the work and give a price. The office calls it a
    /// quote, never an estimate (Kyle, Oct 20); stored before that as
    /// "Estimate", which `init(stored:)` still reads.
    case estimate = "Quote visit"
    case other = "Other"

    var id: String { rawValue }

    /// Reads a stored type, including names used by older versions.
    init(stored: String) {
        if let type = JobType(rawValue: stored) {
            self = type
        } else if stored.caseInsensitiveCompare("Estimate") == .orderedSame {
            self = .estimate
        } else {
            self = .other
        }
    }
}

/// How a job was paid. Venmo and Cash App added Oct 21, 2026: Ashley's sheet
/// uses both. Stored by name, so adding one leaves saved jobs as they were.
enum PaymentType: String, CaseIterable, Codable, Identifiable {
    case cash = "Cash"
    case check = "Check"
    case card = "Card"
    case venmo = "Venmo"
    case cashApp = "Cash App"
    case unknown = "Not set"

    var id: String { rawValue }
}

@Model
final class Job {
    var customer: Customer?
    var jobTypeRaw: String
    /// The scheduled date. When `hasTime` is false, only the day matters.
    var scheduledAt: Date
    var hasTime: Bool
    var price: Double?
    var paymentTypeRaw: String
    var isPaid: Bool
    var isDone: Bool
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    /// When the work ends, if an end time was picked or said. Nil means no
    /// end time: the job is its start time only (see JobTimes.swift). Same
    /// day as the start and later than it; matters only when `hasTime` is on.
    var endsAt: Date? = nil

    /// The quote this job was booked from, if any. Declared here so that
    /// deleting the job clears the quote's link (the quote stays booked).
    @Relationship(deleteRule: .nullify, inverse: \Quote.job)
    var quote: Quote? = nil

    /// The job's permanent ID, the same on every device. Given when the job
    /// is created; jobs from before it existed get one the first time they
    /// are written to the calendar (CalendarStore). Optional with no default
    /// so existing jobs do not all get the same value when the database is
    /// upgraded. Ace's own sync (step 5) needs it too.
    var jobID: UUID? = nil

    /// The identifier of the job's event in the Calendar for Jobs on this
    /// device, for a quick look-up. Only a shortcut: the marker line in the
    /// event's notes is what proves it is this job's event.
    var calendarItemID: String? = nil

    /// When the job's event was last written on this device.
    var calendarWrittenAt: Date? = nil

    init(customer: Customer?,
         jobType: JobType,
         scheduledAt: Date,
         hasTime: Bool,
         price: Double? = nil,
         paymentType: PaymentType = .unknown,
         isPaid: Bool = false,
         notes: String = "") {
        self.customer = customer
        self.jobTypeRaw = jobType.rawValue
        self.scheduledAt = scheduledAt
        self.hasTime = hasTime
        self.price = price
        self.paymentTypeRaw = paymentType.rawValue
        self.isPaid = isPaid
        self.isDone = false
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
        self.jobID = UUID()
    }

    var jobType: JobType {
        get { JobType(stored: jobTypeRaw) }
        set { jobTypeRaw = newValue.rawValue }
    }

    var paymentType: PaymentType {
        get { PaymentType(rawValue: paymentTypeRaw) ?? .unknown }
        set { paymentTypeRaw = newValue.rawValue }
    }

    /// "Fri, Oct 24, 9:00 to 11:00 AM", "Fri, Oct 24, 9:00 AM" or "Fri, Oct 24".
    var whenText: String {
        let day = Dates.shortDay(scheduledAt)
        return hasTime ? day + ", " + timeRangeText : day
    }

    var priceText: String {
        guard let price else { return "" }
        return Money.text(price)
    }
}

// MARK: - Dumpster

@Model
final class Dumpster {
    /// 1 through 6, as painted on the side.
    var number: Int
    /// Size or nickname, e.g. "15 yard". Optional.
    var label: String

    // The current rental, if the dumpster is out.
    var isOut: Bool
    var customer: Customer?
    var location: String
    var droppedOffAt: Date?
    var dueBackAt: Date?
    var price: Double?
    /// Weight included in the price, in tons.
    var agreedWeightTons: Double?
    var notes: String
    /// Something about the dumpster itself ("cracked door, don't send it
    /// out"). Kept until changed; a pickup or drop-off leaves it alone.
    var conditionNote: String = ""
    var updatedAt: Date

    /// The dumpster's permanent ID for the sync. Worked out from its
    /// number on the first sync (`SyncIDs.dumpster`), not random, so two
    /// devices that each set up six dumpsters end up with the same six.
    var syncID: UUID? = nil

    @Relationship(deleteRule: .cascade, inverse: \RentalRecord.dumpster)
    var history: [RentalRecord] = []

    init(number: Int, label: String = "") {
        self.number = number
        self.label = label
        self.isOut = false
        self.location = ""
        self.notes = ""
        self.updatedAt = Date()
    }

    var displayName: String {
        label.isEmpty ? "Dumpster \(number)" : "Dumpster \(number) · \(label)"
    }

    enum Status: String {
        case inYard = "In the yard"
        case out = "Out"
        case dueToday = "Due today"
        case overdue = "Overdue"
    }

    func status(on date: Date = Date(), calendar: Calendar = .current) -> Status {
        guard isOut else { return .inYard }
        guard let dueBackAt else { return .out }
        if calendar.isDate(dueBackAt, inSameDayAs: date) { return .dueToday }
        if calendar.startOfDay(for: dueBackAt) < calendar.startOfDay(for: date) { return .overdue }
        return .out
    }

    /// Sends the dumpster out on a new rental. Every drop-off path (the
    /// dumpster screen and the Assistant) calls this so they behave the same.
    func dropOff(to customer: Customer?,
                 location: String,
                 on date: Date,
                 dueBack: Date,
                 price: Double?,
                 agreedWeightTons: Double?,
                 notes: String) {
        isOut = true
        self.customer = customer
        self.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        droppedOffAt = date
        dueBackAt = dueBack
        self.price = price
        self.agreedWeightTons = agreedWeightTons
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedAt = Date()
    }

    /// Clears the current rental and files it in the history.
    func markPickedUp(actualWeightTons: Double?, ratePerTon: Double, on date: Date = Date()) {
        let record = RentalRecord(
            dumpster: nil,
            customer: nil,
            location: location,
            droppedOffAt: droppedOffAt ?? date,
            pickedUpAt: date,
            price: price,
            agreedWeightTons: agreedWeightTons,
            actualWeightTons: actualWeightTons,
            ratePerTon: ratePerTon
        )
        // Insert first, then connect, so relationships are set on a stored record.
        modelContext?.insert(record)
        record.customer = customer
        history.append(record)
        isOut = false
        customer = nil
        location = ""
        droppedOffAt = nil
        dueBackAt = nil
        price = nil
        agreedWeightTons = nil
        notes = ""
        updatedAt = date
    }
}

@Model
final class RentalRecord {
    var dumpster: Dumpster?
    var customer: Customer?
    var location: String
    var droppedOffAt: Date
    var pickedUpAt: Date
    var price: Double?
    var agreedWeightTons: Double?
    var actualWeightTons: Double?
    var ratePerTon: Double

    /// The record's permanent ID, the same on every device (sync). Given
    /// when the record is made; older records get one on the first sync.
    var syncID: UUID? = nil
    /// When the record last changed, for the sync. Older records have none.
    var updatedAt: Date? = nil

    init(dumpster: Dumpster?,
         customer: Customer?,
         location: String,
         droppedOffAt: Date,
         pickedUpAt: Date,
         price: Double?,
         agreedWeightTons: Double?,
         actualWeightTons: Double?,
         ratePerTon: Double) {
        self.dumpster = dumpster
        self.customer = customer
        self.location = location
        self.droppedOffAt = droppedOffAt
        self.pickedUpAt = pickedUpAt
        self.price = price
        self.agreedWeightTons = agreedWeightTons
        self.actualWeightTons = actualWeightTons
        self.ratePerTon = ratePerTon
        self.syncID = UUID()
        self.updatedAt = Date()
    }

    var overweightCharge: Double {
        Overweight.charge(agreedTons: agreedWeightTons, actualTons: actualWeightTons, ratePerTon: ratePerTon)
    }
}

// MARK: - Helpers

enum Overweight {
    /// Rate per ton over the agreed weight. Partial tons are charged in proportion.
    static func charge(agreedTons: Double?, actualTons: Double?, ratePerTon: Double) -> Double {
        guard let agreedTons, let actualTons, actualTons > agreedTons else { return 0 }
        // To the cent, so $100.0000001 never shows as "$100.00".
        return ((actualTons - agreedTons) * ratePerTon * 100).rounded() / 100
    }
}

enum Money {
    static func text(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(amount.rounded() == amount ? 0 : 2)))
    }
}

// MARK: - Figures for the screens

extension Customer {
    /// The earliest job on file, or nil for a customer with no jobs yet.
    var firstJobDate: Date? {
        jobs.map(\.scheduledAt).min()
    }

    /// The latest job that has happened (today or earlier). Upcoming work
    /// is `nextJobDate`.
    var lastJobDate: Date? {
        let end = Dates.startOfToday().addingTimeInterval(86_400)
        return jobs.map(\.scheduledAt).filter { $0 < end }.max()
    }

    /// The soonest job still to come that is not done.
    var nextJobDate: Date? {
        let today = Dates.startOfToday()
        return jobs.filter { !$0.isDone && $0.scheduledAt >= today }.map(\.scheduledAt).min()
    }

    /// Done work's prices added up, paid or not. Work still to come is not
    /// billed yet.
    var totalBilled: Double {
        jobs.filter(\.isDone).reduce(0) { $0 + ($1.price ?? 0) }
    }

    /// Prices of done jobs that have not been paid.
    var amountOwed: Double {
        jobs.reduce(0) { $0 + $1.owedAmount }
    }

    /// Dumpsters out with this customer right now, lowest number first.
    var dumpstersOut: [Dumpster] {
        dumpsters.filter(\.isOut).sorted { $0.number < $1.number }
    }

    /// Past rentals, newest first.
    var rentalsNewestFirst: [RentalRecord] {
        rentals.sorted { $0.pickedUpAt > $1.pickedUpAt }
    }

    /// "tel:5085550147", for a Call link. Nil without a phone number.
    var phoneURL: URL? {
        let digits = phoneDigits
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    /// Driving directions to the address in Apple Maps. Nil without an
    /// address.
    var directionsURL: URL? { Maps.directions(to: address) }

    /// Deletes the customer and saves. Their jobs, quotes, dumpsters and
    /// rental records stay and lose the customer (the `.nullify` rules above).
    /// The events of their jobs in the Calendar for Jobs are rewritten
    /// without the name, address and phone. Every delete path calls this so
    /// they all behave the same.
    @MainActor
    func remove(from context: ModelContext) {
        let rewrite = CalendarStore.shared.jobsWritten(for: self)
        // Cleared here rather than left to the delete rule, so nothing reads
        // the deleted customer while the events are rewritten.
        for job in rewrite {
            job.customer = nil
        }
        context.delete(self)
        try? context.save()
        for job in rewrite {
            CalendarStore.shared.jobSaved(job)
        }
    }
}

extension Job {
    /// The price, when the work is done and not paid. Zero otherwise.
    var owedAmount: Double {
        isDone && !isPaid ? (price ?? 0) : 0
    }

    /// Done, priced and not paid: the same rule as `owedAmount`, so the
    /// Unpaid list, its sidebar count and the Owed figure always agree.
    /// (Until Oct 20 2026 this also counted done jobs with no price and past
    /// jobs never marked done; those belong under "Not marked done".)
    func isUnpaid(asOf today: Date = Dates.startOfToday()) -> Bool {
        owedAmount > 0
    }

    /// Removes the job's event from the Calendar for Jobs, then deletes the
    /// job and saves. Every delete path calls this so they all behave the
    /// same.
    @MainActor
    func remove(from context: ModelContext) {
        CalendarStore.shared.jobDeleting(self)
        context.delete(self)
        try? context.save()
    }
}

extension Array where Element == Job {
    /// Prices added up; jobs without a price count as zero.
    var priceTotal: Double {
        reduce(0) { $0 + ($1.price ?? 0) }
    }
}

extension Dumpster {
    /// "Out since Mon, Oct 12 · due back Sun, Oct 19 · $450", for the customer screen.
    var currentRentalLine: String {
        var parts: [String] = []
        if let droppedOffAt { parts.append("Out since " + Dates.shortDay(droppedOffAt)) }
        if let dueBackAt { parts.append("due back " + Dates.shortDay(dueBackAt)) }
        if let price { parts.append(Money.text(price)) }
        return parts.isEmpty ? "Out" : parts.joined(separator: " · ")
    }
}

extension RentalRecord {
    /// The rental price plus the overweight charge.
    var total: Double {
        (price ?? 0) + overweightCharge
    }

    /// "Dumpster 3 · Mon, Sep 8 to Fri, Sep 12 · 2.4 of 2 tons · overweight $50",
    /// for the customer screen.
    var customerLine: String {
        var parts: [String] = []
        if let dumpster { parts.append("Dumpster \(dumpster.number)") }
        parts.append(Dates.shortDay(droppedOffAt) + " to " + Dates.shortDay(pickedUpAt))
        if let agreed = agreedWeightTons, let actual = actualWeightTons {
            parts.append(Tons.number(actual) + " of " + Tons.text(agreed))
        }
        if overweightCharge > 0 {
            parts.append("overweight " + Money.text(overweightCharge))
        }
        return parts.joined(separator: " · ")
    }
}

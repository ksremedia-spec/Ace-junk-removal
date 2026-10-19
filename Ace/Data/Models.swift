import Foundation
import SwiftData

// The three things the business keeps track of. Stored on the device with
// SwiftData (Apple's on-device database), so the app works offline. Every
// record carries `updatedAt` so a later sync to the Cloudflare backend can
// tell what changed.

// MARK: - Customer

@Model
final class Customer {
    var name: String
    var phone: String
    var address: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Job.customer)
    var jobs: [Job] = []

    // Declared so that deleting a customer clears these references instead of
    // leaving a dumpster or a past rental pointing at a deleted record.
    @Relationship(deleteRule: .nullify, inverse: \Dumpster.customer)
    var dumpsters: [Dumpster] = []

    @Relationship(deleteRule: .nullify, inverse: \RentalRecord.customer)
    var rentals: [RentalRecord] = []

    init(name: String, phone: String = "", address: String = "", notes: String = "") {
        self.name = name
        self.phone = phone
        self.address = address
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Phone number reduced to digits, for matching "508-555-0147" to "5085550147".
    var phoneDigits: String {
        phone.filter(\.isNumber)
    }
}

// MARK: - Job

enum JobType: String, CaseIterable, Codable, Identifiable {
    case junkRemoval = "Junk removal"
    case dumpsterDropOff = "Dumpster drop-off"
    case dumpsterPickup = "Dumpster pickup"
    case other = "Other"

    var id: String { rawValue }
}

enum PaymentType: String, CaseIterable, Codable, Identifiable {
    case cash = "Cash"
    case check = "Check"
    case card = "Card"
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
    }

    var jobType: JobType {
        get { JobType(rawValue: jobTypeRaw) ?? .other }
        set { jobTypeRaw = newValue.rawValue }
    }

    var paymentType: PaymentType {
        get { PaymentType(rawValue: paymentTypeRaw) ?? .unknown }
        set { paymentTypeRaw = newValue.rawValue }
    }

    /// "Fri, Oct 24 at 9:00 AM" or "Fri, Oct 24".
    var whenText: String {
        if hasTime {
            return scheduledAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        }
        return scheduledAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
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
    var updatedAt: Date

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
        return (actualTons - agreedTons) * ratePerTon
    }
}

enum Money {
    static func text(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(amount.rounded() == amount ? 0 : 2)))
    }
}

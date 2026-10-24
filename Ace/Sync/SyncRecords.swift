import CryptoKit
import Foundation
import SwiftData

/// What each record looks like on the way to and from the sync server
/// (docs/device-sync.md). Links to other records travel as their IDs.
/// Calendar bookkeeping and anything device-only stays out.
enum SyncType: String, CaseIterable {
    // The order records are applied in, so a record's links already exist.
    // `setting` is the business's shared settings, kept in UserDefaults
    // rather than the database (audit Oct 24, findings 4 and 36).
    case customer, worker, dumpster, job, quote, rental, labor, setting
}

struct CustomerData: Codable, Equatable {
    var name: String
    var phone: String
    var address: String
    var notes: String
    var createdAt: Date
}

struct WorkerData: Codable, Equatable {
    var name: String
    var payType: String
    var hourlyRate: Double?
    var phone: String
    var notes: String
    var isActive: Bool
    var createdAt: Date
}

struct DumpsterData: Codable, Equatable {
    var number: Int
    var label: String
    var isOut: Bool
    var customer: UUID?
    var location: String
    var droppedOffAt: Date?
    var dueBackAt: Date?
    var price: Double?
    var agreedWeightTons: Double?
    var notes: String
    var conditionNote: String
}

struct JobData: Codable, Equatable {
    var customer: UUID?
    var jobType: String
    var scheduledAt: Date
    var hasTime: Bool
    var endsAt: Date?
    var price: Double?
    var paymentType: String
    var isPaid: Bool
    var isDone: Bool
    var notes: String
    var createdAt: Date
}

struct QuoteData: Codable, Equatable {
    var customer: UUID?
    var job: UUID?
    var jobType: String
    var details: String
    var price: Double?
    var quotedOn: Date
    var followUpOn: Date?
    var status: String
    var notes: String
    var createdAt: Date
}

struct RentalData: Codable, Equatable {
    var dumpster: UUID?
    var customer: UUID?
    var location: String
    var droppedOffAt: Date
    var pickedUpAt: Date
    var price: Double?
    var agreedWeightTons: Double?
    var actualWeightTons: Double?
    var ratePerTon: Double
}

struct LaborData: Codable, Equatable {
    var worker: UUID?
    var day: Date
    var hours: Double?
    var isOff: Bool
    var note: String
}

/// The one shared settings record. A missing field was never set on any
/// device, so each device keeps its own default.
struct SettingData: Codable, Equatable {
    var overweightRatePerTon: Double?
    /// Calendar weekday numbers, 1 is Sunday.
    var salaryDays: [Int]?
}

/// IDs worked out from what a record is, so two devices that make "the
/// same" record give it the same ID (a name-based UUID, version 5 layout).
enum SyncIDs {
    static func dumpster(_ number: Int) -> UUID {
        named("dumpster-\(number)")
    }

    static func rental(dumpster: Int, droppedOff: Date) -> UUID {
        named("rental-\(dumpster)-\(Int(droppedOff.timeIntervalSince1970 / 60))")
    }

    /// The shared settings record: one per business, the same ID everywhere.
    static let settings = named("settings")

    static func labor(worker: UUID, day: Date, calendar: Calendar = .current) -> UUID {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return named("labor-\(worker.uuidString)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)")
    }

    private static func named(_ name: String) -> UUID {
        var b = Array(Insecure.SHA1.hash(data: Data(("ace-sync:" + name).utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

/// Every record in the database, with its ID, as the sync sees it.
@MainActor
struct SyncSnapshot {
    var customers: [UUID: Customer] = [:]
    var workers: [UUID: Worker] = [:]
    var dumpsters: [UUID: Dumpster] = [:]
    var jobs: [UUID: Job] = [:]
    var quotes: [UUID: Quote] = [:]
    var rentals: [UUID: RentalRecord] = [:]
    var labor: [UUID: LaborEntry] = [:]

    /// Reads everything, giving an ID to any record without one. Returns
    /// whether any ID was given (the caller saves).
    static func read(_ context: ModelContext) -> (SyncSnapshot, Bool) {
        var s = SyncSnapshot()
        var changed = false
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }

        for c in all(Customer.self) {
            if c.syncID == nil { c.syncID = UUID(); changed = true }
            s.customers[c.syncID!] = c
        }
        for w in all(Worker.self) {
            if w.syncID == nil { w.syncID = UUID(); changed = true }
            s.workers[w.syncID!] = w
        }
        for d in all(Dumpster.self) {
            if d.syncID == nil { d.syncID = SyncIDs.dumpster(d.number); changed = true }
            s.dumpsters[d.syncID!] = d
        }
        for j in all(Job.self) {
            if j.jobID == nil { j.jobID = UUID(); changed = true }
            s.jobs[j.jobID!] = j
        }
        for q in all(Quote.self) {
            if q.syncID == nil { q.syncID = UUID(); changed = true }
            s.quotes[q.syncID!] = q
        }
        for r in all(RentalRecord.self) {
            // Two rentals of one dumpster dropped off the same day were given
            // the same ID (audit Oct 24, finding 27): the second gets its own,
            // so both reach the other devices.
            if r.syncID == nil || s.rentals[r.syncID!] != nil { r.syncID = UUID(); changed = true }
            s.rentals[r.syncID!] = r
        }
        for e in all(LaborEntry.self) {
            if e.syncID == nil, let worker = e.worker?.syncID {
                e.syncID = SyncIDs.labor(worker: worker, day: e.day)
                changed = true
            }
            // An entry with no person cannot be placed on another device.
            if let id = e.syncID { s.labor[id] = e }
        }
        return (s, changed)
    }

    func ids(of type: SyncType) -> [UUID] {
        switch type {
        case .customer: return Array(customers.keys)
        case .worker: return Array(workers.keys)
        case .dumpster: return Array(dumpsters.keys)
        case .job: return Array(jobs.keys)
        case .quote: return Array(quotes.keys)
        case .rental: return Array(rentals.keys)
        case .labor: return Array(labor.keys)
        case .setting: return AppSettings.sharedUpdatedAt == nil ? [] : [SyncIDs.settings]
        }
    }

    /// The record is on this device.
    func has(_ type: SyncType, _ id: UUID) -> Bool {
        switch type {
        case .customer: return customers[id] != nil
        case .worker: return workers[id] != nil
        case .dumpster: return dumpsters[id] != nil
        case .job: return jobs[id] != nil
        case .quote: return quotes[id] != nil
        case .rental: return rentals[id] != nil
        case .labor: return labor[id] != nil
        case .setting: return id == SyncIDs.settings && AppSettings.sharedUpdatedAt != nil
        }
    }

    /// The record's fields as sent, and when it last changed.
    func encoded(_ type: SyncType, _ id: UUID) -> (data: Data, updatedAt: Date?)? {
        let coder = SyncCoding.encoder
        switch type {
        case .customer:
            guard let c = customers[id] else { return nil }
            return (try! coder.encode(CustomerData(name: c.name, phone: c.phone, address: c.address, notes: c.notes, createdAt: c.createdAt)), c.updatedAt)
        case .worker:
            guard let w = workers[id] else { return nil }
            return (try! coder.encode(WorkerData(name: w.name, payType: w.payTypeRaw, hourlyRate: w.hourlyRate, phone: w.phone,
                                                 notes: w.notes, isActive: w.isActive, createdAt: w.createdAt)), w.updatedAt)
        case .dumpster:
            guard let d = dumpsters[id] else { return nil }
            return (try! coder.encode(DumpsterData(number: d.number, label: d.label, isOut: d.isOut, customer: d.customer?.syncID,
                                                   location: d.location, droppedOffAt: d.droppedOffAt, dueBackAt: d.dueBackAt,
                                                   price: d.price, agreedWeightTons: d.agreedWeightTons, notes: d.notes,
                                                   conditionNote: d.conditionNote)), d.updatedAt)
        case .job:
            guard let j = jobs[id] else { return nil }
            return (try! coder.encode(JobData(customer: j.customer?.syncID, jobType: j.jobTypeRaw, scheduledAt: j.scheduledAt,
                                              hasTime: j.hasTime, endsAt: j.endsAt, price: j.price, paymentType: j.paymentTypeRaw,
                                              isPaid: j.isPaid, isDone: j.isDone, notes: j.notes, createdAt: j.createdAt)), j.updatedAt)
        case .quote:
            guard let q = quotes[id] else { return nil }
            return (try! coder.encode(QuoteData(customer: q.customer?.syncID, job: q.job?.jobID, jobType: q.jobTypeRaw, details: q.details,
                                                price: q.price, quotedOn: q.quotedOn, followUpOn: q.followUpOn, status: q.statusRaw,
                                                notes: q.notes, createdAt: q.createdAt)), q.updatedAt)
        case .rental:
            guard let r = rentals[id] else { return nil }
            return (try! coder.encode(RentalData(dumpster: r.dumpster?.syncID, customer: r.customer?.syncID, location: r.location,
                                                 droppedOffAt: r.droppedOffAt, pickedUpAt: r.pickedUpAt, price: r.price,
                                                 agreedWeightTons: r.agreedWeightTons, actualWeightTons: r.actualWeightTons,
                                                 ratePerTon: r.ratePerTon)), r.updatedAt)
        case .labor:
            guard let e = labor[id] else { return nil }
            return (try! coder.encode(LaborData(worker: e.worker?.syncID, day: e.day, hours: e.hours, isOff: e.isOff, note: e.note)), e.updatedAt)
        case .setting:
            guard id == SyncIDs.settings, let at = AppSettings.sharedUpdatedAt else { return nil }
            return (try! coder.encode(SettingData(overweightRatePerTon: AppSettings.storedOverweightRate,
                                                  salaryDays: AppSettings.storedSalaryDays?.sorted())), at)
        }
    }

    /// Stamps the record's "last changed" time (the sync's own stamp, for an
    /// edit that changed fields without stamping).
    func stamp(_ type: SyncType, _ id: UUID, _ date: Date) {
        switch type {
        case .customer: customers[id]?.updatedAt = date
        case .worker: workers[id]?.updatedAt = date
        case .dumpster: dumpsters[id]?.updatedAt = date
        case .job: jobs[id]?.updatedAt = date
        case .quote: quotes[id]?.updatedAt = date
        case .rental: rentals[id]?.updatedAt = date
        case .labor: labor[id]?.updatedAt = date
        case .setting: if id == SyncIDs.settings { AppSettings.stampShared(date) }
        }
    }

    // MARK: Applying a record from another device

    /// Creates or updates the record from the server's copy. Links point at
    /// records already in the snapshot; a link to a record not here is
    /// cleared. Returns false when a link was cleared that way, so the
    /// change can be applied again once the linked record arrives.
    @discardableResult
    mutating func apply(_ type: SyncType, _ id: UUID, _ json: Data, updatedAt: Date, in context: ModelContext) throws -> Bool {
        let coder = SyncCoding.decoder
        /// The link was empty, or the record it points at is here.
        func found(_ link: UUID?, _ target: AnyObject?) -> Bool { link == nil || target != nil }
        switch type {
        case .customer:
            let d = try coder.decode(CustomerData.self, from: json)
            let c = customers[id] ?? { let c = Customer(name: d.name); c.syncID = id; context.insert(c); customers[id] = c; return c }()
            c.name = d.name; c.phone = d.phone; c.address = d.address; c.notes = d.notes
            c.createdAt = d.createdAt; c.updatedAt = updatedAt
        case .worker:
            let d = try coder.decode(WorkerData.self, from: json)
            let w = workers[id] ?? { let w = Worker(name: d.name); w.syncID = id; context.insert(w); workers[id] = w; return w }()
            w.name = d.name; w.payTypeRaw = d.payType; w.hourlyRate = d.hourlyRate; w.phone = d.phone
            w.notes = d.notes; w.isActive = d.isActive; w.createdAt = d.createdAt; w.updatedAt = updatedAt
        case .dumpster:
            let d = try coder.decode(DumpsterData.self, from: json)
            let x = dumpsters[id] ?? { let x = Dumpster(number: d.number); x.syncID = id; context.insert(x); dumpsters[id] = x; return x }()
            x.number = d.number; x.label = d.label; x.isOut = d.isOut; x.customer = d.customer.flatMap { customers[$0] }
            x.location = d.location; x.droppedOffAt = d.droppedOffAt; x.dueBackAt = d.dueBackAt; x.price = d.price
            x.agreedWeightTons = d.agreedWeightTons; x.notes = d.notes; x.conditionNote = d.conditionNote; x.updatedAt = updatedAt
            return found(d.customer, x.customer)
        case .job:
            let d = try coder.decode(JobData.self, from: json)
            let j = jobs[id] ?? {
                let j = Job(customer: nil, jobType: .junkRemoval, scheduledAt: d.scheduledAt, hasTime: d.hasTime,
                            price: d.price, paymentType: .unknown, isPaid: d.isPaid, notes: d.notes)
                j.jobID = id; context.insert(j); jobs[id] = j; return j
            }()
            j.customer = d.customer.flatMap { customers[$0] }
            j.jobTypeRaw = d.jobType; j.scheduledAt = d.scheduledAt; j.hasTime = d.hasTime; j.endsAt = d.endsAt
            j.price = d.price; j.paymentTypeRaw = d.paymentType; j.isPaid = d.isPaid; j.isDone = d.isDone
            j.notes = d.notes; j.createdAt = d.createdAt; j.updatedAt = updatedAt
            return found(d.customer, j.customer)
        case .quote:
            let d = try coder.decode(QuoteData.self, from: json)
            let q = quotes[id] ?? { let q = Quote(); q.syncID = id; context.insert(q); quotes[id] = q; return q }()
            q.customer = d.customer.flatMap { customers[$0] }; q.job = d.job.flatMap { jobs[$0] }
            q.jobTypeRaw = d.jobType; q.details = d.details; q.price = d.price; q.quotedOn = d.quotedOn
            q.followUpOn = d.followUpOn; q.statusRaw = d.status; q.notes = d.notes; q.createdAt = d.createdAt
            q.updatedAt = updatedAt
            return found(d.customer, q.customer) && found(d.job, q.job)
        case .rental:
            let d = try coder.decode(RentalData.self, from: json)
            let r = rentals[id] ?? {
                let r = RentalRecord(dumpster: nil, customer: nil, location: d.location, droppedOffAt: d.droppedOffAt,
                                     pickedUpAt: d.pickedUpAt, price: d.price, agreedWeightTons: d.agreedWeightTons,
                                     actualWeightTons: d.actualWeightTons, ratePerTon: d.ratePerTon)
                r.syncID = id; context.insert(r); rentals[id] = r; return r
            }()
            r.dumpster = d.dumpster.flatMap { dumpsters[$0] }; r.customer = d.customer.flatMap { customers[$0] }
            r.location = d.location; r.droppedOffAt = d.droppedOffAt; r.pickedUpAt = d.pickedUpAt; r.price = d.price
            r.agreedWeightTons = d.agreedWeightTons; r.actualWeightTons = d.actualWeightTons; r.ratePerTon = d.ratePerTon
            r.updatedAt = updatedAt
            return found(d.dumpster, r.dumpster) && found(d.customer, r.customer)
        case .labor:
            let d = try coder.decode(LaborData.self, from: json)
            let e = labor[id] ?? {
                let e = LaborEntry(worker: nil, day: d.day, hours: d.hours, isOff: d.isOff)
                e.syncID = id; context.insert(e); labor[id] = e; return e
            }()
            e.worker = d.worker.flatMap { workers[$0] }
            e.day = d.day; e.hours = d.hours; e.isOff = d.isOff; e.note = d.note; e.updatedAt = updatedAt
            return found(d.worker, e.worker)
        case .setting:
            guard id == SyncIDs.settings else { return true }
            let d = try coder.decode(SettingData.self, from: json)
            AppSettings.applyShared(d, updatedAt: updatedAt)
        }
        return true
    }

    /// Deletes the record because another device deleted it.
    mutating func delete(_ type: SyncType, _ id: UUID, in context: ModelContext) {
        switch type {
        case .customer: if let c = customers.removeValue(forKey: id) { context.delete(c) }
        case .worker: if let w = workers.removeValue(forKey: id) { context.delete(w) }
        case .dumpster: if let d = dumpsters.removeValue(forKey: id) { context.delete(d) }
        case .job:
            if let j = jobs.removeValue(forKey: id) {
                // Its event in this device's calendar goes too, if this device wrote one.
                CalendarStore.shared.jobDeleting(j)
                context.delete(j)
            }
        case .quote: if let q = quotes.removeValue(forKey: id) { context.delete(q) }
        case .rental: if let r = rentals.removeValue(forKey: id) { context.delete(r) }
        case .labor: if let e = labor.removeValue(forKey: id) { context.delete(e) }
        // Only when removed from this device (Settings › Sync): back to
        // this device's defaults until the server's copy arrives.
        case .setting: if id == SyncIDs.settings { AppSettings.clearShared() }
        }
    }
}

enum SyncCoding {
    /// Sorted keys, so the same fields always give the same bytes (the
    /// fingerprint). Dates as milliseconds since 1970.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    private static let hex = Array("0123456789abcdef".utf8)

    /// The SHA-256 of the fields as lowercase hex. Same text as before, made
    /// without String(format:), which was slow over thousands of records
    /// (audit Oct 24, finding 50).
    static func fingerprint(_ data: Data) -> String {
        var text: [UInt8] = []
        text.reserveCapacity(64)
        for byte in SHA256.hash(data: data) {
            text.append(hex[Int(byte >> 4)])
            text.append(hex[Int(byte & 0x0F)])
        }
        return String(decoding: text, as: UTF8.self)
    }
}

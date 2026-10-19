import Foundation
import SwiftData

/// Example customers, jobs, quotes and dumpster rentals for showing the app
/// before real data exists. Loaded and removed from Settings › Debug.
///
/// Six customers, a week of jobs, six quotes and three current rentals are
/// written by hand, so the Today and Quotes screens always show the same
/// thing. About 600 more customers, two years of past jobs and the
/// dumpsters' past rentals are generated from fixed name and street lists
/// with a seeded random number generator, so they come out the same every
/// time too.
enum SampleData {
    static func load(into context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            var date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            if let hour { date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date }
            return date
        }

        let customers: [Customer] = [
            Customer(name: "Linda Johnson", phone: "508-555-0147", address: "42 Elm St, Taunton, MA", notes: "Side gate code 4412"),
            Customer(name: "Mark Pereira", phone: "508-555-0182", address: "7 Bay Rd, Raynham, MA"),
            Customer(name: "Tom & Sue Keane", phone: "774-555-0103", address: "119 Winthrop St, Taunton, MA", notes: "Garage cleanout, lots of paint cans"),
            Customer(name: "Harborview Realty", phone: "508-555-0199", address: "300 Broadway, Taunton, MA", notes: "Bill the office, ask for Dana"),
            Customer(name: "Angela Ruiz", phone: "508-555-0126", address: "15 Pine Hill Ln, Berkley, MA"),
            Customer(name: "Dave Macomber", phone: "774-555-0171", address: "88 Plymouth St, Middleborough, MA"),
        ]
        customers.forEach { context.insert($0) }

        // Jobs are inserted first and connected to their customer after, so
        // relationships are only ever set on stored records.
        let jobSpecs: [(customer: Int, job: Job)] = [
            (0, Job(customer: nil, jobType: .junkRemoval, scheduledAt: day(0, hour: 9), hasTime: true, price: 300, paymentType: .cash, isPaid: false, notes: "Basement, old couch and boxes")),
            (1, Job(customer: nil, jobType: .dumpsterDropOff, scheduledAt: day(0, hour: 11), hasTime: true, price: 450, paymentType: .card, isPaid: true)),
            (2, Job(customer: nil, jobType: .junkRemoval, scheduledAt: day(1, hour: 8), hasTime: true, price: 525, paymentType: .check, isPaid: false)),
            (3, Job(customer: nil, jobType: .dumpsterPickup, scheduledAt: day(1), hasTime: false, price: nil, paymentType: .unknown, isPaid: false, notes: "Call office before pickup")),
            (4, Job(customer: nil, jobType: .junkRemoval, scheduledAt: day(2, hour: 10), hasTime: true, price: 200, paymentType: .cash, isPaid: false)),
            (5, Job(customer: nil, jobType: .dumpsterDropOff, scheduledAt: day(3, hour: 7), hasTime: true, price: 475, paymentType: .card, isPaid: false)),
            (0, Job(customer: nil, jobType: .junkRemoval, scheduledAt: day(-3, hour: 14), hasTime: true, price: 180, paymentType: .cash, isPaid: true)),
        ]
        for spec in jobSpecs {
            context.insert(spec.job)
            spec.job.customer = customers[spec.customer]
        }
        jobSpecs[6].job.isDone = true
        // Lengths set by hand; the rest take their type's default. Linda
        // Johnson's job (9:00 to 12:00) overlaps Mark Pereira's drop-off at
        // 11:00, so the overlap warning shows on either one.
        jobSpecs[0].job.durationMinutes = 180
        jobSpecs[2].job.durationMinutes = 180
        jobSpecs[4].job.durationMinutes = 90

        // Quotes for the same six customers: two to call back (one overdue,
        // one today), two waiting, one booked as the Keanes' job tomorrow,
        // and one lost. Inserted first and connected after, like the jobs.
        let quoteSpecs: [(customer: Int, quote: Quote)] = [
            (1, Quote(jobType: .demolition, details: "Take down the old shed and haul it away", price: 1200, quotedOn: day(-6), followUpOn: day(-2))),
            (4, Quote(jobType: .junkRemoval, details: "Garage cleanout, about two loads", price: 650, quotedOn: day(-3), followUpOn: day(0))),
            (5, Quote(jobType: .junkRemoval, details: "Basement furniture and an old piano", price: 850, quotedOn: day(-2), followUpOn: day(4))),
            (3, Quote(jobType: .junkRemoval, details: "Three apartments to clear when the tenants move out", quotedOn: day(-1), notes: "Price after Alex walks through")),
            (2, Quote(jobType: .junkRemoval, details: "Garage cleanout, lots of paint cans", price: 525, quotedOn: day(-8), status: .booked)),
            (0, Quote(jobType: .junkRemoval, details: "Hot tub removal", price: 400, quotedOn: day(-20), status: .lost, notes: "Went with someone cheaper")),
        ]
        for spec in quoteSpecs {
            context.insert(spec.quote)
            spec.quote.customer = customers[spec.customer]
        }
        quoteSpecs[4].quote.job = jobSpecs[2].job

        var dumpsters: [Dumpster] = []
        for number in 1...6 {
            let dumpster = Dumpster(number: number, label: number <= 3 ? "15 yard" : "20 yard")
            context.insert(dumpster)
            dumpsters.append(dumpster)
            switch number {
            case 1:
                dumpster.isOut = true
                dumpster.customer = customers[3]
                dumpster.location = customers[3].address
                dumpster.droppedOffAt = day(-9)
                dumpster.dueBackAt = day(-2)
                dumpster.price = 450
                dumpster.agreedWeightTons = 2
            case 2:
                dumpster.isOut = true
                dumpster.customer = customers[2]
                dumpster.location = customers[2].address
                dumpster.droppedOffAt = day(-7)
                dumpster.dueBackAt = day(0)
                dumpster.price = 450
                dumpster.agreedWeightTons = 2
            case 4:
                dumpster.isOut = true
                dumpster.customer = customers[4]
                dumpster.location = customers[4].address
                dumpster.droppedOffAt = day(-2)
                dumpster.dueBackAt = day(5)
                dumpster.price = 525
                dumpster.agreedWeightTons = 3
            default:
                break
            }
        }

        addGeneratedRecords(into: context, dumpsters: dumpsters, today: today, calendar: calendar)

        try? context.save()
    }

    /// Removes everything. Used before loading samples and by "Clear all data".
    /// Deletes record by record (not as a batch), so relationships are
    /// cleaned up and nothing is left behind without its customer.
    static func clear(context: ModelContext) {
        deleteAll(Quote.self, in: context)
        deleteAll(RentalRecord.self, in: context)
        deleteAll(Job.self, in: context)
        deleteAll(Dumpster.self, in: context)
        deleteAll(Customer.self, in: context)
        try? context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        let everything = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for record in everything {
            context.delete(record)
        }
    }

    // MARK: - Generated records

    /// About 600 customers with past jobs, a few upcoming jobs, and past
    /// rentals for each dumpster. Everything is built in arrays first, then
    /// inserted, then connected; the caller saves once.
    private static func addGeneratedRecords(into context: ModelContext, dumpsters: [Dumpster], today: Date, calendar: Calendar) {
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            var date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            if let hour { date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date }
            return date
        }

        // Any fixed seed works. This one gives a good spread of upcoming days,
        // a few overweight pickups and pickups this month on every dumpster.
        let dice = Dice(seed: 31)
        var usedNames: Set<String> = []
        // The hand-written customers' numbers, so no generated one repeats them.
        var usedPhones: Set<String> = ["508-555-0147", "508-555-0182", "774-555-0103", "508-555-0199", "508-555-0126", "774-555-0171"]

        /// A job with no customer yet, on the given day relative to today.
        func makeJob(dayOffset: Int) -> Job {
            let type = SampleLists.jobTypes[dice.weightedIndex([55, 20, 15, 7, 3])]
            let hasTime = dice.chance(80)
            let price = SampleLists.price(for: type, dice)
            let payment: PaymentType = price == nil ? .unknown : dice.pick([PaymentType.cash, .check, .card])
            return Job(customer: nil,
                       jobType: type,
                       scheduledAt: day(dayOffset, hour: hasTime ? dice.int(7...15) : nil),
                       hasTime: hasTime,
                       price: price,
                       paymentType: payment)
        }

        var customers: [Customer] = []
        var jobs: [(customer: Customer, job: Job)] = []

        for _ in 0..<600 {
            // A person, or a business about one time in sixteen. A repeated
            // name is tried again a few times; two John Smiths are fine.
            var name = ""
            for _ in 0..<5 {
                name = dice.chance(6) ? SampleLists.businessName(dice) : SampleLists.personName(dice)
                if !usedNames.contains(name) { break }
            }
            usedNames.insert(name)

            // Unique 555 numbers, which reach nobody. About 2% have no phone.
            var phone = ""
            if !dice.chance(2) {
                repeat {
                    phone = (dice.chance(70) ? "508" : "774") + "-555-0" + String(format: "%03d", dice.int(0...999))
                } while usedPhones.contains(phone)
                usedPhones.insert(phone)
            }

            let address = "\(dice.int(2...480)) \(dice.pick(SampleLists.streets)), \(dice.pick(SampleLists.towns)), MA"
            let notes = dice.chance(30) ? dice.pick(SampleLists.notes) : ""
            let customer = Customer(name: name, phone: phone, address: address, notes: notes)
            customers.append(customer)

            // Past jobs over the last two years, all done and nearly all paid.
            // A pickup has no price of its own, so it counts as settled.
            let pastCount = dice.weightedIndex([15, 35, 25, 15, 10])
            for _ in 0..<pastCount {
                let job = makeJob(dayOffset: -dice.int(1...730))
                job.isDone = true
                job.isPaid = job.price == nil || dice.chance(95)
                jobs.append((customer, job))
            }

            // About one customer in 34 has a job coming up, 2 to 20 days out,
            // so the Today screen is not flooded.
            if dice.int(1...34) == 1 {
                let job = makeJob(dayOffset: dice.int(2...20))
                job.isPaid = job.price != nil && dice.chance(15)
                jobs.append((customer, job))
            }
        }

        // Past rentals for each dumpster, working backwards from its current
        // drop-off (or today), so nothing overlaps the rental it is on now.
        let rate = AppSettings.overweightRate
        var records: [(dumpster: Dumpster, customer: Customer, record: RentalRecord)] = []
        for dumpster in dumpsters {
            let price: Double = dumpster.label == "15 yard" ? 450 : 525
            var nextStart = dumpster.droppedOffAt ?? today
            for _ in 0..<dice.int(2...5) {
                let pickedUp = calendar.date(byAdding: .day, value: -dice.int(1...6), to: nextStart) ?? nextStart
                let droppedOff = calendar.date(byAdding: .day, value: -dice.int(3...10), to: pickedUp) ?? pickedUp
                guard droppedOff >= day(-120) else { break }
                let agreed: Double = dice.chance(50) ? 2 : 3
                let actual: Double = dice.chance(30) ? agreed + Double(dice.int(2...12)) / 10 : agreed
                let customer = dice.pick(customers)
                let record = RentalRecord(dumpster: nil,
                                          customer: nil,
                                          location: customer.address,
                                          droppedOffAt: droppedOff,
                                          pickedUpAt: pickedUp,
                                          price: price,
                                          agreedWeightTons: agreed,
                                          actualWeightTons: actual,
                                          ratePerTon: rate)
                records.append((dumpster, customer, record))
                nextStart = droppedOff
            }
        }

        // Insert everything, then connect it, so relationships are only ever
        // set on stored records.
        for customer in customers {
            context.insert(customer)
        }
        for entry in jobs {
            context.insert(entry.job)
            entry.job.customer = entry.customer
        }
        for entry in records {
            context.insert(entry.record)
            entry.record.customer = entry.customer
            entry.dumpster.history.append(entry.record)
        }
    }
}

// MARK: - Seeded random numbers

/// SplitMix64: the same seed always gives the same sequence, so the sample
/// data looks the same on every device and every load. Not for security.
private final class Dice {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A whole number in `range`, spread evenly.
    func int(_ range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }

    /// True `percent` times out of 100.
    func chance(_ percent: Int) -> Bool {
        int(0...99) < percent
    }

    func pick<T>(_ items: [T]) -> T {
        items[int(0...(items.count - 1))]
    }

    /// An index chosen by weight: `[55, 20, 15, 7, 3]` gives 0 fifty-five
    /// times out of a hundred, 1 twenty times, and so on.
    func weightedIndex(_ weights: [Int]) -> Int {
        var roll = int(0...(weights.reduce(0, +) - 1))
        for (index, weight) in weights.enumerated() {
            if roll < weight { return index }
            roll -= weight
        }
        return weights.count - 1
    }
}

// MARK: - Names, streets and towns

/// Fixed lists the generator draws from. Names common in south-eastern
/// Massachusetts; streets and towns around Taunton.
private enum SampleLists {
    static let firstNames = [
        "Michael", "John", "Mary", "Patricia", "James", "Robert", "Linda", "Barbara", "William", "Richard",
        "Susan", "Karen", "Joseph", "Thomas", "Nancy", "Lisa", "Kevin", "Brian", "Sean", "Patrick",
        "Maureen", "Kathleen", "Colleen", "Bridget", "Manuel", "José", "Maria", "Ana", "Carlos", "Paulo",
        "Fatima", "Luis", "Antonio", "Rosa", "Giovanni", "Angela", "Marco", "Teresa", "Miguel", "Elena",
        "Sofia", "Minh", "Linh", "Anh", "Hung", "Thanh", "Lan", "Tuan", "Mai", "Diane",
        "Donna", "Cheryl", "Steve", "Mike", "Dan", "Jen", "Ashley", "Brittany", "Tyler", "Jason",
        "Amanda", "Nicole", "Heather", "Chris", "Matt", "Ryan", "Katie", "Megan", "Justin", "Derek",
        "Peter", "Paul", "Frank", "Joe", "Tony", "Lou", "Vinnie", "Al", "Ed", "Ray",
        "Gary", "Larry", "Jim", "Bob", "Bill", "Dave", "Rick", "Doug", "Scott", "Jeff",
        "Greg", "Carol", "Sharon", "Debbie", "Judy", "Ellen", "Joan", "Betty", "Ruth", "Helen",
    ]

    static let surnames = [
        // English
        "Smith", "Johnson", "Brown", "Williams", "Taylor", "Clark", "Hall", "Lewis", "Walker", "Allen",
        "Young", "King", "Wright", "Hill", "Baker", "Carter", "Mitchell", "Turner", "Phillips", "Parker",
        "Cook", "Reed", "Bailey", "Cooper", "Morgan", "Bennett", "Macomber", "Dean", "Hathaway", "Leonard",
        "Hodges", "Wilbur", "Reynolds", "Perry", "Briggs", "Pratt",
        // Irish
        "Murphy", "Sullivan", "O'Brien", "Kelly", "Walsh", "Ryan", "McCarthy", "Doyle", "Keane", "Lynch",
        "Fitzgerald", "O'Connor", "Shea", "Flaherty", "Donovan", "Quinn", "Burke", "Nolan", "Reilly", "Brennan",
        "Connolly", "Gallagher", "Hogan", "Cronin",
        // Portuguese
        "Pereira", "Silva", "Medeiros", "Souza", "Oliveira", "Costa", "Carvalho", "Rodrigues", "Fernandes", "Almeida",
        "Pacheco", "Cabral", "Camara", "Rego", "Furtado", "Tavares", "Correia", "Moniz", "Amaral", "Botelho",
        "Raposo", "Ferreira", "Machado", "Andrade", "Pimentel", "Teixeira", "Mello", "Arruda", "Cordeiro", "Vieira",
        // Italian
        "Rossi", "Russo", "Ferrari", "Esposito", "Romano", "Colombo", "Ricci", "Marino", "Greco", "Bruno",
        "Gallo", "Conti", "DeLuca", "Giordano", "Mancini", "Rizzo", "Lombardi", "Moretti", "Barbieri", "Fontana",
        "Santoro", "Rinaldi", "Caruso", "DiNapoli", "Napolitano",
        // Spanish
        "Garcia", "Martinez", "Rodriguez", "Lopez", "Gonzalez", "Hernandez", "Perez", "Sanchez", "Ramirez", "Torres",
        "Flores", "Rivera", "Gomez", "Diaz", "Cruz", "Morales", "Reyes", "Ortiz", "Ruiz", "Mendez",
        // Vietnamese
        "Nguyen", "Tran", "Le", "Pham", "Hoang", "Huynh", "Vo", "Dang", "Bui", "Do",
        "Ho", "Ngo", "Duong", "Ly",
    ]

    static let saints = ["Anthony", "Joseph", "Mary", "Jude", "Ann", "Paul", "Michael", "Thomas"]

    /// {S} surname, {T} town, {F} first name, {X} saint.
    static let businessTemplates = [
        "{S} Realty", "{S} Realty", "{T} Realty Group", "{S} Property Management", "{T} Property Management",
        "St. {X}'s Church", "First Parish Church of {T}", "{S} Contracting", "{S} Builders", "{S} & Sons Roofing",
        "{S} Landscaping", "{S} Electric", "{S} Plumbing & Heating", "{T} Family Dental", "{T} Pizza House", "{F}'s Pizza House",
    ]

    static let streets = [
        "Elm St", "Winthrop St", "Broadway", "Bay Rd", "County St", "Somerset Ave", "Weir St", "Cohannet St",
        "Middleboro Ave", "Dean St", "Hart St", "Berkley St", "Plymouth St", "Pine Hill Ln", "Purchase St", "Myricks St",
        "Anawan St", "Old Colony Ave", "Richmond St", "Tremont St", "Washington St", "High St", "School St", "Main St",
        "Pleasant St", "Center St", "Bedford St", "Oak St", "Maple Ave", "Summer St", "Winter St", "Spring St",
        "Church St", "North Main St", "South Main St", "Highland Ave", "Williams St", "Burt St", "Glebe St", "Harvey St",
        "Caswell St", "Crane Ave", "Fremont St", "Padelford St", "Longmeadow Rd", "Orchard St", "Locust St", "Pond St",
        "Lake St", "Cedar St",
    ]

    /// Taunton appears most often, on purpose.
    static let towns = [
        "Taunton", "Taunton", "Taunton", "Taunton", "Taunton", "Taunton", "Taunton", "Taunton", "Taunton", "Taunton", "Taunton", "Taunton",
        "Raynham", "Raynham", "Raynham", "Berkley", "Berkley", "Dighton", "Dighton", "Norton", "Norton", "Middleborough", "Middleborough",
        "Lakeville", "Bridgewater", "Bridgewater", "Easton", "Rehoboth", "Freetown", "Mansfield", "Attleboro", "Attleboro", "Fall River", "Fall River",
        "Somerset", "Swansea", "Seekonk", "Carver", "Assonet",
    ]

    static let notes = [
        "Gate code 1122", "Dog in the yard, call first", "Pays by check", "Leave invoice in mailbox",
        "Second floor walk-up", "Park in the back", "Bill the office", "Text when 15 minutes out",
        "Steep driveway, back in", "Use the side door", "Cash on pickup", "Ask for the super",
        "Long driveway, dumpster goes on the left", "Call the day before", "No street parking on Tuesdays",
        "Garage key under the mat",
    ]

    /// Same order as the weights in `makeJob`.
    static let jobTypes: [JobType] = [.junkRemoval, .dumpsterDropOff, .dumpsterPickup, .demolition, .other]

    static func personName(_ dice: Dice) -> String {
        var name = dice.pick(firstNames) + " " + dice.pick(surnames)
        // Couples like "Tom & Sue Keane", now and then.
        if dice.chance(8) { name = dice.pick(firstNames) + " & " + name }
        return name
    }

    static func businessName(_ dice: Dice) -> String {
        dice.pick(businessTemplates)
            .replacingOccurrences(of: "{S}", with: dice.pick(surnames))
            .replacingOccurrences(of: "{T}", with: dice.pick(towns))
            .replacingOccurrences(of: "{F}", with: dice.pick(firstNames))
            .replacingOccurrences(of: "{X}", with: dice.pick(saints))
    }

    /// Typical prices, in round steps. A pickup has no price of its own.
    static func price(for type: JobType, _ dice: Dice) -> Double? {
        switch type {
        case .junkRemoval: return Double(dice.int(6...36) * 25)      // 150–900
        case .dumpsterDropOff: return Double(dice.int(16...26) * 25) // 400–650
        case .dumpsterPickup: return nil
        case .dumpsterSwap: return Double(dice.int(16...26) * 25)    // 400–650
        case .estimate: return nil
        case .demolition: return Double(dice.int(16...70) * 50)      // 800–3,500
        case .other: return Double(dice.int(4...20) * 25)            // 100–500
        }
    }
}

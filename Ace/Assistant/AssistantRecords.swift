import Foundation
import SwiftData

/// The short references in the records sent with a note (C4, J12, Q2, D3),
/// turned back into the records they stand for. Made fresh for every note.
struct RecordRefs {
    var customers: [String: Customer] = [:]
    var jobs: [String: Job] = [:]
    var quotes: [String: Quote] = [:]
    var dumpsters: [String: Dumpster] = [:]

    /// " c4 " → "C4".
    static func key(_ ref: String) -> String {
        ref.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    func customer(_ ref: String) -> Customer? { customers[Self.key(ref)] }
    func job(_ ref: String) -> Job? { jobs[Self.key(ref)] }
    func quote(_ ref: String) -> Quote? { quotes[Self.key(ref)] }
    func dumpster(_ ref: String) -> Dumpster? { dumpsters[Self.key(ref)] }

    /// The job a reference points at, only while it is still on the books
    /// (`live` is the current list), so a job deleted by an earlier step is
    /// never touched again.
    func job(_ ref: String, among live: [Job]) -> Job? {
        guard let found = job(ref) else { return nil }
        let isLive = live.contains(where: { $0 === found })
        return isLive ? found : nil
    }

    /// The quote a reference points at, only while it is still stored
    /// (`live` is the current list of quotes).
    func quote(_ ref: String, among live: [Quote]) -> Quote? {
        guard let found = quote(ref) else { return nil }
        let isLive = live.contains(where: { $0 === found })
        return isLive ? found : nil
    }

    /// The customer a reference means: a customer, a job's customer, a
    /// quote's customer, or the customer a dumpster is out with.
    func customerMeant(by ref: String, jobs live: [Job], quotes liveQuotes: [Quote]) -> Customer? {
        if let found = customer(ref) { return found }
        if let found = job(ref, among: live) { return found.customer }
        if let found = quote(ref, among: liveQuotes) { return found.customer }
        if let found = dumpster(ref) { return found.customer }
        return nil
    }
}

/// Builds the "Records" part of the message to Claude, in the format of
/// docs/assistant-actions.md: the dumpsters, the jobs from a week ago to two
/// weeks ahead, the open quotes, the customers on them plus up to six the
/// note seems to name (each of those with their last 8 jobs), and a line of
/// totals.
enum AssistantRecords {
    static func build(note: String, customers: [Customer], jobs: [Job], dumpsters: [Dumpster], quotes: [Quote], now: Date) -> (text: String, refs: RecordRefs) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let lastDay = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay

        let windowJobs = jobs
            .filter { $0.scheduledAt >= windowStart && $0.scheduledAt < windowEnd }
            .sorted { $0.scheduledAt < $1.scheduledAt }
        let mentioned = mentionedCustomers(in: note, customers: customers)
        let sortedDumpsters = dumpsters.sorted { $0.number < $1.number }
        // Every open quote, oldest first. Booked and lost ones are not sent.
        let openQuotes = QuoteList.shown(quotes, status: .open)

        // References first, so every line can use them.
        var builder = Builder()
        for customer in mentioned { builder.add(customer) }
        for job in windowJobs { if let customer = job.customer { builder.add(customer) } }
        for dumpster in sortedDumpsters { if let customer = dumpster.customer { builder.add(customer) } }
        for quote in openQuotes { if let customer = quote.customer { builder.add(customer) } }
        for job in windowJobs { builder.add(job) }
        for quote in openQuotes { builder.add(quote) }
        var history: [ObjectIdentifier: [Job]] = [:]
        for customer in mentioned {
            let recent = Array(customer.jobs.sorted { $0.scheduledAt > $1.scheduledAt }.prefix(8))
            for job in recent { builder.add(job) }
            history[ObjectIdentifier(customer)] = recent
        }
        for dumpster in sortedDumpsters {
            builder.refs.dumpsters["D\(dumpster.number)"] = dumpster
        }

        var lines: [String] = []
        lines.append("Dumpsters:")
        if sortedDumpsters.isEmpty { lines.append("- none") }
        for dumpster in sortedDumpsters {
            lines.append(builder.dumpsterLine(dumpster, now: now))
        }

        lines.append("Jobs from \(Format.day(windowStart)) to \(Format.day(lastDay)):")
        if windowJobs.isEmpty { lines.append("- none") }
        for job in windowJobs {
            lines.append("- " + builder.jobLine(job, withCustomer: true))
        }

        lines.append("Open quotes:")
        if openQuotes.isEmpty { lines.append("- none") }
        for quote in openQuotes {
            lines.append("- " + builder.quoteLine(quote, today: today))
        }

        lines.append("Customers:")
        if builder.customerOrder.isEmpty { lines.append("- none") }
        for customer in builder.customerOrder {
            lines.append("- " + builder.customerLine(customer))
            for job in history[ObjectIdentifier(customer)] ?? [] {
                lines.append("  - " + builder.jobLine(job, withCustomer: false))
            }
        }

        lines.append(totalsLine(jobs: jobs, today: today, calendar: calendar))
        return (lines.joined(separator: "\n"), builder.refs)
    }

    // MARK: Lines

    /// Hands out references and writes the lines that use them.
    private struct Builder {
        var refs = RecordRefs()
        var customerOrder: [Customer] = []
        private var customerRefs: [ObjectIdentifier: String] = [:]
        private var jobRefs: [ObjectIdentifier: String] = [:]
        private var quoteRefs: [ObjectIdentifier: String] = [:]

        mutating func add(_ customer: Customer) {
            let key = ObjectIdentifier(customer)
            guard customerRefs[key] == nil else { return }
            let ref = "C\(customerOrder.count + 1)"
            customerRefs[key] = ref
            customerOrder.append(customer)
            refs.customers[ref] = customer
        }

        mutating func add(_ job: Job) {
            let key = ObjectIdentifier(job)
            guard jobRefs[key] == nil else { return }
            let ref = "J\(jobRefs.count + 1)"
            jobRefs[key] = ref
            refs.jobs[ref] = job
        }

        mutating func add(_ quote: Quote) {
            let key = ObjectIdentifier(quote)
            guard quoteRefs[key] == nil else { return }
            let ref = "Q\(quoteRefs.count + 1)"
            quoteRefs[key] = ref
            refs.quotes[ref] = quote
        }

        /// "C1 Linda Johnson", or just the name if it has no reference.
        func named(_ customer: Customer) -> String {
            guard let ref = customerRefs[ObjectIdentifier(customer)] else { return customer.name }
            return ref + " " + customer.name
        }

        /// "- D1 Dumpster 1 (15 yard): out with C3 Harborview Realty at 300 Broadway, Taunton, MA
        /// since Sat, Oct 10; due back Sat, Oct 17 (overdue); $450; 2 tons agreed"
        func dumpsterLine(_ dumpster: Dumpster, now: Date) -> String {
            var line = "- D\(dumpster.number) Dumpster \(dumpster.number)"
            if !dumpster.label.isEmpty { line += " (\(dumpster.label))" }
            line += ": "
            let status = dumpster.status(on: now)
            if status == .inYard {
                line += "in the yard"
            } else {
                var head = "out"
                if let customer = dumpster.customer { head += " with " + named(customer) }
                if !dumpster.location.isEmpty { head += " at " + Format.oneLine(dumpster.location) }
                if let droppedOffAt = dumpster.droppedOffAt { head += " since " + Format.day(droppedOffAt) }
                var parts = [head]
                if let dueBackAt = dumpster.dueBackAt {
                    var due = "due back " + Format.day(dueBackAt)
                    if status == .overdue { due += " (overdue)" }
                    if status == .dueToday { due += " (due today)" }
                    parts.append(due)
                }
                if let price = dumpster.price { parts.append(Money.text(price)) }
                if let agreed = dumpster.agreedWeightTons { parts.append(Tons.text(agreed) + " agreed") }
                line += parts.joined(separator: "; ")
            }
            let note = Format.oneLine(dumpster.conditionNote)
            if !note.isEmpty { line += ". Note: " + note }
            return line
        }

        /// "J1 Mon, Oct 19 9:00 to 11:00 AM · C1 Linda Johnson · Junk removal · $300 cash · not paid · not done · 42 Elm St, Taunton, MA"
        /// Under a customer, the customer and address are left out. A job
        /// with a time shows its start, and its end when it has one.
        func jobLine(_ job: Job, withCustomer: Bool) -> String {
            var when = Format.day(job.scheduledAt)
            if job.hasTime { when += " " + job.timeRangeText }
            var parts = [(jobRefs[ObjectIdentifier(job)] ?? "J?") + " " + when]
            if withCustomer {
                parts.append(job.customer.map { named($0) } ?? "no customer")
            }
            parts.append(job.jobType.rawValue)
            if let price = job.price {
                let payment = job.paymentType == .unknown ? "" : " " + job.paymentType.rawValue.lowercased()
                parts.append(Money.text(price) + payment)
            } else {
                parts.append("no price")
            }
            parts.append(job.isPaid ? "paid" : "not paid")
            parts.append(job.isDone ? "done" : "not done")
            if withCustomer, let address = job.customer?.address, !address.isEmpty {
                parts.append(Format.oneLine(address))
            }
            let notes = Format.oneLine(job.notes)
            if !notes.isEmpty { parts.append(notes) }
            return parts.joined(separator: " · ")
        }

        /// "Q1 C2 Dave Macomber · 88 Plymouth St, Middleborough, MA · Junk removal ·
        /// Garage cleanout, about two loads · $450 · quoted Tue, Oct 13 · follow up Sat, Oct 17 (overdue)"
        func quoteLine(_ quote: Quote, today: Date) -> String {
            let ref = quoteRefs[ObjectIdentifier(quote)] ?? "Q?"
            var who = "no customer"
            if let customer = quote.customer { who = named(customer) }
            var parts = [ref + " " + who]
            if let address = quote.customer?.address, !address.isEmpty {
                parts.append(Format.oneLine(address))
            }
            parts.append(quote.jobType.rawValue)
            let details = Format.oneLine(quote.details)
            if !details.isEmpty { parts.append(details) }
            parts.append(quote.price.map { Money.text($0) } ?? "no price")
            parts.append("quoted " + Format.day(quote.quotedOn))
            if let followUpOn = quote.followUpOn {
                var followUp = "follow up " + Format.day(followUpOn)
                let day = Calendar.current.startOfDay(for: followUpOn)
                if day < today { followUp += " (overdue)" }
                if day == today { followUp += " (today)" }
                parts.append(followUp)
            }
            return parts.joined(separator: " · ")
        }

        /// "C1 Linda Johnson · 508-555-0147 · 42 Elm St, Taunton, MA · Side gate code 4412 ·
        /// 4 jobs, $1,180, owes $0, last job Mon, Oct 19"
        func customerLine(_ customer: Customer) -> String {
            var parts = [named(customer)]
            if !customer.phone.isEmpty { parts.append(customer.phone) }
            if !customer.address.isEmpty { parts.append(Format.oneLine(customer.address)) }
            let notes = Format.oneLine(customer.notes)
            if !notes.isEmpty { parts.append(notes) }
            var figures = Plural.text(customer.jobs.count, "job")
            figures += ", " + Money.text(customer.totalBilled)
            figures += ", owes " + Money.text(customer.amountOwed)
            if let last = customer.lastJobDate { figures += ", last job " + Format.day(last) }
            parts.append(figures)
            return parts.joined(separator: " · ")
        }
    }

    /// "Totals: owed $19,550 from 31 jobs; done this week $2,140 from 6 jobs; booked today $750 from 2 jobs."
    private static func totalsLine(jobs: [Job], today: Date, calendar: Calendar) -> String {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        // Monday of this week: weekday 1 is Sunday, 2 is Monday.
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today

        var owed = 0.0, owedCount = 0
        var doneWeek = 0.0, doneWeekCount = 0
        var bookedToday = 0.0, bookedTodayCount = 0
        for job in jobs {
            if job.isDone && !job.isPaid, let price = job.price {
                owed += price
                owedCount += 1
            }
            if job.isDone && job.scheduledAt >= monday && job.scheduledAt < tomorrow {
                doneWeek += job.price ?? 0
                doneWeekCount += 1
            }
            if job.scheduledAt >= today && job.scheduledAt < tomorrow {
                bookedToday += job.price ?? 0
                bookedTodayCount += 1
            }
        }
        return "Totals: owed \(Money.text(owed)) from \(Plural.text(owedCount, "job"))"
            + "; done this week \(Money.text(doneWeek)) from \(Plural.text(doneWeekCount, "job"))"
            + "; booked today \(Money.text(bookedToday)) from \(Plural.text(bookedTodayCount, "job"))."
    }

    // MARK: Who the note names

    /// Words that are never taken as a name.
    private static let commonWords: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "she", "her", "his", "him", "they", "them", "their",
        "has", "have", "had", "was", "are", "were", "will", "can", "not", "but", "out", "off", "all", "just",
        "job", "jobs", "done", "paid", "cash", "check", "card", "dumpster", "dumpsters", "ton", "tons",
        "today", "tomorrow", "yesterday", "morning", "afternoon", "tonight", "week", "next", "last",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]

    /// Up to `limit` customers the note seems to name, strongest match first:
    /// a phone number of 7 or more digits (4 points), the full name or a house
    /// number and street (3), the last name (1). Another word of a name, four
    /// letters or more, counts a little (0.5), and only when three customers or
    /// fewer share it, so a common first name does not fill the list. Ties keep
    /// the order of `customers`.
    static func mentionedCustomers(in note: String, customers: [Customer], limit: Int = 6) -> [Customer] {
        var score: [ObjectIdentifier: Double] = [:]
        func add(_ customer: Customer, _ points: Double) {
            score[ObjectIdentifier(customer), default: 0] += points
        }

        for run in digitRuns(in: note) where run.count >= 7 {
            for customer in customers {
                let digits = customer.phoneDigits
                if digits.count >= 7 && (digits.hasSuffix(run) || run.hasSuffix(digits)) { add(customer, 4) }
            }
        }

        let noteWords = SpokenName(note).words
        let noteLine = " " + noteWords.joined(separator: " ") + " "
        let keyWords = Set(noteWords.filter { word in
            word.filter(\.isLetter).count >= 3 && !commonWords.contains(word)
        })

        var byOtherWord: [String: [Customer]] = [:]
        var byStreet: [String: [Customer]] = [:]
        for customer in customers {
            let parts = SpokenName(customer.name).words
            if let last = parts.last {
                if parts.count >= 2 && noteLine.contains(" " + parts.joined(separator: " ") + " ") { add(customer, 3) }
                if keyWords.contains(last) { add(customer, 1) }
                for word in Set(parts.dropLast()) where word.count >= 4 && keyWords.contains(word) {
                    byOtherWord[word, default: []].append(customer)
                }
            }
            let address = SpokenAddress(customer.address)
            if let number = address.houseNumber, let street = address.streetWord {
                byStreet[number + " " + street, default: []].append(customer)
            }
        }
        for list in byOtherWord.values where list.count <= 3 {
            for customer in list { add(customer, 0.5) }
        }

        let addressWords = SpokenAddress.words(of: note)
        for (position, word) in addressWords.enumerated() where position + 1 < addressWords.count {
            let next = addressWords[position + 1]
            guard word.allSatisfy(\.isNumber), !next.allSatisfy(\.isNumber) else { continue }
            for customer in byStreet[word + " " + next] ?? [] { add(customer, 3) }
        }

        let ranked: [(customer: Customer, points: Double, position: Int)] = customers.enumerated().compactMap { position, customer in
            guard let points = score[ObjectIdentifier(customer)] else { return nil }
            return (customer, points, position)
        }
        return ranked
            .sorted { $0.points != $1.points ? $0.points > $1.points : $0.position < $1.position }
            .prefix(limit)
            .map { $0.customer }
    }

    /// Runs of digits, allowing the spaces, dashes, dots and brackets people
    /// put inside phone numbers: "508 555-0199" → "5085550199".
    static func digitRuns(in text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in text {
            if character.isASCII && character.isNumber {
                current.append(character)
            } else if " -.()".contains(character) {
                continue
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    // MARK: Text

    /// Fixed US formats, so the records read the same on every device.
    private enum Format {
        private static let dayFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "EEE, MMM d"
            return formatter
        }()

        /// "Mon, Oct 19"
        static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

        /// Line breaks turned into "; " so one record stays on one line.
        static func oneLine(_ text: String) -> String {
            text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "; ")
        }
    }
}

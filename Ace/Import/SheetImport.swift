import Foundation
import SwiftData

/// Ashley's job sheet turned into customers and jobs (build step 7). The
/// layout is in docs/ashley-spreadsheet.md: one row per job, with Date,
/// Customer Name, # and Street Name, City State & Zip, Price, Form of
/// Payment, Check # and Not Mailing Address. Columns are found by their
/// headings, so their order does not matter. Plain code, no Claude.
struct SheetImport {
    /// One job as read from a row, before anything is saved.
    struct Row {
        var line: Int
        var date: Date
        var name: String
        var address: String
        var price: Double?
        var payment: PaymentType
        /// The price cell was red: not paid yet.
        var unpaid: Bool
        var notes: String
        /// "???" or a street with no number.
        var missingHouseNumber: Bool
    }

    var tabName = ""
    var rows: [Row] = []
    /// Rows with nothing to import (blank, or headings repeated).
    var skipped = 0
    /// A heading the import looks for that was not in the sheet.
    var missingColumns: [String] = []

    // What the preview says.
    var customerCount: Int { Set(rows.map(\.customerKey)).count }
    var unpaidRows: [Row] { rows.filter(\.unpaid) }
    var noAddress: Int { rows.filter { $0.address.isEmpty }.count }
    var noName: Int { rows.filter { $0.name.isEmpty }.count }
    var noHouseNumber: Int { rows.filter(\.missingHouseNumber).count }
    var firstDate: Date? { rows.map(\.date).min() }
    var lastDate: Date? { rows.map(\.date).max() }

    // MARK: Reading

    /// Picks the tab that looks like the job list and reads it.
    /// `fallbackYear` is used for dates written without one ("1/5").
    static func read(_ tabs: [SheetTab], fallbackYear: Int) -> SheetImport? {
        let candidates = tabs.compactMap { tab -> SheetImport? in
            guard let header = headerRow(tab.rows) else { return nil }
            return read(tab, header: header, fallbackYear: year(in: tab.name) ?? fallbackYear)
        }
        return candidates.max { $0.rows.count < $1.rows.count }
    }

    private enum Column: String, CaseIterable {
        case date = "Date"
        case name = "Customer Name"
        case street = "# and Street Name"
        case city = "City, State & Zip"
        case price = "Price"
        case payment = "Form of Payment"
        case check = "Check #"
        case notMailing = "Not Mailing Address"

        func matches(_ heading: String) -> Bool {
            let h = heading.lowercased()
            switch self {
            case .date: return h == "date" || h.hasPrefix("date")
            case .name: return h.contains("customer") || h == "name"
            case .street: return h.contains("street") || h.hasPrefix("#") || h.contains("address") && !h.contains("mailing")
            case .city: return h.contains("city") || h.contains("zip") || h.contains("town")
            case .price: return h.contains("price") || h.contains("amount")
            case .payment: return h.contains("payment") || h.contains("paid by") || h == "form"
            case .check: return h.contains("check")
            case .notMailing: return h.contains("mailing")
            }
        }
    }

    /// The first row in the top ten that has a customer and a price heading.
    private static func headerRow(_ rows: [[Int: SheetCell]]) -> (index: Int, columns: [Column: Int])? {
        for (index, row) in rows.prefix(10).enumerated() {
            var columns: [Column: Int] = [:]
            for (col, cell) in row.sorted(by: { $0.key < $1.key }) {
                // Check # before Customer (both could match "c").
                if let match = Column.allCases.first(where: { columns[$0] == nil && $0.matches(cell.text) }) {
                    columns[match] = col
                }
            }
            if columns[.name] != nil, columns[.price] != nil || columns[.date] != nil {
                return (index, columns)
            }
        }
        return nil
    }

    private static func read(_ tab: SheetTab, header: (index: Int, columns: [Column: Int]), fallbackYear: Int) -> SheetImport {
        var result = SheetImport(tabName: tab.name)
        result.missingColumns = Column.allCases.filter { header.columns[$0] == nil }.map(\.rawValue)
        let calendar = Calendar.current
        var year = fallbackYear
        var lastDate: Date?

        for (offset, row) in tab.rows.enumerated() where offset > header.index {
            func cell(_ c: Column) -> SheetCell? { header.columns[c].flatMap { row[$0] } }
            func text(_ c: Column) -> String { cell(c)?.text ?? "" }

            let name = clean(text(.name))
            let street = clean(text(.street))
            let city = clean(text(.city))
            let priceCell = cell(.price)
            let price = priceCell.flatMap { $0.number ?? Parse.money($0.text) }
            // A repeated heading, a total line or an empty row.
            if name.isEmpty && street.isEmpty && city.isEmpty && price == nil {
                if !row.isEmpty { result.skipped += 1 }
                continue
            }
            if Column.name.matches(name) || name.lowercased().hasPrefix("total") {
                result.skipped += 1
                continue
            }

            // The date, carrying the year down: the sheet writes "1/5" after
            // the first "1/5/2026". A row with no date takes the one above.
            var date = lastDate
            if let dateCell = cell(.date) {
                if let parsed = parseDate(dateCell, year: year, calendar: calendar) {
                    date = parsed
                    year = calendar.component(.year, from: parsed)
                }
            }
            guard let day = date ?? calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { continue }
            lastDate = day

            // "??? Lexington Ave": the street without the unknown number.
            var streetLine = street.replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces)
            let hadUnknownNumber = street.contains("?")
            if streetLine.hasPrefix(",") { streetLine.removeFirst() }
            let address = [streetLine, city].filter { !$0.isEmpty }.joined(separator: ", ")
            let isPOBox = streetLine.lowercased().replacingOccurrences(of: ".", with: "").hasPrefix("po box")
            let missingNumber = !streetLine.isEmpty && !isPOBox
                && (hadUnknownNumber || SpokenAddress(streetLine).houseNumber == nil)

            var notes: [String] = []
            if let check = cell(.check), !check.text.isEmpty {
                let number = check.number.map { String(Int($0)) } ?? check.text
                notes.append("Check #\(number)")
            }
            if !text(.notMailing).isEmpty { notes.append("Not the mailing address.") }
            if hadUnknownNumber { notes.append("House number not known.") }

            result.rows.append(Row(
                line: offset + 1,
                date: day,
                name: name,
                address: address,
                price: price,
                payment: payment(text(.payment)),
                unpaid: priceCell?.isRed ?? false,
                notes: notes.joined(separator: " "),
                missingHouseNumber: missingNumber
            ))
        }
        return result
    }

    private static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func payment(_ text: String) -> PaymentType {
        JobDraft.paymentType(from: text) ?? .unknown
    }

    /// A four-digit year in a tab or file name ("2026 ACE Books").
    static func year(in text: String) -> Int? {
        let digits = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return digits.first { (2000...2100).contains($0) }
    }

    private static func parseDate(_ cell: SheetCell, year: Int, calendar: Calendar) -> Date? {
        if let number = cell.number, cell.isDate || (30_000...80_000).contains(number) {
            // Spreadsheet day numbers count from December 30, 1899.
            let base = DateComponents(calendar: calendar, year: 1899, month: 12, day: 30).date ?? Date()
            return calendar.date(byAdding: .day, value: Int(number), to: base).map { calendar.startOfDay(for: $0) }
        }
        let parts = cell.text.split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." }).compactMap { Int($0) }
        guard parts.count >= 2, (1...12).contains(parts[0]), (1...31).contains(parts[1]) else { return nil }
        var y = parts.count >= 3 ? parts[2] : year
        if y < 100 { y += 2000 }
        return calendar.date(from: DateComponents(year: y, month: parts[0], day: parts[1]))
    }

    // MARK: Saving

    /// What the import did, for the confirmation.
    struct Outcome {
        var newCustomers = 0
        var existingCustomers = 0
        var jobs = 0
        var alreadyThere = 0
    }

    /// Saves the rows. A customer already in Ace (same name and address) is
    /// used again; a job already in Ace before this import (same customer,
    /// day and price) is skipped, so importing the same sheet twice adds
    /// nothing. Two matching rows in the sheet itself both come in: Ashley
    /// wrote both down. Imported jobs
    /// are not written to the shared calendar: hundreds of past events would
    /// flood it.
    @MainActor
    func save(into context: ModelContext, today: Date = Dates.startOfToday()) -> Outcome {
        var outcome = Outcome()
        let existing = (try? context.fetch(FetchDescriptor<Customer>())) ?? []
        var byKey: [String: Customer] = [:]
        for customer in existing {
            let key = Row.key(name: customer.name, address: customer.address)
            if byKey[key] == nil { byKey[key] = customer }
        }
        let keysBefore = Set(byKey.keys)
        func jobKey(_ customerKey: String, _ day: Date, _ price: Double?) -> String {
            "\(customerKey)|\(Calendar.current.startOfDay(for: day).timeIntervalSince1970)|\(price ?? -1)"
        }
        var jobsBefore = Set<String>()
        for (key, customer) in byKey {
            for job in customer.jobs { jobsBefore.insert(jobKey(key, job.scheduledAt, job.price)) }
        }
        var reused = Set<String>()
        for row in rows {
            let key = row.customerKey
            let customer: Customer
            if let found = byKey[key] {
                customer = found
                if keysBefore.contains(key) { reused.insert(key) }
            } else {
                customer = Customer(name: row.name.isEmpty ? "No name" : row.name, address: row.address)
                context.insert(customer)
                byKey[key] = customer
                outcome.newCustomers += 1
            }
            if jobsBefore.contains(jobKey(key, row.date, row.price)) {
                outcome.alreadyThere += 1
                continue
            }
            let job = Job(customer: nil, jobType: .junkRemoval, scheduledAt: row.date, hasTime: false,
                          price: row.price, paymentType: row.payment, isPaid: !row.unpaid, notes: row.notes)
            job.isDone = row.date <= today
            context.insert(job)
            job.customer = customer
            outcome.jobs += 1
        }
        outcome.existingCustomers = reused.count
        try? context.save()
        return outcome
    }
}

extension SheetImport.Row {
    /// Name and address, lowercased and without punctuation: the same person
    /// on two rows.
    var customerKey: String { Self.key(name: name, address: address) }

    static func key(name: String, address: String) -> String {
        func squash(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        return squash(name) + "|" + squash(address)
    }
}

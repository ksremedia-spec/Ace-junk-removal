import Foundation

/// What Claude returns for one spoken note. `kind` says what the note was:
/// a new job to schedule, an update to a job that already exists, a dumpster
/// pickup, a dumpster drop-off, a question about the records, or something
/// the app cannot do yet ("other", answered in words). Empty strings mean
/// "the note did not say".
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

    struct Row: Identifiable {
        var field: String   // schema field name, e.g. customerName
        var label: String   // what Ashley sees
        var value: String

        var id: String { field }
    }

    /// Rows for display, in the order Ashley would read them.
    var rows: [Row] {
        [
            Row(field: "kind", label: "Kind", value: kind),
            Row(field: "answer", label: "Answer", value: answer),
            Row(field: "customerName", label: "Name", value: customerName),
            Row(field: "phone", label: "Phone", value: phone),
            Row(field: "address", label: "Address", value: address),
            Row(field: "jobType", label: "Job type", value: jobType),
            Row(field: "date", label: "Date", value: date),
            Row(field: "time", label: "Time", value: time),
            Row(field: "price", label: "Price", value: price.isEmpty ? "" : "$" + price),
            Row(field: "paymentType", label: "Payment", value: paymentType),
            Row(field: "paid", label: "Paid", value: paid),
            Row(field: "done", label: "Done", value: done),
            Row(field: "newDate", label: "New date", value: newDate),
            Row(field: "newTime", label: "New time", value: newTime),
            Row(field: "dumpsterNumber", label: "Dumpster", value: dumpsterNumber),
            Row(field: "actualTons", label: "Actual weight", value: actualTons.isEmpty ? "" : actualTons + " tons"),
            Row(field: "agreedTons", label: "Agreed weight", value: agreedTons.isEmpty ? "" : agreedTons + " tons"),
            Row(field: "dueBack", label: "Due back", value: dueBack),
            Row(field: "notes", label: "Notes", value: notes),
        ]
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

    // MARK: Schema

    private static let issueFields = [
        "customerName", "phone", "address", "jobType", "date", "time", "price", "paymentType", "paid", "notes",
        "done", "dumpsterNumber", "actualTons", "agreedTons", "dueBack", "newDate", "newTime",
    ]

    /// The JSON Schema sent to Claude. Every field is required and objects do
    /// not allow extra keys, which is what structured outputs need.
    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "kind": ["type": "string", "enum": Kind.allCases.map(\.rawValue), "description": "job: new work to schedule. update: something about a job that already exists. pickup: a dumpster was picked up. dropoff: a dumpster was dropped off. question: asks about existing records. other: something none of those can do; explain in answer."],
            "answer": ["type": "string", "description": "For a question: the answer in one or two plain sentences, from the records provided. For other: what was understood and the nearest thing the app can do. Otherwise empty."],
            "customerName": ["type": "string", "description": "Customer's name as spoken, or empty."],
            "phone": ["type": "string", "description": "Phone number as digits with dashes, like 508-555-0123, or empty."],
            "address": ["type": "string", "description": "Street address including house number, town and state, or empty."],
            "jobType": ["type": "string", "enum": ["Junk removal", "Demolition", "Dumpster drop-off", "Dumpster pickup", "Other", ""], "description": "Worked out from the work described (see the rules). Empty only when the note gives no clue what the work is."],
            "date": ["type": "string", "description": "Job date as YYYY-MM-DD, or empty. For an update, the day of the job being talked about."],
            "time": ["type": "string", "description": "Job time as HH:MM in 24-hour time, or empty."],
            "price": ["type": "string", "description": "Agreed price in dollars as digits only, like 300, or empty."],
            "paymentType": ["type": "string", "enum": ["cash", "check", "card", "unknown"]],
            "paid": ["type": "string", "enum": ["paid", "unpaid", "unknown"]],
            "notes": ["type": "string", "description": "Anything else useful from the note, in one or two short sentences, or empty."],
            "done": ["type": "string", "enum": ["yes", "no", ""], "description": "For an update: yes when the job is finished, no when it is not, empty when the note did not say."],
            "newDate": ["type": "string", "description": "For an update that moves the job: the new date as YYYY-MM-DD, or empty."],
            "newTime": ["type": "string", "description": "For an update that moves the job: the new time as HH:MM in 24-hour time, or empty."],
            "dumpsterNumber": ["type": "string", "enum": ["", "1", "2", "3", "4", "5", "6"], "description": "The dumpster's number when one was said, or empty."],
            "actualTons": ["type": "string", "description": "For a pickup: the weight in tons as digits, like 2.8, or empty."],
            "agreedTons": ["type": "string", "description": "For a drop-off: the weight included in the price, in tons as digits, or empty."],
            "dueBack": ["type": "string", "description": "For a drop-off: the day the dumpster is due back as YYYY-MM-DD, or empty."],
            "issues": [
                "type": "array",
                "description": "Problems to confirm before saving. Empty for questions and for other.",
                "items": [
                    "type": "object",
                    "properties": [
                        "field": ["type": "string", "enum": issueFields],
                        "question": ["type": "string", "description": "A short plain-English yes/no question, e.g. 'No price was given. Save without one?'"],
                    ],
                    "required": ["field", "question"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": [
            "kind", "answer", "customerName", "phone", "address", "jobType", "date", "time", "price", "paymentType", "paid", "notes",
            "done", "newDate", "newTime", "dumpsterNumber", "actualTons", "agreedTons", "dueBack", "issues",
        ],
        "additionalProperties": false,
    ]

    /// Plain-language instructions. Today's date is filled in at call time so
    /// "Friday" and "tomorrow" resolve correctly.
    static func systemPrompt(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        let today = formatter.string(from: now)
        let zone = TimeZone.current.identifier

        return """
        You help the office of Ace Junk Removal, a junk removal and dumpster rental company in Massachusetts. \
        The input is a spoken note, transcribed by speech recognition, so names, street names and numbers may be misheard. \
        Fix a misheard word only when the correction is certain; otherwise keep what was said and raise an issue.

        Today is \(today) (time zone \(zone)).

        Decide the kind of note:
        - "job": new work to schedule (a customer, an address, a date, a price). Fill the job fields.
        - "update": something about a job that already exists: it is done, it was paid (and how), it moved to another day or time, the price changed, or there is a note to add. \
        Fill only what identifies the job (customer name, phone or address as said; date is the day of that job if said, and today's date for words like "just finished", "this morning" or "on site") \
        and only the changes: done, paid and paymentType, price, newDate, newTime, notes. Leave the other job fields empty. Do not raise issues for fields an update does not need.
        - "pickup": a dumpster was picked up, collected or weighed. Fill dumpsterNumber if a number was said, otherwise the customer name or address it was at, and actualTons if a weight was said.
        - "dropoff": a dumpster was dropped off, delivered or placed. Fill dumpsterNumber if said, the customer name and address, dueBack if said, price and agreedTons if said.
        - "question": the note asks about existing records, e.g. "which dumpsters are due back Friday" or "what do we have on Tuesday". \
        Answer from the records provided with the note, in one or two plain sentences, and leave the other fields empty. If the records do not contain the answer, say so.
        - "other": the note asks for something none of the kinds above can do (for example cancelling a job, changing a customer's details, sending a receipt). \
        Put in "answer", in one or two plain sentences, what was understood and the nearest thing the app can do, and leave the other fields empty.

        Rules for jobs:
        - Fill only what the note says. Use an empty string for anything not mentioned. Never invent a name, number, price or address.
        - Work out the job type from the work described; nobody says "junk removal" out loud. \
        Junk removal: clearing, emptying or cleaning out a garage, basement, attic, shed, house, estate or office, or hauling away furniture, appliances, debris or a hot tub. \
        Demolition: tearing down or taking out a shed, deck, pool, fence, wall, kitchen, bathroom or flooring, or any mention of "demo". \
        Dumpster drop-off: delivering, dropping off, renting or needing a dumpster (a dumpster rental is a drop-off). \
        Dumpster pickup: picking up, swapping or hauling off a dumpster that is already out. \
        Other: any other kind of work. Leave the job type empty, with an issue, only when nothing in the note says what the work is. \
        If a note covers more than one kind of work, pick the main one and put the rest in notes.
        - Resolve relative dates against today: "tomorrow", "Friday" (the next Friday, or today if today is Friday), "next week". Output YYYY-MM-DD.
        - Times in 24-hour HH:MM. "Morning" with no time stays empty and gets an issue.
        - Price: digits only, no dollar sign. "Three hundred" is 300.
        - Payment type: cash, check, card, or unknown. Paid: paid, unpaid, or unknown. "PD cash 300" means paid, cash, 300.
        - For a new job, raise an issue when: no date, no price, no phone number, the kind of work cannot be told from the note, the date is in the past, the address has no house number, the name or address sounds unclear, or two different values were said for one field. \
        Each issue names the field and asks one short yes/no question Ashley can answer. \
        For an update, raise an issue only when it is unclear which job is meant or what changed. \
        For a pickup, raise an issue when no weight was said. \
        For a drop-off, raise an issue when the dumpster number, the customer or the address is missing.
        - Plain business language. No exclamation points.
        """
    }
}

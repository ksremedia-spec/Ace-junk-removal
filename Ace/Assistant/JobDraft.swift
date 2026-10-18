import Foundation

/// The fixed list of job fields Claude fills in from a transcript.
/// Empty strings mean "the note did not say". Nothing here is saved yet;
/// in step 1 it is only displayed on the Debug screen.
struct JobDraft: Codable, Equatable {
    struct Issue: Codable, Equatable, Identifiable {
        var field: String
        var question: String

        var id: String { field + question }
    }

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
    var issues: [Issue]

    struct Row: Identifiable {
        var field: String   // schema field name, e.g. customerName
        var label: String   // what Ashley sees
        var value: String

        var id: String { field }
    }

    /// Rows for display, in the order Ashley would read them.
    var rows: [Row] {
        [
            Row(field: "customerName", label: "Name", value: customerName),
            Row(field: "phone", label: "Phone", value: phone),
            Row(field: "address", label: "Address", value: address),
            Row(field: "jobType", label: "Job type", value: jobType),
            Row(field: "date", label: "Date", value: date),
            Row(field: "time", label: "Time", value: time),
            Row(field: "price", label: "Price", value: price.isEmpty ? "" : "$" + price),
            Row(field: "paymentType", label: "Payment", value: paymentType),
            Row(field: "paid", label: "Paid", value: paid),
            Row(field: "notes", label: "Notes", value: notes),
        ]
    }

    /// The JSON Schema sent to Claude. Every field is required and objects do
    /// not allow extra keys, which is what structured outputs need.
    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "customerName": ["type": "string", "description": "Customer's full name as spoken, or empty."],
            "phone": ["type": "string", "description": "Phone number as digits with dashes, like 508-555-0123, or empty."],
            "address": ["type": "string", "description": "Street address including house number, town and state, or empty."],
            "jobType": ["type": "string", "description": "Short job type, e.g. junk removal, dumpster drop-off, dumpster pickup, or empty."],
            "date": ["type": "string", "description": "Job date as YYYY-MM-DD, or empty."],
            "time": ["type": "string", "description": "Job time as HH:MM in 24-hour time, or empty."],
            "price": ["type": "string", "description": "Agreed price in dollars as digits only, like 300, or empty."],
            "paymentType": ["type": "string", "enum": ["cash", "check", "card", "unknown"]],
            "paid": ["type": "string", "enum": ["paid", "unpaid", "unknown"]],
            "notes": ["type": "string", "description": "Anything else useful from the note, in one or two short sentences, or empty."],
            "issues": [
                "type": "array",
                "description": "Problems Ashley should confirm before saving.",
                "items": [
                    "type": "object",
                    "properties": [
                        "field": ["type": "string", "description": "One of: customerName, phone, address, jobType, date, time, price, paymentType, paid, notes."],
                        "question": ["type": "string", "description": "A short plain-English yes/no question, e.g. 'No price was given. Save without one?'"],
                    ],
                    "required": ["field", "question"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["customerName", "phone", "address", "jobType", "date", "time", "price", "paymentType", "paid", "notes", "issues"],
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
        You fill in a job form for Ace Junk Removal, a junk removal and dumpster rental company in Massachusetts. \
        The input is a spoken note from the office, transcribed by speech recognition, so names, street names and numbers may be misheard. \
        Fix a misheard word only when the correction is certain; otherwise keep what was said and raise an issue.

        Today is \(today) (time zone \(zone)).

        Rules:
        - Fill only what the note says. Use an empty string for anything not mentioned. Never invent a name, number, price or address.
        - Resolve relative dates against today: "tomorrow", "Friday" (the next Friday, or today if today is Friday), "next week". Output YYYY-MM-DD.
        - Times in 24-hour HH:MM. "Morning" with no time stays empty and gets an issue.
        - Price: digits only, no dollar sign. "Three hundred" is 300.
        - Payment type: cash, check, card, or unknown. Paid: paid, unpaid, or unknown. "PD cash 300" means paid, cash, 300.
        - Raise an issue when: no price, no phone number, the date is in the past, the address has no house number, the name or address sounds unclear, or two different values were said for one field. \
        Each issue names the field and asks one short yes/no question Ashley can answer.
        - Plain business language. No exclamation points.
        """
    }
}

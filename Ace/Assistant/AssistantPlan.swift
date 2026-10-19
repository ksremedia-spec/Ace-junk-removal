import Foundation

/// What Claude returns for one spoken note: a reply (the answer to a
/// question, or what was understood when nothing can be done), the actions
/// to confirm one at a time, and the questions to ask before saving. The
/// shape, the schema and the instructions are the contract in
/// docs/assistant-actions.md, shared with the browser demo.
struct AssistantPlan: Codable {
    var reply: String
    var actions: [AssistantAction]
    var issues: [PlanIssue]

    /// Gives every action its position in the list, which is what the
    /// issues point at and what the screens use to tell actions apart.
    mutating func numberActions() {
        for position in actions.indices {
            actions[position].index = position
        }
    }
}

/// One thing to do. Every property is text; an empty string means "not said".
struct AssistantAction: Codable, Identifiable {
    var type = ""
    var ref = ""
    var customerName = ""
    var phone = ""
    var address = ""
    var jobType = ""
    var date = ""
    var time = ""
    var endTime = ""
    var price = ""
    var paymentType = ""
    var paid = ""
    var done = ""
    var newDate = ""
    var newTime = ""
    var dumpsterNumber = ""
    var otherDumpsterNumber = ""
    var actualTons = ""
    var agreedTons = ""
    var dueBack = ""
    var followUp = ""
    var quoteStatus = ""
    var note = ""
    var newName = ""
    var newPhone = ""
    var newAddress = ""
    var contact = ""
    var message = ""

    /// Position in the plan, set after decoding. Not part of the JSON.
    var index = 0

    var id: Int { index }

    enum CodingKeys: String, CodingKey {
        case type, ref, customerName, phone, address, jobType, date, time, endTime, price, paymentType, paid, done
        case newDate, newTime, dumpsterNumber, otherDumpsterNumber, actualTons, agreedTons, dueBack
        case followUp, quoteStatus, note
        case newName, newPhone, newAddress, contact, message
    }

    enum ActionType: String, CaseIterable {
        case newJob = "new_job"
        case updateJob = "update_job"
        case cancelJob = "cancel_job"
        case newCustomer = "new_customer"
        case updateCustomer = "update_customer"
        case contactCustomer = "contact_customer"
        case dumpsterDropoff = "dumpster_dropoff"
        case dumpsterPickup = "dumpster_pickup"
        case dumpsterSwap = "dumpster_swap"
        case updateRental = "update_rental"
        case dumpsterNote = "dumpster_note"
        case newQuote = "new_quote"
        case updateQuote = "update_quote"

        /// The screen title.
        var title: String {
            switch self {
            case .newJob: return "New Job"
            case .updateJob: return "Update Job"
            case .cancelJob: return "Cancel Job"
            case .newCustomer: return "New Customer"
            case .updateCustomer: return "Update Customer"
            case .contactCustomer: return "Contact Customer"
            case .dumpsterDropoff: return "Dumpster Drop-off"
            case .dumpsterPickup: return "Dumpster Pickup"
            case .dumpsterSwap: return "Dumpster Swap"
            case .updateRental: return "Update Rental"
            case .dumpsterNote: return "Dumpster Note"
            case .newQuote: return "New Quote"
            case .updateQuote: return "Update Quote"
            }
        }

        /// The fields this kind's screen shows with its own warning note, in
        /// the form `AssistantFlags.key` gives. A question about any other
        /// field is shown above the screen instead. Nil when the screen asks
        /// every question itself (the new-job screen asks them on Save).
        var fieldsOnScreen: Set<String>? {
            switch self {
            case .newJob: return nil
            case .updateJob: return ["done", "paid", "jobtype", "paymenttype", "price", "newdate", "newtime", "endtime", "note"]
            case .cancelJob: return ["ref"]
            case .newCustomer: return ["customername", "phone", "address", "note"]
            case .updateCustomer: return ["ref", "newname", "newphone", "newaddress", "note"]
            case .contactCustomer: return ["ref", "phone", "address"]
            case .dumpsterDropoff: return ["customername", "address", "dumpsternumber", "phone", "dueback", "price", "agreedtons"]
            case .dumpsterPickup: return ["actualtons"]
            case .dumpsterSwap: return ["dumpsternumber", "ref", "actualtons", "otherdumpsternumber", "dueback", "price", "agreedtons", "note"]
            case .updateRental: return ["dumpsternumber", "ref", "dueback", "price", "agreedtons", "newaddress", "note"]
            case .dumpsterNote: return ["dumpsternumber", "ref", "note"]
            case .newQuote: return ["customername", "phone", "address", "jobtype", "price", "note", "followup"]
            case .updateQuote: return ["ref", "price", "followup", "note", "date", "time", "endtime", "paymenttype", "paid"]
            }
        }
    }

    var kind: ActionType? { ActionType(rawValue: type) }

    struct Field: Identifiable {
        let name: String
        let value: String

        var id: String { name }
    }

    /// The properties that were filled in, in schema order, for the debug screen.
    var filledFields: [Field] {
        let all: [(String, String)] = [
            ("ref", ref), ("customerName", customerName), ("phone", phone), ("address", address),
            ("jobType", jobType), ("date", date), ("time", time), ("endTime", endTime), ("price", price),
            ("paymentType", paymentType), ("paid", paid), ("done", done), ("newDate", newDate),
            ("newTime", newTime), ("dumpsterNumber", dumpsterNumber), ("otherDumpsterNumber", otherDumpsterNumber),
            ("actualTons", actualTons), ("agreedTons", agreedTons), ("dueBack", dueBack),
            ("followUp", followUp), ("quoteStatus", quoteStatus), ("note", note),
            ("newName", newName), ("newPhone", newPhone), ("newAddress", newAddress),
            ("contact", contact), ("message", message),
        ]
        return all.filter { !$0.1.isEmpty }.map { Field(name: $0.0, value: $0.1) }
    }
}

extension AssistantAction {
    /// Reads leniently: a missing property counts as "not said" instead of
    /// failing the whole answer.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? ""
        }
        type = text(.type)
        ref = text(.ref)
        customerName = text(.customerName)
        phone = text(.phone)
        address = text(.address)
        jobType = text(.jobType)
        date = text(.date)
        time = text(.time)
        endTime = text(.endTime)
        price = text(.price)
        paymentType = text(.paymentType)
        paid = text(.paid)
        done = text(.done)
        newDate = text(.newDate)
        newTime = text(.newTime)
        dumpsterNumber = text(.dumpsterNumber)
        otherDumpsterNumber = text(.otherDumpsterNumber)
        actualTons = text(.actualTons)
        agreedTons = text(.agreedTons)
        dueBack = text(.dueBack)
        followUp = text(.followUp)
        quoteStatus = text(.quoteStatus)
        note = text(.note)
        newName = text(.newName)
        newPhone = text(.newPhone)
        newAddress = text(.newAddress)
        contact = text(.contact)
        message = text(.message)
        normalize()
    }

    /// Structured output can return an enum value with different capitals
    /// ("Junk Removal", "Yes"). Brings each one back to the spelling the
    /// app compares against.
    mutating func normalize() {
        type = type.trimmingCharacters(in: .whitespaces).lowercased()
        paymentType = paymentType.trimmingCharacters(in: .whitespaces).lowercased()
        paid = paid.trimmingCharacters(in: .whitespaces).lowercased()
        done = done.trimmingCharacters(in: .whitespaces).lowercased()
        contact = contact.trimmingCharacters(in: .whitespaces).lowercased()
        quoteStatus = quoteStatus.trimmingCharacters(in: .whitespaces).lowercased()
        dumpsterNumber = dumpsterNumber.trimmingCharacters(in: .whitespaces)
        otherDumpsterNumber = otherDumpsterNumber.trimmingCharacters(in: .whitespaces)
        let spokenType = jobType.trimmingCharacters(in: .whitespaces)
        if let match = JobType.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(spokenType) == .orderedSame }) {
            jobType = match.rawValue
        }
    }

    /// The action in the older form the job and dumpster screens still take.
    /// Only the issues tied to this action come along; "note" becomes the
    /// draft's "notes" so the notes field is flagged.
    func jobDraft(issues: [PlanIssue]) -> JobDraft {
        let draftKind: JobDraft.Kind
        switch kind {
        case .updateJob: draftKind = .update
        case .dumpsterPickup: draftKind = .pickup
        case .dumpsterDropoff: draftKind = .dropoff
        default: draftKind = .job
        }
        let paidText: String
        switch paid.lowercased() {
        case "yes": paidText = "paid"
        case "no": paidText = "unpaid"
        default: paidText = "unknown"
        }
        let draftIssues = issues
            .filter { $0.action == index }
            .map { JobDraft.Issue(field: $0.field.lowercased() == "note" ? "notes" : $0.field, question: $0.question) }
        return JobDraft(
            kind: draftKind.rawValue,
            answer: "",
            customerName: customerName,
            phone: phone,
            address: address,
            jobType: jobType,
            date: date,
            time: time,
            endTime: endTime,
            price: price,
            paymentType: paymentType.isEmpty ? "unknown" : paymentType,
            paid: paidText,
            notes: note,
            done: done,
            newDate: newDate,
            newTime: newTime,
            dumpsterNumber: dumpsterNumber,
            actualTons: actualTons,
            agreedTons: agreedTons,
            dueBack: dueBack,
            issues: draftIssues
        )
    }
}

/// A question to ask before saving, tied to an action by its position.
struct PlanIssue: Codable, Identifiable {
    var action: Int
    var field: String
    var question: String

    var id: String { "\(action) \(field) \(question)" }
}

// MARK: - What is sent to Claude

extension AssistantPlan {
    private static func string(_ description: String = "") -> [String: Any] {
        var property: [String: Any] = ["type": "string"]
        if !description.isEmpty { property["description"] = description }
        return property
    }

    private static func oneOf(_ values: [String], _ description: String = "") -> [String: Any] {
        var property = string(description)
        property["enum"] = values
        return property
    }

    private static func integer(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    private static let actionProperties: [String: Any] = [
        "type": oneOf(["new_job", "update_job", "cancel_job", "new_customer", "update_customer", "contact_customer", "dumpster_dropoff", "dumpster_pickup", "dumpster_swap", "update_rental", "dumpster_note", "new_quote", "update_quote"]),
        "ref": string("Reference of the record this action is about, from the records list (C4, J12, Q2, D3), or empty."),
        "customerName": string(),
        "phone": string("Digits with dashes, like 508-555-0123, or empty."),
        "address": string("Street address with house number, town and state, or empty."),
        "jobType": oneOf(["Junk removal", "Demolition", "Dumpster drop-off", "Dumpster pickup", "Dumpster swap", "Estimate", "Other", ""]),
        "date": string("YYYY-MM-DD: the day of a new job, or the day of the job meant, or empty."),
        "time": string("HH:MM, 24-hour, or empty."),
        "endTime": string("HH:MM, 24-hour: when the job ends, or empty."),
        "price": string("Dollars as digits, like 300, or empty."),
        "paymentType": oneOf(["cash", "check", "card", ""]),
        "paid": oneOf(["yes", "no", ""]),
        "done": oneOf(["yes", "no", ""]),
        "newDate": string("YYYY-MM-DD when a job moves, or empty."),
        "newTime": string("HH:MM when a job moves, or empty."),
        "dumpsterNumber": oneOf(["", "1", "2", "3", "4", "5", "6"]),
        "otherDumpsterNumber": oneOf(["", "1", "2", "3", "4", "5", "6"], "For a swap: the dumpster left in place."),
        "actualTons": string("Weight at pickup in tons as digits, like 2.8, or empty."),
        "agreedTons": string("Agreed weight in tons as digits, or empty."),
        "dueBack": string("YYYY-MM-DD, or empty."),
        "followUp": string("YYYY-MM-DD: the day to call back about a quote, or empty."),
        "quoteStatus": oneOf(["approved", "declined", ""], "For update_quote: approved when the customer said yes, declined when they said no."),
        "note": string("Anything to write down, in one short sentence, or empty."),
        "newName": string(),
        "newPhone": string(),
        "newAddress": string(),
        "contact": oneOf(["call", "text", "directions", ""]),
        "message": string("For a text: the message to send."),
    ]

    private static let actionRequired: [String] = [
        "type", "ref", "customerName", "phone", "address", "jobType", "date", "time", "endTime", "price", "paymentType", "paid", "done", "newDate", "newTime", "dumpsterNumber", "otherDumpsterNumber", "actualTons", "agreedTons", "dueBack", "followUp", "quoteStatus", "note", "newName", "newPhone", "newAddress", "contact", "message",
    ]

    private static let issueProperties: [String: Any] = [
        "action": integer("Position of the action in the list, 0 for the first."),
        "field": oneOf(["customerName", "phone", "address", "jobType", "date", "time", "endTime", "price", "paymentType", "paid", "done", "newDate", "newTime", "dumpsterNumber", "otherDumpsterNumber", "actualTons", "agreedTons", "dueBack", "followUp", "note", "newName", "newPhone", "newAddress", "ref"]),
        "question": string("One short plain yes/no question."),
    ]

    private static let issueRequired: [String] = ["action", "field", "question"]

    private static let replyDescription = "The answer to a question, or what was understood when nothing can be done, in one or two plain sentences. Empty when the actions cover the note."

    /// The JSON Schema for structured output, exactly as in
    /// docs/assistant-actions.md: every property required, no extra keys.
    static let jsonSchema: [String: Any] = {
        let action: [String: Any] = [
            "type": "object",
            "properties": actionProperties,
            "required": actionRequired,
            "additionalProperties": false,
        ]
        let issue: [String: Any] = [
            "type": "object",
            "properties": issueProperties,
            "required": issueRequired,
            "additionalProperties": false,
        ]
        let properties: [String: Any] = [
            "reply": string(replyDescription),
            "actions": ["type": "array", "items": action] as [String: Any],
            "issues": ["type": "array", "items": issue] as [String: Any],
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": ["reply", "actions", "issues"],
            "additionalProperties": false,
        ]
    }()

    /// The instructions, word for word from docs/assistant-actions.md, with
    /// today's date, the time zone and the time filled in.
    static func systemPrompt(now: Date = Date()) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US")
        dayFormatter.dateFormat = "EEEE, MMMM d, yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US")
        timeFormatter.dateFormat = "h:mm a"
        let today = dayFormatter.string(from: now)
        let zone = TimeZone.current.identifier
        let time = timeFormatter.string(from: now)

        return """
        You help the office and the crew of Ace Junk Removal, a junk removal, demolition and dumpster rental company in Massachusetts. The input is a spoken note written down by speech recognition, so names, street names and numbers may be misheard. Fix a misheard word only when the correction is certain.

        Today is \(today) (\(zone)). The time is \(time).

        The person speaking is Ashley in the office (booking work, answering the phone, keeping the books) or Alex and the crew in the field (finishing jobs, collecting payment, dropping off and picking up dumpsters). Work out what they want done and return it as a list of actions. One note can hold several actions: "Johnson's done, paid cash, and she wants a dumpster next Friday" is an update to her job and a new job.

        The records sent with the note list dumpsters, jobs, open quotes and customers, each with a reference like D3, J12, Q2 or C4. When an action is about a record in the list, put its reference in "ref". When the note names someone or something not in the list, leave "ref" empty and fill in the name, phone, address or dumpster number as said; the app looks it up.

        Actions:
        - new_job: book new work. Fill customerName, phone and address as said, jobType, date, time, endTime (when it will end, when an end or a length was said), price, paymentType, paid and note. A dumpster delivery, pickup or swap booked for later is a new_job with that jobType. An on-site quote visit is jobType "Estimate". A call-back or reminder is jobType "Other" on that day, with the reason in note.
        - update_job: change a job that exists. done "yes" when it is finished, "no" when it is not finished after all. paid "yes" when it was paid, with paymentType and, if an amount was said, price; paid "no" when payment did not happen or a check bounced. newDate and newTime when it moved. endTime when its end changed or a new end was said. price when the price changed. jobType when the kind of work changed. note for anything to write down: a no-show, a dump fee, an extra item, a promise to pay later. Being paid on site means the work is done. Fill only what changes.
        - cancel_job: the job is off. The app asks before removing it.
        - new_customer: add a customer without booking work: customerName, phone, address, note.
        - update_customer: a customer's details changed or there is something to remember about them: newName, newPhone, newAddress, note (gate codes, dogs, how they pay, who to ask for).
        - contact_customer: call, text or get directions. contact is "call", "text" or "directions"; for a text, message is the text to send. ref can be the customer or the job.
        - dumpster_dropoff: a dumpster has just been dropped off or delivered: dumpsterNumber, customerName, address, dueBack, price, agreedTons, note.
        - dumpster_pickup: a dumpster has just been picked up, collected or weighed: dumpsterNumber (or the customer or address it was at) and actualTons.
        - dumpster_swap: a full dumpster was taken away and an empty one left in its place: dumpsterNumber is the one taken away, actualTons its weight, otherDumpsterNumber the one left, and dueBack, price and agreedTons for the new rental when said.
        - update_rental: change a dumpster that is out: dueBack (kept longer or picked up sooner), price, agreedTons, newAddress (moved on the property or to another place), note.
        - dumpster_note: something about a dumpster itself, such as damage or that it should not go out: dumpsterNumber and note.
        - new_quote: a price was given that the customer has not accepted yet: customerName, phone and address as said, jobType, price, note (what was quoted, in a few words) and followUp (the day to call them back, when said).
        - update_quote: an open quote changed. quoteStatus "approved" when the customer said yes or approved it, with date, time and endTime for the work when said; "declined" when they said no or went elsewhere. price when it changed. followUp when a call-back day was said. note for anything to write down. A call-back about an open quote is an update_quote with followUp, not a new_job. When a price is given and accepted in the same note and no open quote matches, book a new_job instead.

        When the note asks a question, for example "which dumpsters are due back Friday", "what do we have tomorrow", "how much does Pereira owe", "what's Johnson's address", "is a dumpster free Friday" or "which quotes need a call back", answer it in "reply" from the records in one or two plain sentences, and return actions only if something should also be done. If the records do not hold the answer, say so.

        When the note asks for something none of the actions can do, such as sending an invoice, changing a setting, undoing a change or deleting a customer, say in "reply" what was understood and the nearest thing that can be done, and return no actions.

        Leave "reply" empty when the actions cover the note.

        Rules for fields:
        - Fill only what the note says. Use an empty string for anything not said. Never invent a name, number, price or address.
        - Dates as YYYY-MM-DD, worked out from today: "tomorrow", "Friday" (the next Friday, or today if today is Friday), "next week". Times as HH:MM in 24-hour time. "This morning", "just now", "just finished" and "on site" mean today.
        - Money as digits: "three hundred" is 300. Weights in tons as digits: "two point eight" is 2.8. An end time is worked out from what was said: "till noon" is 12:00; "about three hours" from a 9:00 start is 12:00. With no end or length said, leave endTime empty; never guess one.
        - jobType from the work described; nobody says "junk removal" out loud. Junk removal: clearing, emptying or cleaning out a garage, basement, attic, shed, house, estate or office, or hauling away furniture, appliances, debris or a hot tub. Demolition: tearing down or taking out a shed, deck, pool, fence, wall, kitchen, bathroom or flooring, or any mention of "demo". Dumpster drop-off, Dumpster pickup and Dumpster swap: booking those for a later day. Estimate: going to look and give a price. Other: anything else. Leave it empty only when nothing says what the work is.
        - paymentType is cash, check or card. "PD cash 300" means paid, cash, 300.

        Issues: list what the person should confirm before saving, each tied to an action by its position in the list (0 for the first), naming the field and asking one short yes/no question. For a new job: no date, no price, no phone number for someone not in the records, unclear kind of work, a date in the past, an address with no house number, a name or address that sounds misheard, two values said for one field. For a new quote: no price, no phone number for someone not in the records, an address with no house number. For any other action: only when it is unclear which record is meant or what should change, and for a pickup or swap when no weight was said.

        Plain business language. No exclamation points.
        """
    }
}

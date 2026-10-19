import SwiftData
import SwiftUI

// The Assistant's quote screens: a new quote, and a change to an open quote
// (approved books the job, declined marks it lost, otherwise a new price,
// call-back day or note). The contract is docs/assistant-actions.md.

// MARK: - New quote

/// "Quote for 66 Johnson Street, garage cleanout, 800." The New Quote form,
/// filled in. The customer is found the way the new-job form finds one: the
/// one the note pointed at, the same phone number, or the same full name.
/// A shared last name or an address alone is not enough. With no match,
/// saving adds a customer with the name, phone and address said.
struct NewQuoteView: View {
    @Environment(\.modelContext) private var context

    let customers: [Customer]
    /// The customer the note's reference pointed at, if any. The quote goes
    /// to them unless the name is changed to someone else.
    let knownCustomer: Customer?
    private let flags: AssistantFlags
    var onFinish: (String) -> Void
    var onStartOver: () -> Void

    @State private var name: String
    @State private var phone: String
    @State private var address: String
    @State private var form: QuoteFormData
    @State private var saved = false
    @State private var flagged = 0

    init(action: AssistantAction, issues: [PlanIssue], customers: [Customer], knownCustomer: Customer?,
         onFinish: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.customers = customers
        self.knownCustomer = knownCustomer
        self.onFinish = onFinish
        self.onStartOver = onStartOver

        var phoneText = action.phone
        var addressText = action.address
        if let knownCustomer {
            if phoneText.isEmpty { phoneText = knownCustomer.phone }
            if addressText.isEmpty { addressText = knownCustomer.address }
        }
        _name = State(initialValue: knownCustomer?.name ?? action.customerName.trimmingCharacters(in: .whitespaces))
        _phone = State(initialValue: PhoneFormat.formatted(phoneText))
        _address = State(initialValue: addressText)

        // Quoted today; the call-back day is the one said, else three days
        // out (the form's default), shown and not flagged.
        let saidType = JobType.allCases.first { $0.rawValue.caseInsensitiveCompare(action.jobType) == .orderedSame }
        var quote = QuoteFormData()
        quote.jobType = saidType ?? .junkRemoval
        quote.details = action.note.trimmingCharacters(in: .whitespacesAndNewlines)
        quote.priceText = action.price
        quote.hasFollowUp = true
        if let day = JobDraft.day(from: action.followUp) {
            quote.followUpOn = day
        }
        _form = State(initialValue: quote)

        var flags = AssistantFlags(issues: issues)
        if saidType == nil {
            flags.add("jobType", "No kind of work was said.")
        }
        self.flags = flags
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var phoneDigits: String { phone.filter(\.isNumber) }

    /// Same rules as the new-job form: the referenced customer while the
    /// name still matches, then the same phone number, then the same full
    /// name. Nil means saving adds a new customer.
    private var matchingCustomer: Customer? {
        if let knownCustomer,
           SpokenName(name).text == SpokenName(knownCustomer.name).text {
            return knownCustomer
        }
        if phoneDigits.count >= 7, let byPhone = customers.first(where: { $0.phoneDigits == phoneDigits }) {
            return byPhone
        }
        let lowered = trimmedName.lowercased()
        guard !lowered.isEmpty else { return nil }
        return customers.first { $0.name.lowercased() == lowered }
    }

    private var nameNote: String? {
        trimmedName.isEmpty && matchingCustomer == nil ? (flags["customerName"] ?? "No name was said.") : flags["customerName"]
    }

    /// Clears as soon as a price is typed in, unless Claude asked about it.
    private var priceNote: String? {
        Parse.money(form.priceText) == nil ? (flags["price"] ?? "No price was said.") : flags["price"]
    }

    var body: some View {
        Form {
            Section {
                FlaggedRow(nameNote) {
                    TextField("Name", text: $name)
                }
                FlaggedRow(flags["phone"]) {
                    TextField("Phone", text: $phone)
                        .phoneKeyboard()
                }
                FlaggedRow(flags["address"]) {
                    TextField("Address", text: $address, axis: .vertical)
                }
                if let match = matchingCustomer {
                    Text("Matches existing customer \(match.name).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if !trimmedName.isEmpty {
                    Text("Saving adds \(trimmedName) as a new customer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Customer")
            }

            Section("Quote") {
                FlaggedRow(flags["jobType"]) {
                    Picker("Type", selection: $form.jobType) {
                        ForEach(JobType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }
                FlaggedRow(flags["note"]) {
                    TextField("What", text: $form.details, prompt: Text("What was quoted, e.g. garage cleanout"), axis: .vertical)
                }
                FlaggedRow(priceNote) {
                    TextField("Price", text: $form.priceText, prompt: Text("Price in dollars"))
                        .decimalKeyboard()
                }
                DatePicker("Quoted", selection: $form.quotedOn, displayedComponents: .date)
                Toggle("Follow up", isOn: $form.hasFollowUp)
                if form.hasFollowUp {
                    FlaggedRow(flags["followUp"]) {
                        DatePicker("Follow up on", selection: $form.followUpOn, displayedComponents: .date)
                    }
                }
            }

            Section("Notes") {
                TextField("Notes", text: $form.notes, axis: .vertical)
            }

            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(trimmedName.isEmpty && matchingCustomer == nil)
            }
        }
        .onAppear {
            if !flags.isEmpty || nameNote != nil || priceNote != nil { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private func save() {
        let customer: Customer
        if let match = matchingCustomer {
            customer = match
            if customer.phone.isEmpty, !phoneDigits.isEmpty { customer.phone = PhoneFormat.formatted(phone) }
            if customer.address.isEmpty { customer.address = address.trimmingCharacters(in: .whitespacesAndNewlines) }
            customer.updatedAt = Date()
        } else {
            customer = Customer(
                name: trimmedName,
                phone: PhoneFormat.formatted(phone),
                address: address.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            context.insert(customer)
        }
        // Inserted first and connected after, so the link is made on a
        // stored record.
        let quote = Quote()
        context.insert(quote)
        var data = form
        data.customer = customer
        data.apply(to: quote)
        try? context.save()
        // A phone or address filled in above goes onto their jobs' events.
        CalendarStore.shared.customerSaved(customer)
        saved.toggle()
        onFinish("Quote saved.")
    }
}

// MARK: - Change an open quote

/// "Silva approved, do it Friday morning", "Silva went with someone else",
/// "Silva's quote is 1,100 now". Finds the quote, then shows the screen for
/// what was said: Book Job, Mark Lost, or the changes with Save.
struct UpdateQuoteView: View {
    let action: AssistantAction
    let issues: [PlanIssue]
    /// The open quotes the note could mean (or the one its reference names).
    let candidates: [Quote]
    /// Every job, to warn about overlaps on Book Job.
    let jobs: [Job]
    let subject: String
    var onFinish: (String) -> Void
    var onSkip: () -> Void
    var onStartOver: () -> Void

    @State private var picked: Quote?

    private var quote: Quote? {
        if let picked { return picked }
        return candidates.count == 1 ? candidates.first : nil
    }

    var body: some View {
        if let quote {
            screen(for: quote)
        } else if candidates.isEmpty {
            NothingFoundView(message: "No open quote found for \(subject).", onSkip: onSkip, onStartOver: onStartOver)
        } else {
            WhichQuoteList(quotes: candidates, onPick: { picked = $0 }, onStartOver: onStartOver)
        }
    }

    /// quoteStatus arrives lowercased (see `AssistantAction.normalize`).
    @ViewBuilder
    private func screen(for quote: Quote) -> some View {
        switch action.quoteStatus {
        case "approved":
            BookQuoteForm(
                quote: quote,
                action: action,
                issues: issues,
                jobs: jobs,
                onFinish: { text in finished(quote, text) },
                onStartOver: onStartOver
            )
        case "declined":
            LoseQuoteForm(
                quote: quote,
                action: action,
                issues: issues,
                onFinish: { text in finished(quote, text) },
                onStartOver: onStartOver
            )
        default:
            UpdateQuoteForm(
                quote: quote,
                action: action,
                issues: issues,
                onFinish: { text in finished(quote, text) },
                onStartOver: onStartOver
            )
        }
    }

    /// Keeps showing this quote while the next step loads, even though it
    /// may no longer be open.
    private func finished(_ quote: Quote, _ text: String) {
        picked = quote
        onFinish(text)
    }
}

/// "Which quote?" when several open quotes fit the note.
struct WhichQuoteList: View {
    let quotes: [Quote]
    var onPick: (Quote) -> Void
    var onStartOver: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(quotes) { quote in
                    Button {
                        onPick(quote)
                    } label: {
                        QuoteRow(quote: quote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Which quote?")
            }
            Section {
                Button("Start over") { onStartOver() }
            }
        }
    }
}

/// The quote as it stands, read-only. `note` flags the customer row when it
/// is unclear which quote was meant.
struct QuoteDetailsSection: View {
    let quote: Quote
    var note: String? = nil

    var body: some View {
        Section("Quote") {
            FlaggedRow(note) {
                LabeledContent("Customer", value: quote.customer?.name ?? "No customer")
            }
            if let address = quote.customer?.address, !address.isEmpty {
                LabeledContent("Address") {
                    Text(address)
                        .multilineTextAlignment(.trailing)
                }
            }
            LabeledContent("Type", value: quote.jobType.rawValue)
            if !quote.details.isEmpty {
                LabeledContent("What") {
                    Text(quote.details)
                        .multilineTextAlignment(.trailing)
                }
            }
            LabeledContent("Price", value: quote.price.map { Money.text($0) } ?? "No price")
            LabeledContent("Quoted", value: Dates.shortDay(quote.quotedOn))
            if let followUpOn = quote.followUpOn {
                LabeledContent("Follow up", value: Dates.shortDay(followUpOn))
            }
            if quote.status != .open {
                LabeledContent("Status", value: quote.status.rawValue)
            }
        }
    }
}

// MARK: Approved: book the job

/// The quote at the top and the job's date, time, end time, price and
/// payment below. Saving adds the job (the quote's customer and type, what was
/// quoted as its notes) and marks the quote booked and linked to it. An
/// overlap with another timed job is shown and asked about first.
private struct BookQuoteForm: View {
    @Environment(\.modelContext) private var context

    let quote: Quote
    let jobs: [Job]
    private let flags: AssistantFlags
    var onFinish: (String) -> Void
    var onStartOver: () -> Void

    @State private var date: Date
    @State private var hasTime: Bool
    /// "Set an end time" and the Ends picker (only its clock time is used,
    /// on the job's day). On when an end time was said.
    @State private var hasEnd: Bool
    @State private var endTime: Date
    @State private var priceText: String
    @State private var paymentType: PaymentType
    @State private var isPaid: Bool
    @State private var notes: String
    @State private var saved = false
    @State private var flagged = 0
    @State private var askingOverlap = false
    @State private var overlapQuestion = ""

    init(quote: Quote, action: AssistantAction, issues: [PlanIssue], jobs: [Job],
         onFinish: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.quote = quote
        self.jobs = jobs
        self.onFinish = onFinish
        self.onStartOver = onStartOver

        // The day said, else today (flagged). A time only when one was said.
        let calendar = Calendar.current
        let saidDay = JobDraft.day(from: action.date)
        var when = saidDay ?? Dates.startOfToday()
        var timeSaid = false
        if let clock = JobDraft.clock(from: action.time) {
            when = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: when) ?? when
            timeSaid = true
        }
        _date = State(initialValue: when)
        _hasTime = State(initialValue: timeSaid)
        let saidEnd = timeSaid ? JobTimes.end(fromClock: action.endTime, on: when) : nil
        _hasEnd = State(initialValue: saidEnd != nil)
        _endTime = State(initialValue: saidEnd ?? JobTimes.suggestedEnd(after: when))
        // The quote's price unless a new one was said.
        _priceText = State(initialValue: action.price.isEmpty ? Parse.moneyText(quote.price) : action.price)
        _paymentType = State(initialValue: JobDraft.paymentType(from: action.paymentType) ?? .unknown)
        _isPaid = State(initialValue: action.paid == "yes")
        // What was quoted, then anything said with the approval.
        let said = action.note.trimmingCharacters(in: .whitespacesAndNewlines)
        _notes = State(initialValue: [quote.details, said].filter { !$0.isEmpty }.joined(separator: "\n"))

        var flags = AssistantFlags(issues: issues)
        if saidDay == nil {
            flags.add("date", "No day was said for the work.")
        }
        self.flags = flags
    }

    /// The end time to save, on the job's day; nil without one.
    private var endDate: Date? {
        hasTime ? JobTimes.end(start: date, hasEnd: hasEnd, endTime: endTime) : nil
    }

    /// False while an end time is set that is not after the start.
    private var endIsValid: Bool {
        !hasTime || JobTimes.endIsValid(start: date, hasEnd: hasEnd, endTime: endTime)
    }

    /// Unfinished timed jobs that day the new job would clash with.
    private var overlapping: [Job] {
        guard hasTime else { return [] }
        return JobOverlap.find(start: date, end: endDate, excluding: nil, in: jobs)
    }

    var body: some View {
        Form {
            QuoteDetailsSection(quote: quote, note: flags["ref"])

            Section("Job") {
                FlaggedRow(flags["date"]) {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Toggle("Set a time", isOn: $hasTime)
                if hasTime {
                    FlaggedRow(flags["time"]) {
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                    }
                    EndTimeRows(hasEnd: $hasEnd, endTime: $endTime, start: date, note: flags["endTime"])
                    OverlapNote(overlapping: overlapping)
                }
            }

            Section("Payment") {
                FlaggedRow(flags["price"]) {
                    TextField("Price", text: $priceText, prompt: Text("Price in dollars"))
                        .decimalKeyboard()
                }
                FlaggedRow(flags["paymentType"]) {
                    Picker("Payment", selection: $paymentType) {
                        ForEach(PaymentType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }
                FlaggedRow(flags["paid"]) {
                    Toggle("Paid", isOn: $isPaid)
                }
            }

            Section("Notes") {
                FlaggedRow(flags["note"]) {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }

            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Book Job") { trySave() }
                    .disabled(!endIsValid)
            }
        }
        .alert(overlapQuestion, isPresented: $askingOverlap) {
            Button("Yes") { save() }
            Button("No", role: .cancel) {}
        }
        .onAppear {
            if !flags.isEmpty || !overlapping.isEmpty { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    /// Asks "This overlaps … Save anyway?" first; No keeps the screen open.
    private func trySave() {
        if let question = JobOverlap.question(overlapping) {
            overlapQuestion = question
            flagged += 1
            askingOverlap = true
        } else {
            save()
        }
    }

    private func save() {
        let job = Job(
            customer: nil,
            jobType: quote.jobType,
            scheduledAt: hasTime ? date : Calendar.current.startOfDay(for: date),
            hasTime: hasTime,
            price: Parse.money(priceText),
            paymentType: paymentType,
            isPaid: isPaid,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        // Inserted first and connected after, so the links are made on a
        // stored record.
        context.insert(job)
        job.customer = quote.customer
        job.endsAt = endDate
        quote.markBooked(with: job)
        try? context.save()
        CalendarStore.shared.jobSaved(job)
        saved.toggle()
        onFinish("Job saved.")
    }
}

// MARK: Declined: mark it lost

/// The quote with Mark Lost. Anything said with it is added to its notes.
private struct LoseQuoteForm: View {
    @Environment(\.modelContext) private var context

    let quote: Quote
    private let flags: AssistantFlags
    var onFinish: (String) -> Void
    var onStartOver: () -> Void

    @State private var noteToAdd: String
    @State private var saved = false
    @State private var flagged = 0

    init(quote: Quote, action: AssistantAction, issues: [PlanIssue],
         onFinish: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.quote = quote
        self.flags = AssistantFlags(issues: issues)
        self.onFinish = onFinish
        self.onStartOver = onStartOver
        _noteToAdd = State(initialValue: action.note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        Form {
            QuoteDetailsSection(quote: quote, note: flags["ref"])
            QuoteNoteSection(quote: quote, note: flags["note"], text: $noteToAdd)
            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Mark Lost") { save() }
            }
        }
        .onAppear {
            if !flags.isEmpty { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private func save() {
        quote.addNote(noteToAdd)
        quote.markLost()
        try? context.save()
        saved.toggle()
        onFinish("Quote marked lost.")
    }
}

// MARK: Otherwise: price, call-back day, note

/// The quote with its price, call-back day and a note to add, and Save.
private struct UpdateQuoteForm: View {
    @Environment(\.modelContext) private var context

    let quote: Quote
    private let flags: AssistantFlags
    var onFinish: (String) -> Void
    var onStartOver: () -> Void

    @State private var priceText: String
    @State private var hasFollowUp: Bool
    @State private var followUpOn: Date
    @State private var noteToAdd: String
    @State private var saved = false
    @State private var flagged = 0

    init(quote: Quote, action: AssistantAction, issues: [PlanIssue],
         onFinish: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.quote = quote
        self.onFinish = onFinish
        self.onStartOver = onStartOver

        let saidFollowUp = JobDraft.day(from: action.followUp)
        let note = action.note.trimmingCharacters(in: .whitespacesAndNewlines)
        _priceText = State(initialValue: action.price.isEmpty ? Parse.moneyText(quote.price) : action.price)
        _hasFollowUp = State(initialValue: saidFollowUp != nil || quote.followUpOn != nil)
        _followUpOn = State(initialValue: saidFollowUp ?? quote.followUpOn ?? QuoteFormData.defaultFollowUp())
        _noteToAdd = State(initialValue: note)

        var flags = AssistantFlags(issues: issues)
        if action.price.isEmpty && saidFollowUp == nil && note.isEmpty {
            flags.add("price", "No change was heard.")
        }
        self.flags = flags
    }

    var body: some View {
        Form {
            QuoteDetailsSection(quote: quote, note: flags["ref"])
            Section("Changes") {
                FlaggedRow(flags["price"]) {
                    TextField("Price", text: $priceText, prompt: Text("Price in dollars"))
                        .decimalKeyboard()
                }
                Toggle("Follow up", isOn: $hasFollowUp)
                if hasFollowUp {
                    FlaggedRow(flags["followUp"]) {
                        DatePicker("Follow up on", selection: $followUpOn, displayedComponents: .date)
                    }
                }
            }
            QuoteNoteSection(quote: quote, note: flags["note"], text: $noteToAdd)
            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            if !flags.isEmpty { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private func save() {
        quote.price = Parse.money(priceText)
        quote.followUpOn = hasFollowUp ? Calendar.current.startOfDay(for: followUpOn) : nil
        quote.addNote(noteToAdd)
        quote.updatedAt = Date()
        try? context.save()
        saved.toggle()
        onFinish("Quote saved.")
    }
}

/// "Add a note", with the quote's notes so far underneath.
private struct QuoteNoteSection: View {
    let quote: Quote
    let note: String?
    @Binding var text: String

    var body: some View {
        Section {
            FlaggedRow(note) {
                TextField("Add a note", text: $text, axis: .vertical)
            }
        } header: {
            Text("Notes")
        } footer: {
            if !quote.notes.isEmpty {
                Text("Added under the quote's notes: " + quote.notes)
            }
        }
    }
}

private extension Quote {
    /// Adds a line under the quote's notes. Empty text changes nothing.
    func addNote(_ text: String) {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }
        notes = notes.isEmpty ? note : notes + "\n" + note
        updatedAt = Date()
    }
}

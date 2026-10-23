import SwiftData
import SwiftUI

/// The filled-in form after dictation. Fields Claude flagged are in the
/// warning color with its question underneath. On Save, each remaining
/// problem is asked as one yes/no question at a time, then the customer is
/// matched or created and the job stored.
struct JobReviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Customer.name) private var customers: [Customer]

    let draft: JobDraft
    /// The customer the note's reference pointed at, if any. The job goes to
    /// them unless the name is changed to someone else.
    let knownCustomer: Customer?
    /// The voice model, for answering the Missing questions by voice.
    let engine: SpeechEngine?
    var onSaved: () -> Void
    var onStartOver: () -> Void

    @State private var name: String
    @State private var phone: String
    @State private var address: String
    @State private var jobType: JobType
    @State private var date: Date
    @State private var hasTime: Bool
    /// "Set an end time", on when an end time was said.
    @State private var hasEnd: Bool
    /// The Ends picker; only its clock time is used, on the job's day.
    @State private var endTime: Date
    @State private var priceText: String
    @State private var paymentType: PaymentType
    @State private var isPaid: Bool
    @State private var notes: String
    /// Typed or said separately when the address came without one; it goes
    /// in front of the street on save.
    @State private var houseNumber = ""
    /// A date picked or said after the note had none.
    @State private var dateSet = false
    @FocusState private var focus: Gap?
    /// Questions passed over in the Missing card.
    @State private var skippedGaps: Set<Gap> = []
    /// A Missing button's field, scrolled to before it is typed in: on the
    /// iPhone a field further down the form is not built until it is near.
    @State private var scrollTarget: Gap?

    /// What Claude filled in, parsed once, so we can tell what Ashley changed.
    private let original: Original

    struct Original {
        var jobType: JobType
        var date: Date
        var hasTime: Bool
        var endDate: Date?
        var price: Double?
        var paymentType: PaymentType
        var isPaid: Bool
    }

    struct Question: Identifiable, Equatable {
        let id = UUID()
        let field: String
        let text: String
    }

    @State private var pending: [Question] = []
    @State private var current: Question?
    @State private var showingQuestion = false
    @State private var saved = false
    @State private var flagged = 0

    init(draft: JobDraft, knownCustomer: Customer? = nil, engine: SpeechEngine? = nil,
         onSaved: @escaping () -> Void, onStartOver: @escaping () -> Void) {
        self.draft = draft
        self.knownCustomer = knownCustomer
        self.engine = engine
        self.onSaved = onSaved
        self.onStartOver = onStartOver

        let parsedDate = Self.parse(date: draft.date, time: draft.time)
        let parsedType = draft.jobType.trimmingCharacters(in: .whitespaces).isEmpty ? .junkRemoval : JobType(stored: draft.jobType)
        let parsedPayment = JobDraft.paymentType(from: draft.paymentType) ?? .unknown
        let parsedPaid = draft.paid.lowercased() == "paid"
        // An end time only counts with a start time; nothing is assumed.
        let parsedEnd = parsedDate.hasTime ? JobTimes.end(fromClock: draft.endTime, on: parsedDate.date) : nil
        original = Original(
            jobType: parsedType,
            date: parsedDate.date,
            hasTime: parsedDate.hasTime,
            endDate: parsedEnd,
            price: Parse.money(draft.price),
            paymentType: parsedPayment,
            isPaid: parsedPaid
        )

        _name = State(initialValue: draft.customerName)
        _phone = State(initialValue: PhoneFormat.formatted(draft.phone))
        _address = State(initialValue: draft.address)
        _jobType = State(initialValue: parsedType)
        _date = State(initialValue: parsedDate.date)
        _hasTime = State(initialValue: parsedDate.hasTime)
        _hasEnd = State(initialValue: parsedEnd != nil)
        _endTime = State(initialValue: parsedEnd ?? JobTimes.suggestedEnd(after: parsedDate.date))
        _priceText = State(initialValue: draft.price)
        _paymentType = State(initialValue: parsedPayment)
        _isPaid = State(initialValue: parsedPaid)
        _notes = State(initialValue: draft.notes)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                MissingSection(
                    gaps: gaps,
                    engine: engine,
                    formSummary: { formSummary },
                    onPick: pick,
                    onFill: fill,
                    skipped: $skippedGaps
                )

                Section {
                    // Every field shows where to type, so a gap is one click and
                    // a few keys to fix (Kyle, Oct 19).
                    field("customerName") {
                        TextField("Name", text: $name, prompt: Text("Customer name"))
                            .focused($focus, equals: .name)
                            .id(Gap.name)
                    }
                    field("phone") {
                        TextField("Phone", text: $phone, prompt: Text("Add a phone number"))
                            .phoneKeyboard()
                            .focused($focus, equals: .phone)
                            .id(Gap.phone)
                    }
                    if gaps.contains(.houseNumber) || !houseNumber.isEmpty {
                        TextField("House number", text: $houseNumber, prompt: Text("House number"))
                            .houseNumberKeyboard()
                            .focused($focus, equals: .houseNumber)
                            .id(Gap.houseNumber)
                            .foregroundStyle(houseNumber.isEmpty ? Tint.warning : Color.primary)
                    }
                    field("address") {
                        TextField("Address", text: $address, prompt: Text("Street and town"), axis: .vertical)
                            .focused($focus, equals: .address)
                            .id(Gap.address)
                    }
                    if let match = matchingCustomer {
                        Text("Matches existing customer \(match.name), \(match.address.isEmpty ? "no address on file" : match.address).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("New customer.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Customer")
                }

                Section("Job") {
                    field("jobType") {
                        Picker("Type", selection: $jobType) {
                            ForEach(JobType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                    }
                    field("date") {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .focused($focus, equals: .date)
                            .id(Gap.date)
                    }
                    Toggle("Set a time", isOn: $hasTime)
                    if hasTime {
                        field("time") {
                            DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                        }
                        EndTimeRows(hasEnd: $hasEnd, endTime: $endTime, start: date, note: questions[Self.key("endTime")])
                        OverlapNote(overlapping: overlapping)
                    } else if let question = questions[Self.key("time")] {
                        Text(question)
                            .font(.footnote)
                            .foregroundStyle(Tint.warning)
                    }
                }

                Section("Payment") {
                    field("price") {
                        TextField("Price", text: $priceText, prompt: Text("Price in dollars"))
                            .decimalKeyboard()
                            .focused($focus, equals: .price)
                            .id(Gap.price)
                    }
                    field("paymentType") {
                        Picker("Payment", selection: $paymentType) {
                            ForEach(PaymentType.allCases) { type in
                                Label(type.rawValue, systemImage: type.symbol).tag(type)
                            }
                        }
                    }
                    field("paid") {
                        Toggle("Paid", isOn: $isPaid)
                    }
                }

                Section("Notes") {
                    field("notes") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 60)
                    }
                }

                Section {
                    Button("Start over") { onStartOver() }
                }
            }
            .formStyle(.grouped)
            .onChange(of: focus) { _, gap in
                // Brings the field being filled in clear of the keyboard.
                guard let gap else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation { proxy.scrollTo(gap, anchor: .center) }
                }
            }
            .onChange(of: scrollTarget) { _, gap in
                guard let gap else { return }
                // Cleared first: focus set while an alert was closing can
                // be left pointing at a field that never got the keyboard,
                // and setting the same field again would then do nothing.
                focus = nil
                withAnimation { proxy.scrollTo(gap, anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focus = gap
                    scrollTarget = nil
                }
                // Once more if it did not take (a closing alert can swallow
                // the first try).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    guard focus != gap else { return }
                    withAnimation { proxy.scrollTo(gap, anchor: .center) }
                    focus = gap
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { beginSave() }
                    .disabled(!endIsValid)
            }
        }
        // "Save as is" / "Fix it", never Yes / No: Claude's own questions are
        // worded either way ("Do you have a phone number?"), and Yes used to
        // save without one (Oct 20 audit).
        .alert(current?.text ?? "", isPresented: $showingQuestion) {
            Button("Save as is") { answeredYes() }
            Button("Fix it", role: .cancel) { answeredNo() }
        } message: {
            Text("Save the job as it is, or go back and fix it first?")
        }
        .onAppear {
            if !draft.issues.isEmpty || !gaps.isEmpty { flagged += 1 }
        }
        .onChange(of: date) { old, new in
            // Only picking a day answers "No date": changing just the time
            // does not (Oct 20 phone audit).
            if !Calendar.current.isDate(old, inSameDayAs: new) { dateSet = true }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    // MARK: Flags on the form

    /// Field names as Claude may spell them ("customerName", "customer_name",
    /// "CustomerName") reduced to one form.
    private static func key(_ text: String) -> String {
        text.lowercased().filter { $0 != "_" && $0 != " " }
    }

    /// Claude's questions plus the gaps the app itself can see.
    private var questions: [String: String] {
        var map = Dictionary(draft.issues.map { (Self.key($0.field), $0.question) }, uniquingKeysWith: { first, _ in first })
        if draft.date.isEmpty, !dateSet, map[Self.key("date")] == nil {
            map[Self.key("date")] = "No date was given. Save for today?"
        }
        // No job type said: the form shows its default quietly, without a
        // question (Kyle: it kept asking for the job type).
        return map
    }

    /// Wraps a field; when it was flagged, the label turns the warning color
    /// and the question appears underneath.
    @ViewBuilder
    private func field<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        if let question = questions[Self.key(name)], !resolved(name) {
            content()
                .foregroundStyle(Tint.warning)
            Text(question)
                .font(.footnote)
                .foregroundStyle(Tint.warning)
        } else {
            content()
        }
    }

    // MARK: Missing pieces

    /// The address with the house number typed or said separately in front.
    private var fullAddress: String {
        let street = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = houseNumber.trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty else { return street }
        return street.isEmpty ? number : number + " " + street
    }

    /// What is still missing, in the order it is asked about. A customer on
    /// file covers their own phone and address. No time is fine (the prompt
    /// never asks about one either).
    private var gaps: [Gap] {
        var list: [Gap] = []
        let match = matchingCustomer
        if name.trimmingCharacters(in: .whitespaces).isEmpty { list.append(.name) }
        if fullAddress.isEmpty {
            if match?.address.isEmpty ?? true { list.append(.address) }
        } else if SpokenAddress(fullAddress).houseNumber == nil {
            list.append(.houseNumber)
        }
        if phoneDigits.isEmpty, match?.phone.isEmpty ?? true { list.append(.phone) }
        if draft.date.isEmpty, !dateSet { list.append(.date) }
        if Parse.money(priceText) == nil, jobType != .estimate { list.append(.price) }
        return list
    }

    /// A Missing button: the field, ready to type in.
    private func pick(_ gap: Gap) {
        scrollTarget = gap
    }

    /// The form as it stands, for reading an answer in context.
    private var formSummary: String {
        [
            "Name: \(name)",
            "Phone: \(phone)",
            "Address: \(fullAddress)",
            "Job: \(jobType.rawValue)",
            "Date: \(Dates.longDay(date))",
            "Price: \(priceText)",
        ].joined(separator: "\n")
    }

    /// A spoken answer, into its field.
    private func fill(_ gap: Gap, _ value: String) {
        switch gap {
        case .name:
            name = value
        case .address:
            address = value
        case .houseNumber:
            houseNumber = value
        case .phone:
            phone = PhoneFormat.formatted(value)
        case .date:
            guard let day = JobDraft.day(from: value) else { return }
            let calendar = Calendar.current
            let clock = calendar.dateComponents([.hour, .minute], from: date)
            date = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day) ?? day
            dateSet = true
        case .price:
            priceText = value
        }
    }

    // MARK: Overlaps

    /// The end time to save, on the job's day; nil without one.
    private var endDate: Date? {
        hasTime ? JobTimes.end(start: date, hasEnd: hasEnd, endTime: endTime) : nil
    }

    /// False while an end time is set that is not after the start.
    private var endIsValid: Bool {
        !hasTime || JobTimes.endIsValid(start: date, hasEnd: hasEnd, endTime: endTime)
    }

    /// Unfinished timed jobs that day this one would clash with.
    private var overlapping: [Job] {
        guard hasTime else { return [] }
        return JobOverlap.find(start: date, end: endDate, excluding: nil, in: jobs)
    }

    // MARK: Matching

    private var phoneDigits: String { phone.filter(\.isNumber) }

    private var matchingCustomer: Customer? {
        existingCustomer(name: name, phone: phone, address: fullAddress, known: knownCustomer, in: customers)
    }

    // MARK: Questions, one at a time

    private func beginSave() {
        var list: [Question] = []
        var covered = Set<String>()

        func ask(_ field: String, _ text: String) {
            list.append(Question(field: field, text: text))
            covered.insert(Self.key(field))
        }

        // A question already passed over with Skip is not asked again;
        // the past-date and double-booking checks always are.
        if name.trimmingCharacters(in: .whitespaces).isEmpty && !skippedGaps.contains(.name) {
            ask("customerName", "No name was given. Save as \"Unknown customer\"?")
        }
        if phoneDigits.isEmpty && matchingCustomer == nil && !skippedGaps.contains(.phone) {
            ask("phone", "No phone number. Save without one?")
        }
        // A quote visit is booked to work out the price; there is none yet.
        if Parse.money(priceText) == nil && jobType != .estimate && !skippedGaps.contains(.price) {
            ask("price", "No price. Save without one?")
        }
        let scheduled = hasTime ? date : Calendar.current.startOfDay(for: date)
        if scheduled < Dates.startOfToday() {
            ask("date", "The date is in the past (\(Dates.shortDay(date))). Save anyway?")
        } else if draft.date.isEmpty && !dateSet && !skippedGaps.contains(.date) {
            ask("date", "No date was given. Save for today (\(Dates.shortDay(date)))?")
        }
        if let question = JobOverlap.question(overlapping) {
            ask("time", question)
        }
        // Claude's own questions, except the ones the code just asked or that
        // Ashley has since changed.
        for issue in draft.issues where !covered.contains(Self.key(issue.field)) && !resolved(issue.field) && !skippedIssue(issue.field) {
            list.append(Question(field: issue.field, text: issue.question))
        }

        pending = list
        if !list.isEmpty { flagged += 1 }
        advance()
    }

    /// Claude's question about a gap skipped in the Missing card. A skipped
    /// house number covers Claude's "address" question too.
    private func skippedIssue(_ field: String) -> Bool {
        guard let gap = Gap(field: field) else { return false }
        if skippedGaps.contains(gap) { return true }
        return gap == .address && skippedGaps.contains(.houseNumber)
    }

    /// True when Ashley changed the field away from what Claude filled in.
    private func resolved(_ field: String) -> Bool {
        switch Self.key(field) {
        case "customername":
            return name.trimmingCharacters(in: .whitespaces) != draft.customerName.trimmingCharacters(in: .whitespaces)
                && !name.trimmingCharacters(in: .whitespaces).isEmpty
        case "phone":
            return phoneDigits != draft.phone.filter(\.isNumber) && !phoneDigits.isEmpty
        case "address":
            return fullAddress != draft.address && fullAddress.contains(where: \.isNumber)
        case "jobtype":
            return jobType != original.jobType
        case "date":
            return dateSet || !Calendar.current.isDate(date, inSameDayAs: original.date)
        case "time":
            return hasTime && (!original.hasTime || date != original.date)
        case "endtime":
            return endDate != original.endDate
        case "price":
            return Parse.money(priceText) != original.price && Parse.money(priceText) != nil
        case "paymenttype":
            return paymentType != original.paymentType
        case "paid":
            return isPaid != original.isPaid
        case "notes":
            return notes != draft.notes
        default:
            return false
        }
    }

    private func advance() {
        if let next = pending.first {
            current = next
            showingQuestion = true
        } else {
            current = nil
            performSave()
        }
    }

    private func answeredYes() {
        if !pending.isEmpty { pending.removeFirst() }
        // Let the alert finish dismissing before showing the next one.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            advance()
        }
    }

    /// "Fix it": back to the form, with the field the question was about
    /// ready to type in.
    private func answeredNo() {
        let field = current?.field
        pending = []
        current = nil
        if let field, let gap = Gap(field: field) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                pick(gap == .address && gaps.contains(.houseNumber) ? .houseNumber : gap)
            }
        }
    }

    // MARK: Save

    private func performSave() {
        let customer: Customer
        if let match = matchingCustomer {
            customer = match
            var changed = false
            if customer.phone.isEmpty, !phoneDigits.isEmpty { customer.phone = PhoneFormat.formatted(phone); changed = true }
            if customer.address.isEmpty, !fullAddress.isEmpty { customer.address = fullAddress; changed = true }
            // Stamped only when something changed: a stamp alone sends the
            // customer to every device and their rows to the sheet.
            if changed { customer.updatedAt = Date() }
        } else {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            customer = Customer(
                name: trimmedName.isEmpty ? "Unknown customer" : trimmedName,
                phone: PhoneFormat.formatted(phone),
                address: fullAddress
            )
            context.insert(customer)
        }

        let job = Job(
            customer: nil,
            jobType: jobType,
            scheduledAt: hasTime ? date : Calendar.current.startOfDay(for: date),
            hasTime: hasTime,
            price: Parse.money(priceText),
            paymentType: paymentType,
            isPaid: isPaid,
            notes: CustomerAddress.notes(notes, saidAddress: fullAddress, onFile: customer.address)
        )
        context.insert(job)
        job.customer = customer
        job.endsAt = endDate
        try? context.save()
        CalendarStore.shared.jobSaved(job)
        // A phone or address filled in above goes onto their other jobs' events.
        CalendarStore.shared.customerSaved(customer)
        saved.toggle()
        onSaved()
    }

    // MARK: Parsing what Claude sent

    private static func parse(date: String, time: String) -> (date: Date, hasTime: Bool) {
        let calendar = Calendar.current
        var day = Dates.startOfToday()
        let dayParts = date.split(separator: "-").compactMap { Int($0) }
        if dayParts.count == 3,
           let parsed = calendar.date(from: DateComponents(year: dayParts[0], month: dayParts[1], day: dayParts[2])) {
            day = parsed
        }
        let timeParts = time.split(separator: ":").compactMap { Int($0) }
        if timeParts.count == 2,
           let withTime = calendar.date(bySettingHour: timeParts[0], minute: timeParts[1], second: 0, of: day) {
            return (withTime, true)
        }
        return (day, false)
    }

}

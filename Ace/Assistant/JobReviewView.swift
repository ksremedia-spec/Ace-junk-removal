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
    var onSaved: () -> Void
    var onStartOver: () -> Void

    @State private var name: String
    @State private var phone: String
    @State private var address: String
    @State private var jobType: JobType
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var priceText: String
    @State private var paymentType: PaymentType
    @State private var isPaid: Bool
    @State private var notes: String

    struct Question: Identifiable, Equatable {
        let id = UUID()
        let field: String
        let text: String
    }

    @State private var pending: [Question] = []
    @State private var current: Question?
    @State private var showingQuestion = false
    @State private var saved = false

    private var claudeQuestions: [String: String] {
        Dictionary(draft.issues.map { ($0.field, $0.question) }, uniquingKeysWith: { first, _ in first })
    }

    init(draft: JobDraft, onSaved: @escaping () -> Void, onStartOver: @escaping () -> Void) {
        self.draft = draft
        self.onSaved = onSaved
        self.onStartOver = onStartOver
        _name = State(initialValue: draft.customerName)
        _phone = State(initialValue: PhoneFormat.formatted(draft.phone))
        _address = State(initialValue: draft.address)
        _jobType = State(initialValue: JobType(rawValue: draft.jobType) ?? .junkRemoval)
        let parsed = Self.parse(date: draft.date, time: draft.time)
        _date = State(initialValue: parsed.date)
        _hasTime = State(initialValue: parsed.hasTime)
        _priceText = State(initialValue: draft.price)
        _paymentType = State(initialValue: Self.payment(from: draft.paymentType))
        _isPaid = State(initialValue: draft.paid == "paid")
        _notes = State(initialValue: draft.notes)
    }

    var body: some View {
        Form {
            Section {
                field("customerName") {
                    TextField("Name", text: $name)
                }
                field("phone") {
                    TextField("Phone", text: $phone)
                        .phoneKeyboard()
                }
                field("address") {
                    TextField("Address", text: $address, axis: .vertical)
                }
                if let match = matchingCustomer {
                    Text("Matches existing customer \(match.name).")
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
                }
                Toggle("Set a time", isOn: $hasTime)
                if hasTime {
                    field("time") {
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                    }
                } else if let question = claudeQuestions["time"] {
                    Text(question)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Payment") {
                field("price") {
                    TextField("Price", text: $priceText, prompt: Text("Price in dollars"))
                        .decimalKeyboard()
                }
                field("paymentType") {
                    Picker("Payment", selection: $paymentType) {
                        ForEach(PaymentType.allCases) { type in
                            Text(type.rawValue).tag(type)
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
                Button("Save job") { beginSave() }
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .alert(current?.text ?? "", isPresented: $showingQuestion) {
            Button("Yes") { answeredYes() }
            Button("No", role: .cancel) { answeredNo() }
        }
        .sensoryFeedback(.success, trigger: saved)
    }

    /// Wraps a field; when Claude flagged it, the label turns the warning
    /// color and its question appears underneath.
    @ViewBuilder
    private func field<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        if let question = claudeQuestions[key] {
            content()
                .foregroundStyle(Color.orange)
            Text(question)
                .font(.footnote)
                .foregroundStyle(.orange)
        } else {
            content()
        }
    }

    // MARK: Matching

    private var phoneDigits: String { phone.filter(\.isNumber) }

    private var matchingCustomer: Customer? {
        if phoneDigits.count >= 7, let byPhone = customers.first(where: { $0.phoneDigits == phoneDigits }) {
            return byPhone
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return customers.first { $0.name.lowercased() == trimmed }
    }

    // MARK: Questions, one at a time

    private func beginSave() {
        var questions: [Question] = []
        var covered = Set<String>()

        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            questions.append(Question(field: "customerName", text: "No name was given. Save as \"Unknown customer\"?"))
            covered.insert("customerName")
        }
        if phoneDigits.isEmpty && matchingCustomer == nil {
            questions.append(Question(field: "phone", text: "No phone number. Save without one?"))
            covered.insert("phone")
        }
        if Parse.money(priceText) == nil {
            questions.append(Question(field: "price", text: "No price. Save without one?"))
            covered.insert("price")
        }
        let scheduled = hasTime ? date : Calendar.current.startOfDay(for: date)
        if scheduled < Dates.startOfToday() {
            questions.append(Question(field: "date", text: "The date is in the past (\(Dates.shortDay(date))). Save anyway?"))
            covered.insert("date")
        }
        if let clash = doubleBooking(at: scheduled) {
            questions.append(Question(field: "time", text: "Another job is already booked \(clash.whenText): \(clash.customer?.name ?? "no customer"), \(clash.jobType.rawValue). Book this one too?"))
            covered.insert("time")
        }
        // Claude's own questions, except the ones the code just asked or that
        // Ashley has since fixed.
        for issue in draft.issues where !covered.contains(issue.field) && !resolved(issue.field) {
            questions.append(Question(field: issue.field, text: issue.question))
        }

        pending = questions
        advance()
    }

    private func resolved(_ field: String) -> Bool {
        switch field {
        case "customerName": return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case "phone": return !phoneDigits.isEmpty
        case "address": return address.trimmingCharacters(in: .whitespaces).contains(where: \.isNumber)
        case "price": return Parse.money(priceText) != nil
        case "time": return hasTime
        default: return false
        }
    }

    private func doubleBooking(at scheduled: Date) -> Job? {
        let calendar = Calendar.current
        return jobs.first { job in
            guard !job.isDone, calendar.isDate(job.scheduledAt, inSameDayAs: scheduled) else { return false }
            guard hasTime, job.hasTime else { return false }
            return calendar.component(.hour, from: job.scheduledAt) == calendar.component(.hour, from: scheduled)
                && calendar.component(.minute, from: job.scheduledAt) == calendar.component(.minute, from: scheduled)
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

    private func answeredNo() {
        pending = []
        current = nil
    }

    // MARK: Save

    private func performSave() {
        let customer: Customer
        if let match = matchingCustomer {
            customer = match
            if customer.phone.isEmpty, !phoneDigits.isEmpty { customer.phone = PhoneFormat.formatted(phone) }
            if customer.address.isEmpty { customer.address = address.trimmingCharacters(in: .whitespacesAndNewlines) }
            customer.updatedAt = Date()
        } else {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            customer = Customer(
                name: trimmedName.isEmpty ? "Unknown customer" : trimmedName,
                phone: PhoneFormat.formatted(phone),
                address: address.trimmingCharacters(in: .whitespacesAndNewlines)
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
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(job)
        job.customer = customer
        try? context.save()
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

    private static func payment(from text: String) -> PaymentType {
        switch text.lowercased() {
        case "cash": return .cash
        case "check": return .check
        case "card": return .card
        default: return .unknown
        }
    }
}

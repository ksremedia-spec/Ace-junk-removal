import SwiftData
import SwiftUI

/// "Johnson's done, paid cash." Finds the job the note means and shows the
/// changes to confirm. With several possible jobs, Alex picks one first. With
/// none, the note can be turned into a new job instead.
struct JobUpdateView: View {
    let draft: JobDraft
    let customers: [Customer]
    let jobs: [Job]
    var onSaved: () -> Void
    var onStartOver: () -> Void
    var onStartNewJob: () -> Void

    @State private var picked: Job?

    private var candidates: [Job] {
        let matched = matchCustomers(draft, in: customers)
        return matchJobs(draft, customers: matched, allJobs: jobs, today: Dates.startOfToday())
    }

    private var job: Job? {
        if let picked { return picked }
        let found = candidates
        return found.count == 1 ? found.first : nil
    }

    var body: some View {
        if let job {
            JobUpdateForm(job: job, draft: draft, onSaved: onSaved, onStartOver: onStartOver)
        } else if candidates.isEmpty {
            notFound
        } else {
            whichJob
        }
    }

    // MARK: Which job?

    private var whichJob: some View {
        List {
            Section {
                ForEach(candidates) { candidate in
                    Button {
                        picked = candidate
                    } label: {
                        Text(Self.rowText(for: candidate))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Which job?")
            }
            Section {
                Button("Start over") { onStartOver() }
            }
        }
    }

    /// "Linda Johnson · Junk removal · Mon, Oct 19 at 9:00 AM"
    private static func rowText(for job: Job) -> String {
        [job.customer?.name ?? "No customer", job.jobType.rawValue, job.whenText].joined(separator: " · ")
    }

    // MARK: Nothing found

    private var notFound: some View {
        Form {
            Section {
                Text("No job found for \(subject).")
            } footer: {
                Text("An update needs a job that is already on the books.")
            }
            Section {
                Button("Start a new job instead") { onStartNewJob() }
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
    }

    private var subject: String {
        let name = draft.customerName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let address = draft.address.trimmingCharacters(in: .whitespaces)
        if !address.isEmpty { return address }
        return "that"
    }
}

/// The job as it stands, then the changes heard, ready to save.
private struct JobUpdateForm: View {
    @Environment(\.modelContext) private var context

    let job: Job
    let draft: JobDraft
    var onSaved: () -> Void
    var onStartOver: () -> Void

    @State private var isDone: Bool
    @State private var isPaid: Bool
    @State private var paymentType: PaymentType
    @State private var priceText: String
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var noteToAdd: String
    @State private var saved = false
    @State private var flagged = 0

    private let flags: AssistantFlags

    init(job: Job, draft: JobDraft, onSaved: @escaping () -> Void, onStartOver: @escaping () -> Void) {
        self.job = job
        self.draft = draft
        self.onSaved = onSaved
        self.onStartOver = onStartOver

        let done = draft.done.lowercased()
        let paid = draft.paid.lowercased()
        let paymentSaid = JobDraft.paymentType(from: draft.paymentType)
        _isDone = State(initialValue: done == "yes" ? true : (done == "no" ? false : job.isDone))
        _isPaid = State(initialValue: paid == "paid" ? true : (paid == "unpaid" ? false : job.isPaid))
        _paymentType = State(initialValue: paymentSaid ?? job.paymentType)
        _priceText = State(initialValue: draft.price.isEmpty ? Parse.moneyText(job.price) : draft.price)

        let calendar = Calendar.current
        var when = job.scheduledAt
        var hasTime = job.hasTime
        if let newDay = JobDraft.day(from: draft.newDate) {
            let hour = calendar.component(.hour, from: when)
            let minute = calendar.component(.minute, from: when)
            when = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDay) ?? newDay
        }
        if let clock = JobDraft.clock(from: draft.newTime) {
            when = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: when) ?? when
            hasTime = true
        }
        _date = State(initialValue: when)
        _hasTime = State(initialValue: hasTime)
        _noteToAdd = State(initialValue: draft.notes)

        var flags = AssistantFlags(draft: draft)
        let heardAChange = done == "yes" || done == "no" || paid == "paid" || paid == "unpaid" || paymentSaid != nil
            || !draft.price.isEmpty || !draft.newDate.isEmpty || !draft.newTime.isEmpty || !draft.notes.isEmpty
        if !heardAChange {
            flags.add("done", "No change was heard. Mark the job done?")
        }
        self.flags = flags
    }

    var body: some View {
        Form {
            customerSection
            jobSection
            changesSection
            notesSection
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

    private var customerSection: some View {
        Section("Customer") {
            LabeledContent("Customer", value: job.customer?.name ?? "No customer")
            if let phone = job.customer?.phone, !phone.isEmpty {
                LabeledContent("Phone", value: phone)
            }
            if let address = job.customer?.address, !address.isEmpty {
                LabeledContent("Address") {
                    Text(address)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var jobSection: some View {
        Section("Job") {
            LabeledContent("Type", value: job.jobType.rawValue)
            LabeledContent("Scheduled", value: job.whenText)
            if !job.priceText.isEmpty {
                LabeledContent("Price", value: job.priceText + (job.isPaid ? ", paid" : ", unpaid"))
            }
            if job.isDone {
                LabeledContent("Status", value: "Done")
            }
        }
    }

    private var changesSection: some View {
        Section("Changes") {
            FlaggedRow(flags["done"]) {
                Toggle("Done", isOn: $isDone)
            }
            FlaggedRow(flags["paid"]) {
                Toggle("Paid", isOn: $isPaid)
            }
            FlaggedRow(flags["paymentType"]) {
                Picker("Payment", selection: $paymentType) {
                    ForEach(PaymentType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
            }
            FlaggedRow(flags["price"]) {
                TextField("Price", text: $priceText, prompt: Text("Price in dollars"))
                    .decimalKeyboard()
            }
            FlaggedRow(flags["newDate"]) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            Toggle("Set a time", isOn: $hasTime)
            if hasTime {
                FlaggedRow(flags["newTime"]) {
                    DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                }
            }
        }
    }

    private var notesSection: some View {
        Section {
            FlaggedRow(flags["notes"]) {
                TextField("Add a note", text: $noteToAdd, axis: .vertical)
            }
        } header: {
            Text("Notes")
        } footer: {
            if !job.notes.isEmpty {
                Text("Added under the job's notes: " + job.notes)
            }
        }
    }

    private func save() {
        job.isDone = isDone
        job.isPaid = isPaid
        job.paymentType = paymentType
        job.price = Parse.money(priceText)
        job.scheduledAt = hasTime ? date : Calendar.current.startOfDay(for: date)
        job.hasTime = hasTime
        let note = noteToAdd.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            job.notes = job.notes.isEmpty ? note : job.notes + "\n" + note
        }
        job.updatedAt = Date()
        try? context.save()
        saved.toggle()
        onSaved()
    }
}

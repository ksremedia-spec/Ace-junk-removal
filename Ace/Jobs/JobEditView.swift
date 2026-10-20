import SwiftData
import SwiftUI

/// Add a job (presented as a sheet) or edit one (pushed from a list).
struct JobEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Every job, to check for overlaps.
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]

    let job: Job?
    /// Called with the job after Save, before the form closes. Booking a
    /// quote uses it to mark the quote booked; Cancel never calls it.
    private let onSaved: ((Job) -> Void)?
    @State private var form: JobFormData
    /// The form as it was opened (or last saved), to tell whether anything
    /// has changed since.
    @State private var original: JobFormData
    @State private var showingCustomerPicker = false
    @State private var confirmDelete = false
    @State private var saved = false
    @State private var askingOverlap = false
    @State private var overlapQuestion = ""
    @State private var flagged = 0

    private var isNew: Bool { job == nil }

    init(job: Job?, prefill: JobFormData? = nil, onSaved: ((Job) -> Void)? = nil) {
        self.job = job
        self.onSaved = onSaved
        let start = prefill ?? JobFormData(job: job)
        _form = State(initialValue: start)
        _original = State(initialValue: start)
    }

    var body: some View {
        Form {
            Section {
                header
                    .bareRow()
            }

            Section("Customer") {
                LabeledContent("Customer") {
                    Button(form.customer?.name ?? "Choose…") {
                        showingCustomerPicker = true
                    }
                }
                if let customer = form.customer {
                    if !customer.phone.isEmpty {
                        LabeledContent("Phone", value: customer.phone)
                    }
                    if !customer.address.isEmpty {
                        LabeledContent("Address", value: customer.address)
                    }
                }
            }

            Section("Job") {
                Picker("Type", selection: $form.jobType) {
                    ForEach(JobType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                DatePicker("Date", selection: $form.date, displayedComponents: .date)
                Toggle("Set a time", isOn: $form.hasTime)
                if form.hasTime {
                    DatePicker("Time", selection: $form.date, displayedComponents: .hourAndMinute)
                    EndTimeRows(hasEnd: $form.hasEnd, endTime: $form.endTime, start: form.date)
                    OverlapNote(overlapping: overlapping)
                }
            }

            Section("Payment") {
                TextField("Price", text: $form.priceText, prompt: Text("Price in dollars"))
                    .decimalKeyboard()
                Picker("Payment", selection: $form.paymentType) {
                    ForEach(PaymentType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                Toggle("Paid", isOn: $form.isPaid)
            }

            Section("Notes") {
                TextEditor(text: $form.notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
            }

            if !isNew {
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete job", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .readableWidth()
        .navigationTitle(isNew ? "New job" : "Job")
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { trySave() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(form.customer == nil || !form.endIsValid || (!isNew && !hasChanges))
            }
        }
        .sheet(isPresented: $showingCustomerPicker) {
            NavigationStack {
                CustomerPickerView(selection: $form.customer)
            }
        }
        .confirmationDialog("Delete this job?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        }
        .alert(overlapQuestion, isPresented: $askingOverlap) {
            Button("Save anyway") { save() }
            Button("Change the time", role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
        // On the Mac the list's right-click menu can change these while this
        // form is open; keep the form in step so Save does not undo them.
        .onChange(of: job?.isDone) { _, newValue in
            if let newValue { form.isDone = newValue; original.isDone = newValue }
        }
        .onChange(of: job?.isPaid) { _, newValue in
            if let newValue { form.isPaid = newValue; original.isPaid = newValue }
        }
        // On the Mac this page sits beside the list: clicking another job
        // used to throw away unsaved changes without a word. Like Mail and
        // Notes, they are kept instead (Oct 20 audit).
        .onDisappear {
            if !isNew, hasChanges, form.customer != nil, form.endIsValid { persist() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    // MARK: Header

    /// Built from the form, so it follows every change before Save.
    private var header: some View {
        DetailHeader(
            title: form.customer?.name ?? (isNew ? "New job" : "No customer"),
            subtitle: whenText,
            caption: form.customer?.address.isEmpty == false ? form.customer?.address : nil,
            value: Parse.money(form.priceText).map(Money.text),
            valueTint: form.isPaid ? .secondary : .primary,
            hasActions: job != nil || form.customer?.phoneURL != nil || form.customer?.directionsURL != nil
        ) {
            TypeBadge(type: form.jobType, size: 52, muted: form.isDone)
        } pills: {
            if hasPills {
                HStack(spacing: Space.xs) {
                    // Done and Paid show on the buttons below; only what they
                    // do not say gets a pill.
                    if job == nil && form.isDone {
                        StatusPill(text: "Done", tint: Tint.done, symbol: "checkmark")
                    }
                    if job == nil && form.isPaid {
                        StatusPill(text: "Paid", tint: Tint.paid)
                    } else if !form.isPaid && form.isDone && Parse.money(form.priceText) != nil {
                        StatusPill(text: "Unpaid", tint: Tint.owed)
                    }
                    if !overlapping.isEmpty {
                        StatusPill(text: "Overlaps", tint: Tint.owed, symbol: "exclamationmark.triangle.fill")
                    }
                }
            }
        } actions: {
            if let job {
                Button {
                    setDone(!job.isDone, on: job)
                } label: {
                    Label(job.isDone ? "Done" : "Mark done", systemImage: job.isDone ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(.action(job.isDone ? Tint.paid : .secondary, prominent: job.isDone))
                .help(job.isDone ? "Done. Click to mark it not done." : "Mark this job done")
                Button {
                    setPaid(!job.isPaid, on: job)
                } label: {
                    Label(job.isPaid ? "Paid" : "Mark paid", systemImage: job.isPaid ? "dollarsign.circle.fill" : "dollarsign.circle")
                }
                .buttonStyle(.action(job.isPaid ? Tint.paid : .secondary, prominent: job.isPaid))
                .help(job.isPaid ? "Paid. Click to mark it unpaid." : "Mark this job paid")
            }
            if let url = form.customer?.phoneURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Call", systemImage: "phone.fill")
                }
                .buttonStyle(.action())
            }
            if let url = form.customer?.directionsURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Directions", systemImage: "map.fill")
                }
                .buttonStyle(.action())
            }
        }
    }

    private var hasPills: Bool {
        (job == nil && (form.isDone || form.isPaid))
            || (!form.isPaid && form.isDone && Parse.money(form.priceText) != nil)
            || !overlapping.isEmpty
    }

    /// "Junk removal · Mon, Oct 19 · 9:00 to 11:00 AM"
    private var whenText: String {
        var text = form.jobType.rawValue + " · " + Dates.shortDay(form.date)
        if form.hasTime {
            text += " · " + JobTimes.text(start: form.date, end: form.endDate)
        }
        return text
    }

    /// The header's Done and Paid buttons save straight away, the same as
    /// the list's right-click menu; the form follows through onChange.
    private func setDone(_ done: Bool, on job: Job) {
        job.isDone = done
        job.updatedAt = Date()
        try? context.save()
        CalendarStore.shared.jobSaved(job)
        saved.toggle()
    }

    private func setPaid(_ paid: Bool, on job: Job) {
        job.isPaid = paid
        job.updatedAt = Date()
        try? context.save()
        CalendarStore.shared.jobSaved(job)
        saved.toggle()
    }

    /// Other unfinished timed jobs that day that this one would clash with.
    /// None while "Set a time" is off or the job is marked done.
    private var overlapping: [Job] {
        guard form.hasTime, !form.isDone else { return [] }
        return JobOverlap.find(start: form.date, end: form.endDate, excluding: job, in: jobs)
    }

    /// A new job, or one whose day, time or end time was changed here.
    /// Saving an unchanged job (marking it paid, say) does not ask again.
    private var timingChanged: Bool {
        guard let job else { return true }
        return job.hasTime != form.hasTime
            || job.scheduledAt != form.date
            || job.endsAt != form.endDate
    }

    /// Asks "This overlaps … Save anyway?" first when the job overlaps
    /// another; No keeps the form open.
    private func trySave() {
        if timingChanged, let question = JobOverlap.question(overlapping) {
            overlapQuestion = question
            flagged += 1
            askingOverlap = true
        } else {
            save()
        }
    }

    private var hasChanges: Bool { form != original }

    private func save() {
        let target = persist()
        saved.toggle()
        onSaved?(target)
        dismiss()
    }

    /// Writes the form to the job, without closing anything.
    @discardableResult
    private func persist() -> Job {
        let target: Job
        if let job {
            target = job
        } else {
            target = Job(customer: nil, jobType: form.jobType, scheduledAt: form.date, hasTime: form.hasTime)
            context.insert(target)
        }
        form.apply(to: target)
        try? context.save()
        CalendarStore.shared.jobSaved(target)
        original = form
        return target
    }

    private func delete() {
        if let job {
            job.remove(from: context)
        }
        dismiss()
    }
}

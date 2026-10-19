import SwiftData
import SwiftUI

/// Add a job (presented as a sheet) or edit one (pushed from a list).
struct JobEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Every job, to check for overlaps.
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]

    let job: Job?
    /// Called with the job after Save, before the form closes. Booking a
    /// quote uses it to mark the quote booked; Cancel never calls it.
    private let onSaved: ((Job) -> Void)?
    @State private var form: JobFormData
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
        _form = State(initialValue: prefill ?? JobFormData(job: job))
    }

    var body: some View {
        Form {
            Section("Customer") {
                LabeledContent("Customer") {
                    Button(form.customer?.name ?? "Choose") {
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
                    .frame(minHeight: 80)
            }

            if !isNew {
                Section {
                    Toggle("Done", isOn: $form.isDone)
                }
                Section {
                    Button("Delete job", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "New job" : "Job")
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { trySave() }
                    .disabled(form.customer == nil || !form.endIsValid)
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
            Button("Yes") { save() }
            Button("No", role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
        // On the Mac the list's right-click menu can change these while this
        // form is open; keep the form in step so Save does not undo them.
        .onChange(of: job?.isDone) { _, newValue in
            if let newValue { form.isDone = newValue }
        }
        .onChange(of: job?.isPaid) { _, newValue in
            if let newValue { form.isPaid = newValue }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
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

    private func save() {
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
        saved.toggle()
        onSaved?(target)
        dismiss()
    }

    private func delete() {
        if let job {
            job.remove(from: context)
        }
        dismiss()
    }
}

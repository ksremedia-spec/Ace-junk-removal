import SwiftData
import SwiftUI

/// Add a job (presented as a sheet) or edit one (pushed from a list).
struct JobEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let job: Job?
    @State private var form: JobFormData
    @State private var showingCustomerPicker = false
    @State private var confirmDelete = false
    @State private var saved = false

    private var isNew: Bool { job == nil }

    init(job: Job?, prefill: JobFormData? = nil) {
        self.job = job
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
                Button("Save") { save() }
                    .disabled(form.customer == nil)
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
        .sensoryFeedback(.success, trigger: saved)
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
        saved.toggle()
        dismiss()
    }

    private func delete() {
        if let job {
            context.delete(job)
            try? context.save()
        }
        dismiss()
    }
}

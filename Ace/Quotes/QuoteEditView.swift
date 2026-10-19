import SwiftData
import SwiftUI

/// Add a quote (presented as a sheet) or see and change one (pushed from the
/// list on iPhone, the detail column on the Mac). An existing quote also has
/// Book Job and Mark Lost, or Reopen, and Delete Quote.
struct QuoteEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let quote: Quote?
    /// Called with the quote after Save, before the form closes.
    var onSaved: ((Quote) -> Void)? = nil
    /// On the Mac the parent clears its selection; on iPhone this screen pops.
    var onDeleted: (() -> Void)? = nil

    @State private var form: QuoteFormData
    @State private var showingCustomerPicker = false
    @State private var showingBookJob = false
    @State private var confirmDelete = false
    /// "Quote marked lost." and the like, shown under the buttons for a moment.
    @State private var confirmation: String?
    @State private var saved = 0

    private var isNew: Bool { quote == nil }

    init(quote: Quote?, onSaved: ((Quote) -> Void)? = nil, onDeleted: (() -> Void)? = nil) {
        self.quote = quote
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _form = State(initialValue: QuoteFormData(quote: quote))
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
                        LabeledContent("Phone") {
                            if let url = customer.phoneURL {
                                Link(customer.phone, destination: url)
                            } else {
                                Text(customer.phone)
                            }
                        }
                    }
                    if !customer.address.isEmpty {
                        LabeledContent("Address", value: customer.address)
                    }
                }
            }

            Section("Quote") {
                Picker("Type", selection: $form.jobType) {
                    ForEach(JobType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                TextField("What", text: $form.details, prompt: Text("What was quoted, e.g. garage cleanout"), axis: .vertical)
                TextField("Price", text: $form.priceText, prompt: Text("Price in dollars"))
                    .decimalKeyboard()
                DatePicker("Quoted", selection: $form.quotedOn, displayedComponents: .date)
                Toggle("Follow up", isOn: $form.hasFollowUp)
                if form.hasFollowUp {
                    DatePicker("Follow up on", selection: $form.followUpOn, displayedComponents: .date)
                }
            }

            Section("Notes") {
                TextEditor(text: $form.notes)
                    .frame(minHeight: 80)
            }

            if let quote {
                statusSection(quote)
                Section {
                    Button("Delete Quote", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(isNew ? "New quote" : "Quote")
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
        .sheet(isPresented: $showingBookJob) {
            NavigationStack {
                JobEditView(job: nil, prefill: form.newJobForm, onSaved: { job in
                    booked(with: job)
                })
            }
        }
        .confirmationDialog("Delete this quote?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        }
        .sensoryFeedback(.success, trigger: saved)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    /// Where the quote stands and what can be done with it next.
    private func statusSection(_ quote: Quote) -> some View {
        Section {
            LabeledContent("Status", value: quote.status.rawValue)
            switch quote.status {
            case .open:
                Button("Book Job") {
                    showingBookJob = true
                }
                Button("Mark Lost") {
                    markLost(quote)
                }
            case .booked:
                if let job = quote.job {
                    NavigationLink {
                        JobEditView(job: job)
                    } label: {
                        JobRow(job: job)
                    }
                }
                Button("Reopen") {
                    reopen(quote)
                }
            case .lost:
                Button("Reopen") {
                    reopen(quote)
                }
            }
        } footer: {
            if let confirmation {
                Text(confirmation)
            }
        }
    }

    // MARK: Actions

    private func save() {
        let target: Quote
        if let quote {
            target = quote
        } else {
            target = Quote()
            context.insert(target)
        }
        // Set after the insert, so the customer link is made on a stored record.
        form.apply(to: target)
        try? context.save()
        saved += 1
        confirm("Quote saved.")
        onSaved?(target)
        dismiss()
    }

    private func markLost(_ quote: Quote) {
        quote.markLost()
        try? context.save()
        saved += 1
        confirm("Quote marked lost.")
    }

    private func reopen(_ quote: Quote) {
        quote.reopen()
        try? context.save()
        saved += 1
        confirm("Quote reopened.")
    }

    /// The New Job form was saved. Any edits made here before Book Job go
    /// into the quote too, so it matches what was booked. The New Job form
    /// gives its own success haptic.
    private func booked(with job: Job) {
        guard let quote else { return }
        if form.customer == nil { form.customer = job.customer }
        form.apply(to: quote)
        quote.markBooked(with: job)
        try? context.save()
        confirm("Job saved.")
    }

    private func delete() {
        guard let quote else { return }
        // The Mac clears its selection first, so nothing shows a deleted quote.
        onDeleted?()
        context.delete(quote)
        try? context.save()
        if onDeleted == nil { dismiss() }
    }

    /// Shows the confirmation under the buttons, then clears it.
    private func confirm(_ text: String) {
        confirmation = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if confirmation == text { confirmation = nil }
        }
    }
}

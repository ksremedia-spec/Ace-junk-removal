import SwiftData
import SwiftUI

/// Add a quote (presented as a sheet) or see and change one (pushed from the
/// list on iPhone, the detail column on the Mac). An existing quote also has
/// Book Job and Mark Lost, or Reopen, and Delete Quote.
struct QuoteEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let quote: Quote?
    /// Called with the quote after Save, before the form closes.
    var onSaved: ((Quote) -> Void)? = nil
    /// On the Mac the parent clears its selection; on iPhone this screen pops.
    var onDeleted: (() -> Void)? = nil

    @State private var form: QuoteFormData
    /// The form as opened or last saved, to tell whether anything changed.
    @State private var original: QuoteFormData
    @State private var confirmLost = false
    @State private var showingCustomerPicker = false
    @State private var showingBookJob = false
    @State private var confirmDelete = false
    /// "Quote marked lost." and the like, shown under the buttons for a moment.
    @State private var confirmation: String?
    @State private var saved = 0
    /// Set first when the quote is deleted, so the page closing does not
    /// write onto it (Oct 20 phone audit).
    @State private var deleted = false
    @State private var confirmDiscard = false
    @State private var confirmReopen = false

    private var isNew: Bool { quote == nil }

    init(quote: Quote?, onSaved: ((Quote) -> Void)? = nil, onDeleted: (() -> Void)? = nil) {
        self.quote = quote
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _form = State(initialValue: QuoteFormData(quote: quote))
        _original = State(initialValue: QuoteFormData(quote: quote))
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
                LabeledContent("Price") {
                    TextField("Price", text: $form.priceText, prompt: Text("$0"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
                DatePicker("Quoted", selection: $form.quotedOn, displayedComponents: .date)
                if QuoteFeatures.followUps {
                    Toggle("Follow up", isOn: $form.hasFollowUp)
                    if form.hasFollowUp {
                        DatePicker("Follow up on", selection: $form.followUpOn, displayedComponents: .date)
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: $form.notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
            }

            if let quote {
                statusSection(quote)
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete quote", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .readableWidth()
        .navigationTitle(isNew ? "New quote" : "Quote")
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmDiscard = true } else { dismiss() }
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(form.customer == nil || (!isNew && !hasChanges))
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
        .confirmationDialog("Reopen this quote?", isPresented: $confirmReopen, titleVisibility: .visible) {
            Button("Reopen") { if let quote { reopen(quote) } }
        } message: {
            if let job = quote?.job {
                Text("The job on \(Dates.shortDay(job.scheduledAt)) stays on the schedule.")
            }
        }
        .confirmationDialog("Mark this quote lost?", isPresented: $confirmLost, titleVisibility: .visible) {
            Button("Mark lost") { if let quote { markLost(quote) } }
        } message: {
            Text("It leaves the Quotes list. Search still finds it, and Reopen brings it back.")
        }
        .interactiveDismissDisabled(isNew && hasChanges)
        .confirmationDialog("Discard this quote?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Clicking another quote kept nothing before; now changes are saved.
        .onDisappear {
            if !deleted, let quote, hasChanges, form.customer != nil {
                form.apply(to: quote)
                try? context.save()
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    // MARK: Header

    /// Built from the form, so it follows changes before Save. Book job and
    /// Mark lost, or Reopen, act straight away.
    private var header: some View {
        DetailHeader(
            title: form.customer?.name ?? (isNew ? "New quote" : "No customer"),
            subtitle: form.jobType.rawValue + " · quoted " + Dates.shortDay(form.quotedOn),
            caption: form.details.isEmpty ? nil : form.details,
            value: Parse.money(form.priceText).map(Money.text) ?? "No price",
            valueTint: Parse.money(form.priceText) == nil ? .secondary : .primary,
            hasActions: quote != nil
        ) {
            TypeBadge(type: form.jobType, size: 52, muted: (quote?.status ?? .open) != .open)
        } pills: {
            if let quote, quote.status != .open {
                StatusPill(text: quote.status.rawValue, tint: quote.status.tint)
            }
        } actions: {
            if let quote {
                switch quote.status {
                case .open:
                    Button {
                        showingBookJob = true
                    } label: {
                        Label("Book job", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.action(.accentColor, prominent: true))
                    Button {
                        confirmLost = true
                    } label: {
                        Label("Mark lost", systemImage: "xmark")
                    }
                    .buttonStyle(.action(.secondary))
                case .booked, .lost:
                    Button {
                        // A booked quote's job stays on the schedule: say so,
                        // so booking it again does not make a second job.
                        if quote.job != nil { confirmReopen = true } else { reopen(quote) }
                    } label: {
                        Label("Reopen", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.action())
                }
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

    /// The job a booked quote became, and the last action's confirmation.
    private func statusSection(_ quote: Quote) -> some View {
        Section {
            if quote.status == .booked, let job = quote.job {
                NavigationLink {
                    JobEditView(job: job)
                } label: {
                    JobRow(job: job)
                }
            }
        } header: {
            if quote.status == .booked, quote.job != nil {
                Text("Booked job")
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
        original = form
        saved += 1
        confirm("Quote saved.")
        onSaved?(target)
        dismiss()
    }

    private var hasChanges: Bool { form != original }

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
        original = form
        confirm("Job saved.")
    }

    private func delete() {
        guard let quote else { return }
        deleted = true
        original = form
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

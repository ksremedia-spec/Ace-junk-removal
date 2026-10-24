#if os(macOS)
import AppKit
#endif
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
    /// On the Mac the page beside the list clears the parent's selection
    /// (the page is not pushed, so it cannot close itself); without it the
    /// page closes (audit Oct 24, 8 and 9; the same as quotes).
    private let onDeleted: (() -> Void)?
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
    /// Set first when the job is deleted, so nothing writes back onto it
    /// as the page closes (Oct 20 phone audit: a crash and a ghost event).
    @State private var deleted = false
    @State private var confirmDiscard = false
    @State private var askingEnd = false

    private var isNew: Bool { job == nil }

    /// The job, while it still exists. Nil for a new job, and once it was
    /// deleted here, by the Assistant or by another device: nothing reads
    /// or writes a deleted record.
    private var liveJob: Job? {
        guard let job, !JobActions.isGone(job) else { return nil }
        return job
    }

    /// iPhone: going Back from a job whose new time clashes with another
    /// asks the overlap question first, instead of saving quietly. An end
    /// time before the start asks too: it cannot be saved, and going Back
    /// used to drop every change without a word (audit Oct 24, 21).
    private var backNeedsQuestion: Bool {
        #if os(iOS)
        return !isNew && hasChanges && (!form.endIsValid || (timingChanged && !overlapping.isEmpty))
        #else
        return false
        #endif
    }

    init(job: Job?, prefill: JobFormData? = nil, onSaved: ((Job) -> Void)? = nil, onDeleted: (() -> Void)? = nil) {
        self.job = job
        self.onSaved = onSaved
        self.onDeleted = onDeleted
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
                #if os(iOS)
                // A saved job's customer opens their page; changing the
                // customer is its own row, so a stray tap never moves the job.
                if !isNew, let customer = form.customer {
                    NavigationLink {
                        CustomerDetailView(customer: customer)
                    } label: {
                        LabeledContent("Customer", value: customer.name)
                    }
                    Button("Change customer") { showingCustomerPicker = true }
                } else {
                    LabeledContent("Customer") {
                        Button(form.customer?.name ?? "Choose…") {
                            showingCustomerPicker = true
                        }
                    }
                }
                #else
                LabeledContent("Customer") {
                    Button(form.customer?.name ?? "Choose…") {
                        showingCustomerPicker = true
                    }
                }
                #endif
                if let customer = form.customer {
                    // Tap to call or get directions; long press to copy.
                    if !customer.phone.isEmpty {
                        LabeledContent("Phone") {
                            if let url = customer.phoneURL {
                                Link(customer.phone, destination: url)
                            } else {
                                Text(customer.phone)
                            }
                        }
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(customer.phone) }
                        }
                    }
                    if !customer.address.isEmpty {
                        LabeledContent("Address") {
                            if let url = customer.directionsURL {
                                Link(customer.address, destination: url)
                                    .multilineTextAlignment(.trailing)
                            } else {
                                Text(customer.address)
                            }
                        }
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(customer.address) }
                        }
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
                // Labelled on the iPhone too, where a form hides a text box's
                // own label and "300" alone said nothing.
                LabeledContent("Price") {
                    TextField("Price", text: $form.priceText, prompt: Text("$0"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
                Picker("Payment", selection: $form.paymentType) {
                    ForEach(PaymentType.allCases) { type in
                        Label(type.rawValue, systemImage: type.symbol).tag(type)
                    }
                }
                // A saved job has Mark paid in its header, which saves at
                // once; a second switch here could disagree with it.
                if isNew {
                    Toggle("Paid", isOn: $form.isPaid)
                }
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
                    Button("Cancel") {
                        if hasChanges { confirmDiscard = true } else { dismiss() }
                    }
                }
            }
            #if os(iOS)
            if backNeedsQuestion {
                ToolbarItem(placement: .navigation) {
                    // Save anyway saves and closes; Change the time stays.
                    Button {
                        goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
            }
            #endif
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
        .alert("Remove the end time?", isPresented: $askingEnd) {
            Button("Remove end time") { removeEndAndSave() }
            Button("Change the time", role: .cancel) {}
        } message: {
            Text("It is before the start time.")
        }
        // A half-typed booking is not thrown away by a brush of the sheet;
        // Cancel asks first (Oct 20 phone audit).
        .interactiveDismissDisabled(isNew && hasChanges)
        .confirmationDialog("Discard this job?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        #if os(iOS)
        .navigationBarBackButtonHidden(backNeedsQuestion)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: form.hasTime) { _, on in
            // Turning on a time for a job that had none starts at the next
            // full hour, not midnight.
            guard on, form.date == Calendar.current.startOfDay(for: form.date) else { return }
            form.date = JobTimes.combine(day: form.date, time: Dates.nextFullHour())
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
        // On the Mac the list's right-click menu can change these while this
        // form is open; keep the form in step so Save does not undo them.
        // Changed elsewhere while open (the Mac list's menu, another device
        // by sync): untouched fields follow, typed ones are kept, so Save
        // never undoes the other change (audit Oct 21, M8).
        .onChange(of: liveJob?.updatedAt) { _, _ in
            guard !deleted, let job = liveJob else { return }
            let fresh = JobFormData(job: job)
            form = form.merging(fresh: fresh, base: original)
            original = fresh
        }
        // Deleted elsewhere while open (the Assistant, another device by
        // sync): the page closes, and nothing typed is written to it.
        .onChange(of: jobs.count) { _, _ in
            guard !deleted, let job, JobActions.isGone(job) else { return }
            deleted = true
            original = form
            if let onDeleted { onDeleted() } else { dismiss() }
        }
        // Its customer was deleted (from the customer page opened here): the
        // page stops showing them (audit Oct 24, 68).
        .onChange(of: liveJob?.customer?.persistentModelID) { _, _ in refreshCustomer() }
        .onAppear { refreshCustomer() }
        // On the Mac this page sits beside the list: clicking another job
        // used to throw away unsaved changes without a word. Like Mail and
        // Notes, they are kept instead (Oct 20 audit).
        .onDisappear { saveOnLeave() }
        #if os(macOS)
        // Quitting does not close the page first, so it saves here too
        // (audit Oct 24, 34).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveOnLeave()
        }
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    /// Keeps what was typed when the page closes without Save. An end time
    /// before the start cannot be saved, so only it is dropped; a job with
    /// no customer keeps its other changes too (audit Oct 24, 21).
    private func saveOnLeave() {
        guard !deleted, !isNew, hasChanges, liveJob != nil else { return }
        if !form.endIsValid { form.hasEnd = false }
        persist()
    }

    /// iPhone Back while a question is due: the end time first, then the
    /// overlap.
    private func goBack() {
        if !form.endIsValid {
            flagged += 1
            askingEnd = true
        } else {
            trySave()
        }
    }

    private func removeEndAndSave() {
        form.hasEnd = false
        // The overlap question, if any, waits for this alert to close.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { trySave() }
    }

    /// A customer deleted while this page was open is no longer shown or
    /// read; a customer chosen here and not saved yet is kept.
    private func refreshCustomer() {
        guard !deleted, let job = liveJob else { return }
        let current = job.customer.flatMap { Self.isGone($0) ? nil : $0 }
        let untouched = form.customer == original.customer
        if untouched || form.customer.map(Self.isGone) == true { form.customer = current }
        if untouched || original.customer.map(Self.isGone) == true { original.customer = current }
    }

    private static func isGone(_ customer: Customer) -> Bool {
        customer.modelContext == nil || customer.isDeleted
    }

    // MARK: Header

    /// Built from the form, so it follows every change before Save.
    private var header: some View {
        DetailHeader(
            title: form.customer?.name ?? (isNew ? "New job" : "No customer"),
            subtitle: whenText,
            caption: siteAddress,
            value: Parse.money(form.priceText).map(Money.text),
            valueTint: (liveJob?.isPaid ?? form.isPaid) ? .secondary : .primary,
            hasActions: liveJob != nil || form.customer?.phoneURL != nil || directionsURL != nil
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
            if let job = liveJob {
                Button {
                    setDone(!job.isDone, on: job)
                } label: {
                    Label(job.isDone ? "Done" : "Mark done", systemImage: job.isDone ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(.action(job.isDone ? Tint.paid : .accentColor, prominent: job.isDone))
                .help(job.isDone ? "Done. Click to mark it not done." : "Mark this job done")
                Button {
                    setPaid(!job.isPaid, on: job)
                } label: {
                    Label(job.isPaid ? "Paid" : "Mark paid", systemImage: job.isPaid ? "dollarsign.circle.fill" : "dollarsign.circle")
                }
                .buttonStyle(.action(job.isPaid ? Tint.paid : .accentColor, prominent: job.isPaid))
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
            if let url = directionsURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Directions", systemImage: "map.fill")
                }
                .buttonStyle(.action())
            }
        }
    }

    /// Where the work is: a "Job address: …" first line in the notes (a job
    /// said at another address), else the customer's address on file
    /// (audit Oct 24, 39).
    private var siteAddress: String? {
        JobSite.address(notes: form.notes, customer: form.customer)
    }

    private var directionsURL: URL? {
        siteAddress.flatMap(Maps.directions)
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
        JobActions.shared.setDone(done, job, in: context)
    }

    private func setPaid(_ paid: Bool, on job: Job) {
        JobActions.shared.setPaid(paid, job, in: context)
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
        guard !JobActions.isGone(job) else { return false }
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
        if let job, JobActions.isGone(job) { return }
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
        form.apply(to: target, changedSince: job == nil ? nil : original)
        try? context.save()
        CalendarStore.shared.jobSaved(target)
        form = JobFormData(job: target)
        original = form
        return target
    }

    private func delete() {
        deleted = true
        original = form
        guard let job else { return dismiss() }
        // The Undo bar and the payment question let go of it first.
        JobActions.shared.forget(job)
        // The Mac clears its selection first, so nothing shows a deleted job.
        onDeleted?()
        if !JobActions.isGone(job) { job.remove(from: context) }
        if onDeleted == nil { dismiss() }
    }
}

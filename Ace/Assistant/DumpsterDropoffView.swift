import SwiftData
import SwiftUI

/// "Dropped 4 at Pereira's, 7 Bay Road, 450, two tons, back next Friday."
/// The drop-off form filled in from the note: which dumpster, who, where,
/// when it is due back, the price and the agreed weight. Marks the dumpster
/// out the same way the dumpster screen does.
struct DumpsterDropoffView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]

    let draft: JobDraft
    let dumpsters: [Dumpster]
    /// Called with the confirmation, e.g. "Dumpster 3 dropped off."
    var onSaved: (String) -> Void
    var onStartOver: () -> Void

    @State private var selectedNumber: Int
    @State private var customer: Customer?
    @State private var name: String
    @State private var phone: String
    @State private var location: String
    @State private var dropOffDate = Dates.startOfToday()
    @State private var dueBackDate: Date
    @State private var priceText: String
    @State private var agreedTonsText: String
    @State private var notes: String
    @State private var showingCustomerPicker = false
    @State private var markJobDone = true
    @State private var saved = false
    @State private var flagged = 0

    private let flags: AssistantFlags

    /// `refCustomer` is the customer the note's reference pointed at; it wins
    /// over matching the spoken name.
    init(draft: JobDraft, customers: [Customer], dumpsters: [Dumpster], refCustomer: Customer? = nil,
         onSaved: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.draft = draft
        self.dumpsters = dumpsters
        self.onSaved = onSaved
        self.onStartOver = onStartOver

        let inYard = matchDumpster(draft, dumpsters: dumpsters, wantOut: false)
        let spokenNumber = Int(draft.dumpsterNumber.filter(\.isNumber))
        _selectedNumber = State(initialValue: inYard.first?.number ?? 0)

        let match = refCustomer ?? matchCustomers(draft, in: customers).first
        _customer = State(initialValue: match)
        _name = State(initialValue: draft.customerName.trimmingCharacters(in: .whitespaces))
        _phone = State(initialValue: PhoneFormat.formatted(draft.phone))
        let spokenAddress = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        _location = State(initialValue: spokenAddress.isEmpty ? (match?.address ?? "") : spokenAddress)

        let today = Dates.startOfToday()
        let weekOut = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        _dueBackDate = State(initialValue: JobDraft.day(from: draft.dueBack) ?? weekOut)
        _priceText = State(initialValue: draft.price)
        _agreedTonsText = State(initialValue: draft.agreedTons)
        _notes = State(initialValue: draft.notes)

        var flags = AssistantFlags(draft: draft)
        if let spokenNumber, inYard.first?.number != spokenNumber {
            flags.add("dumpsterNumber", "Dumpster \(spokenNumber) is out. Is this the right one?")
        } else if spokenNumber == nil {
            flags.add("dumpsterNumber", "No dumpster number was said.")
        }
        if match == nil && draft.customerName.trimmingCharacters(in: .whitespaces).isEmpty {
            flags.add("customerName", "No customer was said.")
        }
        if draft.dueBack.isEmpty {
            flags.add("dueBack", "No due-back day was said. A week from today?")
        }
        self.flags = flags
    }

    private var inYard: [Dumpster] {
        dumpsters.filter { !$0.isOut }.sorted { $0.number < $1.number }
    }

    private var selectedDumpster: Dumpster? {
        inYard.first { $0.number == selectedNumber }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// The booked drop-off job for this customer, today or earlier, if any.
    private var linkedJob: Job? {
        bookedJob(.dumpsterDropOff, for: customer, in: jobs)
    }

    private var canSave: Bool {
        selectedDumpster != nil && (customer != nil || !trimmedName.isEmpty)
    }

    /// Clears as soon as a customer is chosen or a name typed.
    private var customerNote: String? {
        customer == nil && trimmedName.isEmpty ? (flags["customerName"] ?? "No customer was said.") : flags["customerName"]
    }

    /// Clears as soon as a location is typed.
    private var locationNote: String? {
        location.trimmingCharacters(in: .whitespaces).isEmpty ? (flags["address"] ?? "No address was said.") : nil
    }

    var body: some View {
        Form {
            dumpsterSection
            customerSection
            rentalSection
            linkedJobSection
            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Mark Dropped Off") { markDroppedOff() }
                    .disabled(!canSave)
            }
        }
        .sheet(isPresented: $showingCustomerPicker) {
            NavigationStack {
                CustomerPickerView(selection: $customer)
            }
        }
        .onChange(of: customer) { _, chosen in
            if let chosen, location.trimmingCharacters(in: .whitespaces).isEmpty {
                location = chosen.address
            }
        }
        .onAppear {
            if !flags.isEmpty || locationNote != nil { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private var dumpsterSection: some View {
        Section("Dumpster") {
            if inYard.isEmpty {
                Text("Every dumpster is out. Nothing to drop off.")
                    .foregroundStyle(.secondary)
            } else {
                FlaggedRow(flags["dumpsterNumber"]) {
                    Picker("Dumpster", selection: $selectedNumber) {
                        ForEach(inYard) { dumpster in
                            Text(dumpster.displayName).tag(dumpster.number)
                        }
                    }
                }
                if let note = selectedDumpster?.conditionNote, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var linkedJobSection: some View {
        if let linkedJob {
            Section {
                Toggle("Also mark the booked drop-off job done", isOn: $markJobDone)
            } footer: {
                Text(linkedJob.jobType.rawValue + ", " + linkedJob.whenText)
            }
        }
    }

    private var customerSection: some View {
        Section {
            if let customer {
                LabeledContent("Customer", value: customer.name)
                if !customer.phone.isEmpty {
                    LabeledContent("Phone", value: customer.phone)
                }
                Button("Choose a different customer") { showingCustomerPicker = true }
            } else {
                FlaggedRow(customerNote) {
                    TextField("Name", text: $name)
                }
                FlaggedRow(flags["phone"]) {
                    TextField("Phone", text: $phone)
                        .phoneKeyboard()
                }
                Button("Choose an existing customer") { showingCustomerPicker = true }
            }
        } header: {
            Text("Customer")
        } footer: {
            if customer == nil {
                Text("A new customer is added on save.")
            }
        }
    }

    private var rentalSection: some View {
        Section("Drop-off") {
            FlaggedRow(locationNote) {
                TextField("Location", text: $location, axis: .vertical)
            }
            DatePicker("Drop-off", selection: $dropOffDate, displayedComponents: .date)
            FlaggedRow(flags["dueBack"]) {
                DatePicker("Due back", selection: $dueBackDate, displayedComponents: .date)
            }
            FlaggedRow(flags["price"]) {
                TextField("Price", text: $priceText, prompt: Text("Price in dollars"))
                    .decimalKeyboard()
            }
            FlaggedRow(flags["agreedTons"]) {
                TextField("Agreed weight", text: $agreedTonsText, prompt: Text("Agreed weight in tons"))
                    .decimalKeyboard()
            }
            TextField("Notes", text: $notes, axis: .vertical)
        }
    }

    private func markDroppedOff() {
        guard let dumpster = selectedDumpster else { return }
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let linked = markJobDone ? linkedJob : nil

        let who: Customer
        if let customer {
            who = customer
            let digits = phone.filter(\.isNumber)
            if who.phone.isEmpty, !digits.isEmpty { who.phone = PhoneFormat.formatted(phone) }
            if who.address.isEmpty { who.address = trimmedLocation }
            who.updatedAt = Date()
        } else {
            who = Customer(
                name: trimmedName.isEmpty ? "Unknown customer" : trimmedName,
                phone: PhoneFormat.formatted(phone),
                address: trimmedLocation
            )
            context.insert(who)
        }

        dumpster.dropOff(
            to: who,
            location: trimmedLocation,
            on: dropOffDate,
            dueBack: dueBackDate,
            price: Parse.money(priceText),
            agreedWeightTons: Parse.tons(agreedTonsText),
            notes: notes
        )
        if let linked {
            linked.isDone = true
            linked.updatedAt = Date()
        }
        try? context.save()
        if let linked {
            CalendarStore.shared.jobSaved(linked)
        }
        saved.toggle()
        onSaved("Dumpster \(dumpster.number) dropped off.")
    }
}

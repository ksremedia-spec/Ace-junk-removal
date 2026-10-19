import SwiftData
import SwiftUI

// The Assistant's customer screens: add a customer, change a customer's
// details, and call, text or get directions to a customer.

// MARK: - New customer

/// "Add Dave Macomber, 774 555 0171, 88 Plymouth St." A customer without a
/// job. Warns when the phone number is already on file for someone.
struct NewCustomerView: View {
    @Environment(\.modelContext) private var context

    let customers: [Customer]
    private let flags: AssistantFlags
    var onFinish: (String) -> Void
    var onStartOver: () -> Void

    @State private var name: String
    @State private var phone: String
    @State private var address: String
    @State private var notes: String
    @State private var saved = false
    @State private var flagged = 0

    init(action: AssistantAction, issues: [PlanIssue], customers: [Customer],
         onFinish: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.customers = customers
        self.flags = AssistantFlags(issues: issues)
        self.onFinish = onFinish
        self.onStartOver = onStartOver
        _name = State(initialValue: action.customerName.trimmingCharacters(in: .whitespaces))
        _phone = State(initialValue: PhoneFormat.formatted(action.phone))
        _address = State(initialValue: action.address)
        _notes = State(initialValue: action.note)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// Someone already on file with this phone number.
    private var samePhone: Customer? {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        return customers.first { $0.phoneDigits == digits }
    }

    private var nameNote: String? {
        trimmedName.isEmpty ? (flags["customerName"] ?? "No name was said.") : flags["customerName"]
    }

    private var phoneNote: String? {
        if let samePhone { return "\(samePhone.name) already has this number." }
        return flags["phone"]
    }

    var body: some View {
        Form {
            Section("Customer") {
                FlaggedRow(nameNote) {
                    TextField("Name", text: $name)
                }
                FlaggedRow(phoneNote) {
                    TextField("Phone", text: $phone)
                        .phoneKeyboard()
                }
                FlaggedRow(flags["address"]) {
                    TextField("Address", text: $address, axis: .vertical)
                }
            }
            Section("Notes") {
                FlaggedRow(flags["note"]) {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear {
            if !flags.isEmpty || nameNote != nil || phoneNote != nil { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private func save() {
        let customer = Customer(
            name: trimmedName,
            phone: PhoneFormat.formatted(phone),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(customer)
        try? context.save()
        saved.toggle()
        onFinish("Customer saved.")
    }
}

// MARK: - Update a customer

/// "Linda Johnson's new number is 508 555 0199", "Keane's gate code is
/// 4412". Finds the customer, then shows the changes to confirm.
struct UpdateCustomerView: View {
    let action: AssistantAction
    let issues: [PlanIssue]
    let candidates: [Customer]
    /// Everyone, to warn about a phone number already on file.
    let customers: [Customer]
    let subject: String
    var onFinish: (String) -> Void
    var onSkip: () -> Void
    var onStartOver: () -> Void

    @State private var picked: Customer?

    private var customer: Customer? {
        if let picked { return picked }
        return candidates.count == 1 ? candidates.first : nil
    }

    var body: some View {
        if let customer {
            UpdateCustomerForm(
                customer: customer,
                action: action,
                issues: issues,
                customers: customers,
                onFinish: onFinish,
                onStartOver: onStartOver
            )
        } else if candidates.isEmpty {
            NothingFoundView(message: "No customer found for \(subject).", onSkip: onSkip, onStartOver: onStartOver)
        } else {
            WhichCustomerList(customers: candidates, onPick: { picked = $0 }, onStartOver: onStartOver)
        }
    }
}

private struct UpdateCustomerForm: View {
    @Environment(\.modelContext) private var context

    let customer: Customer
    let customers: [Customer]
    private let flags: AssistantFlags
    var onFinish: (String) -> Void
    var onStartOver: () -> Void

    @State private var name: String
    @State private var phone: String
    @State private var address: String
    @State private var noteToAdd: String
    @State private var saved = false
    @State private var flagged = 0

    init(customer: Customer, action: AssistantAction, issues: [PlanIssue], customers: [Customer],
         onFinish: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.customer = customer
        self.customers = customers
        self.onFinish = onFinish
        self.onStartOver = onStartOver

        let newName = action.newName.trimmingCharacters(in: .whitespaces)
        let newPhone = action.newPhone.trimmingCharacters(in: .whitespaces)
        let newAddress = action.newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = action.note.trimmingCharacters(in: .whitespacesAndNewlines)
        _name = State(initialValue: newName.isEmpty ? customer.name : newName)
        _phone = State(initialValue: newPhone.isEmpty ? customer.phone : PhoneFormat.formatted(newPhone))
        _address = State(initialValue: newAddress.isEmpty ? customer.address : newAddress)
        _noteToAdd = State(initialValue: note)

        var flags = AssistantFlags(issues: issues)
        if newName.isEmpty && newPhone.isEmpty && newAddress.isEmpty && note.isEmpty {
            flags.add("note", "No change was heard.")
        }
        self.flags = flags
    }

    /// Someone else already on file with the new phone number.
    private var phoneNote: String? {
        let digits = phone.filter(\.isNumber)
        if digits.count >= 7, digits != customer.phoneDigits,
           let other = customers.first(where: { $0.phoneDigits == digits && $0.persistentModelID != customer.persistentModelID }) {
            return "\(other.name) already has this number."
        }
        return flags["newPhone"]
    }

    var body: some View {
        Form {
            currentSection
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
            if !flags.isEmpty || phoneNote != nil { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private var currentSection: some View {
        Section("Customer") {
            FlaggedRow(flags["ref"]) {
                LabeledContent("Customer", value: customer.name)
            }
            if !customer.phone.isEmpty {
                LabeledContent("Phone", value: customer.phone)
            }
            if !customer.address.isEmpty {
                LabeledContent("Address") {
                    Text(customer.address)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var changesSection: some View {
        Section("Changes") {
            FlaggedRow(flags["newName"]) {
                TextField("Name", text: $name)
            }
            FlaggedRow(phoneNote) {
                TextField("Phone", text: $phone)
                    .phoneKeyboard()
            }
            FlaggedRow(flags["newAddress"]) {
                TextField("Address", text: $address, axis: .vertical)
            }
        }
    }

    private var notesSection: some View {
        Section {
            FlaggedRow(flags["note"]) {
                TextField("Add a note", text: $noteToAdd, axis: .vertical)
            }
        } header: {
            Text("Notes")
        } footer: {
            if !customer.notes.isEmpty {
                Text("Added under the customer's notes: " + customer.notes)
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty { customer.name = trimmedName }
        customer.phone = PhoneFormat.formatted(phone)
        customer.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = noteToAdd.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            customer.notes = customer.notes.isEmpty ? note : customer.notes + "\n" + note
        }
        customer.updatedAt = Date()
        try? context.save()
        saved.toggle()
        onFinish("Customer saved.")
    }
}

// MARK: - Contact a customer

/// "Call Johnson", "Text Johnson we're 15 minutes out", "Directions to the
/// next job". The customer with Call, Message and Directions buttons; the
/// one asked for comes first and stands out. Nothing is saved.
struct ContactCustomerView: View {
    let action: AssistantAction
    let issues: [PlanIssue]
    let candidates: [Customer]
    let subject: String
    var onFinish: (String) -> Void
    var onSkip: () -> Void
    var onStartOver: () -> Void

    @State private var picked: Customer?

    private var customer: Customer? {
        if let picked { return picked }
        return candidates.count == 1 ? candidates.first : nil
    }

    var body: some View {
        if let customer {
            ContactCustomerForm(
                customer: customer,
                action: action,
                issues: issues,
                onDone: { onFinish("") },
                onStartOver: onStartOver
            )
        } else if candidates.isEmpty {
            NothingFoundView(message: "No customer found for \(subject).", onSkip: onSkip, onStartOver: onStartOver)
        } else {
            WhichCustomerList(customers: candidates, onPick: { picked = $0 }, onStartOver: onStartOver)
        }
    }
}

private struct ContactCustomerForm: View {
    enum Way: String, CaseIterable {
        case call, text, directions

        var title: String {
            switch self {
            case .call: return "Call"
            case .text: return "Message"
            case .directions: return "Directions"
            }
        }

        var symbol: String {
            switch self {
            case .call: return "phone.fill"
            case .text: return "message.fill"
            case .directions: return "map.fill"
            }
        }
    }

    let customer: Customer
    private let asked: Way
    private let flags: AssistantFlags
    var onDone: () -> Void
    var onStartOver: () -> Void

    @State private var message: String
    @State private var flagged = 0

    init(customer: Customer, action: AssistantAction, issues: [PlanIssue],
         onDone: @escaping () -> Void, onStartOver: @escaping () -> Void) {
        self.customer = customer
        self.onDone = onDone
        self.onStartOver = onStartOver
        let asked = Way(rawValue: action.contact) ?? (action.message.isEmpty ? .call : .text)
        self.asked = asked
        _message = State(initialValue: action.message)

        var flags = AssistantFlags(issues: issues)
        if asked != .directions && customer.phoneDigits.isEmpty {
            flags.add("phone", "No phone number on file.")
        }
        if asked == .directions && customer.address.isEmpty {
            flags.add("address", "No address on file.")
        }
        self.flags = flags
    }

    /// The asked-for way first, then the other two.
    private var others: [Way] {
        Way.allCases.filter { $0 != asked }
    }

    var body: some View {
        Form {
            customerSection
            if asked == .text || !message.isEmpty {
                Section("Message") {
                    TextField("Message", text: $message, axis: .vertical)
                }
            }
            linksSection
            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onDone() }
            }
        }
        .onAppear {
            if !flags.isEmpty { flagged += 1 }
        }
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private var customerSection: some View {
        Section("Customer") {
            FlaggedRow(flags["ref"]) {
                LabeledContent("Customer", value: customer.name)
            }
            FlaggedRow(flags["phone"]) {
                LabeledContent("Phone", value: customer.phone.isEmpty ? "None" : customer.phone)
            }
            FlaggedRow(flags["address"]) {
                LabeledContent("Address") {
                    Text(customer.address.isEmpty ? "None" : customer.address)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    /// The asked-for way on its own, prominent; the other two below it.
    @ViewBuilder
    private var linksSection: some View {
        Section {
            ContactLink(way: asked, url: url(for: asked), prominent: true)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        Section {
            ForEach(others, id: \.self) { way in
                ContactLink(way: way, url: url(for: way))
            }
        }
    }

    /// tel:, sms: with the message as the body, or an Apple Maps search.
    /// Nil when the phone number or address is missing.
    private func url(for way: Way) -> URL? {
        switch way {
        case .call:
            return customer.phoneURL
        case .text:
            let digits = customer.phoneDigits
            guard !digits.isEmpty else { return nil }
            let body = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty,
                  let encoded = body.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
                return URL(string: "sms:\(digits)")
            }
            return URL(string: "sms:\(digits)&body=\(encoded)")
        case .directions:
            return customer.directionsURL
        }
    }
}

/// One way to reach the customer: a link that opens the phone, Messages or
/// Maps, or a dimmed label when there is nothing to open. The prominent one
/// spans the row.
private struct ContactLink: View {
    let way: ContactCustomerForm.Way
    let url: URL?
    var prominent = false

    var body: some View {
        if let url {
            Link(destination: url) {
                Label(way.title, systemImage: way.symbol)
                    .frame(maxWidth: prominent ? .infinity : nil)
            }
        } else {
            Label(way.title, systemImage: way.symbol)
                .foregroundStyle(.secondary)
        }
    }
}

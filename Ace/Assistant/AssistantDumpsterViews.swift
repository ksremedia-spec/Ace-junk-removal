import SwiftData
import SwiftUI

// The Assistant's dumpster screens beyond pickup and drop-off: a swap, a
// change to a rental that is out, and a note about the dumpster itself.

// MARK: - Overweight rows

/// "Over by 1.1 tons · Overweight charge $138", or "Within the agreed
/// weight." Same rows as the dumpster screen and the pickup.
struct OverweightRows: View {
    let actualTons: Double?
    let agreedTons: Double?
    let charge: Double

    var body: some View {
        if let actualTons, let agreedTons {
            if actualTons > agreedTons {
                LabeledContent("Over by", value: Tons.text(actualTons - agreedTons))
                LabeledContent("Overweight charge") {
                    Text(Money.text(charge))
                        .foregroundStyle(Tint.warning)
                }
            } else {
                Text("Within the agreed weight. No extra charge.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Swap

/// "Swapped 2 at Keane's, 3.1 tons, left 5." Takes the full dumpster away
/// (weighed, with the overweight charge) and leaves an empty one from the
/// yard at the same customer and place, in one screen.
struct DumpsterSwapView: View {
    let action: AssistantAction
    let issues: [PlanIssue]
    /// The out dumpsters the note could mean.
    let candidates: [Dumpster]
    /// Every dumpster, for the one to leave.
    let dumpsters: [Dumpster]
    let notFoundMessage: String
    var onFinish: (String) -> Void
    var onSkip: () -> Void
    var onStartOver: () -> Void

    @State private var picked: Dumpster?

    private var dumpster: Dumpster? {
        if let picked { return picked }
        return candidates.count == 1 ? candidates.first : nil
    }

    var body: some View {
        if let dumpster {
            DumpsterSwapForm(
                out: dumpster,
                action: action,
                issues: issues,
                dumpsters: dumpsters,
                onFinish: { text in
                    // Keep showing this dumpster while the next step loads,
                    // even though it is no longer out.
                    picked = dumpster
                    onFinish(text)
                },
                onStartOver: onStartOver
            )
        } else if candidates.isEmpty {
            NothingFoundView(message: notFoundMessage, onSkip: onSkip, onStartOver: onStartOver)
        } else {
            WhichDumpsterList(dumpsters: candidates, onPick: { picked = $0 }, onStartOver: onStartOver)
        }
    }
}

private struct DumpsterSwapForm: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.overweightRateKey) private var ratePerTon = AppSettings.defaultOverweightRate

    let out: Dumpster
    let dumpsters: [Dumpster]
    private let flags: AssistantFlags
    var onFinish: (String) -> Void
    var onStartOver: () -> Void

    @State private var actualTonsText: String
    @State private var leaveNumber: Int
    @State private var dueBackDate: Date
    @State private var priceText: String
    @State private var agreedTonsText: String
    @State private var notes: String
    @State private var saved = false
    @State private var flagged = 0
    /// "28 tons is more than a dumpster holds. Was it 2.8 tons?"
    @State private var askHeavy = false

    init(out: Dumpster, action: AssistantAction, issues: [PlanIssue], dumpsters: [Dumpster],
         onFinish: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.out = out
        self.dumpsters = dumpsters
        self.onFinish = onFinish
        self.onStartOver = onStartOver

        let inYard = dumpsters.filter { !$0.isOut }.sorted { $0.number < $1.number }
        let said = Int(action.otherDumpsterNumber.filter(\.isNumber))
        let saidInYard = inYard.first(where: { $0.number == said })
        // The dumpster said, or the only one in the yard; otherwise "Choose"
        // (Oct 20 phone audit: the first in the yard was picked silently).
        _leaveNumber = State(initialValue: saidInYard?.number ?? (said == nil && inYard.count == 1 ? inYard[0].number : 0))
        _actualTonsText = State(initialValue: action.actualTons)

        let today = Dates.startOfToday()
        let weekOut = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        _dueBackDate = State(initialValue: JobDraft.day(from: action.dueBack) ?? weekOut)
        // A swap carries on the same rental terms unless new ones were said.
        _priceText = State(initialValue: action.price.isEmpty ? Parse.moneyText(out.price) : action.price)
        _agreedTonsText = State(initialValue: action.agreedTons.isEmpty ? Parse.tonsText(out.agreedWeightTons) : action.agreedTons)
        let note = action.note.trimmingCharacters(in: .whitespacesAndNewlines)
        _notes = State(initialValue: [out.notes, note].filter { !$0.isEmpty }.joined(separator: "\n"))

        var flags = AssistantFlags(issues: issues)
        if let said, saidInYard == nil {
            flags.add("otherDumpsterNumber", "Dumpster \(said) is not in the yard. Is this the right one?")
        } else if said == nil, inYard.count != 1 {
            flags.add("otherDumpsterNumber", "No dumpster to leave was said. Which one went?")
        }
        if action.dueBack.isEmpty {
            flags.add("dueBack", "No due-back day was said. A week from today?")
        }
        self.flags = flags
    }

    private var inYard: [Dumpster] {
        dumpsters.filter { !$0.isOut }.sorted { $0.number < $1.number }
    }

    private var leaving: Dumpster? {
        inYard.first { $0.number == leaveNumber }
    }

    private var actualTons: Double? { Parse.tons(actualTonsText) }

    private var charge: Double {
        Overweight.charge(agreedTons: out.agreedWeightTons, actualTons: actualTons, ratePerTon: ratePerTon)
    }

    /// Clears as soon as a weight is typed in.
    private var weightNote: String? {
        actualTons == nil ? (flags["actualTons"] ?? "No weight was said.") : WeightCheck.note(for: actualTons)
    }

    var body: some View {
        Form {
            takeAwaySection
            leaveSection
            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Swap") {
                    if WeightCheck.suggestion(for: actualTons) != nil {
                        flagged += 1
                        askHeavy = true
                    } else {
                        performSwap()
                    }
                }
                .disabled(leaving == nil)
            }
        }
        .heavyWeightQuestion(isPresented: $askHeavy, tons: actualTons) { tons in
            performSwap(tons: tons)
        }
        .onAppear {
            if !flags.isEmpty || weightNote != nil { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private var takeAwaySection: some View {
        Section {
            FlaggedRow(flags["dumpsterNumber"] ?? flags["ref"]) {
                LabeledContent("Dumpster", value: out.displayName)
            }
            LabeledContent("Customer", value: out.customer?.name ?? "—")
            LabeledContent("Location") {
                Text(out.location.isEmpty ? "—" : out.location)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Agreed weight", value: out.agreedWeightTons.map { Tons.text($0) } ?? "—")
            FlaggedRow(weightNote) {
                LabeledContent("Actual weight, tons") {
                    TextField("Actual weight in tons", text: $actualTonsText, prompt: Text("e.g. 2.8"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
            }
            OverweightRows(actualTons: actualTons, agreedTons: out.agreedWeightTons, charge: charge)
        } header: {
            Text("Take away")
        } footer: {
            Text("Rate: \(Money.text(ratePerTon)) per ton over the agreed weight. Change it in Settings.")
        }
    }

    private var leaveSection: some View {
        Section("Leave") {
            if inYard.isEmpty {
                Text("No dumpster is in the yard.")
                    .foregroundStyle(.secondary)
            } else {
                FlaggedRow(flags["otherDumpsterNumber"]) {
                    Picker("Dumpster", selection: $leaveNumber) {
                        if leaveNumber == 0 {
                            Text("Choose").tag(0)
                        }
                        ForEach(inYard) { dumpster in
                            Text(dumpster.displayName).tag(dumpster.number)
                        }
                    }
                }
                if let note = leaving?.conditionNote, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Tint.warning)
                }
            }
            FlaggedRow(flags["dueBack"]) {
                DatePicker("Due back", selection: $dueBackDate, displayedComponents: .date)
            }
            FlaggedRow(flags["price"]) {
                LabeledContent("Price") {
                    TextField("Price", text: $priceText, prompt: Text("$0"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
            }
            FlaggedRow(flags["agreedTons"]) {
                LabeledContent("Agreed weight, tons") {
                    TextField("Agreed weight", text: $agreedTonsText, prompt: Text("e.g. 2"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
            }
            FlaggedRow(flags["note"]) {
                TextField("Notes", text: $notes, axis: .vertical)
            }
        }
    }

    /// `tons`: the weight chosen in the heavy-weight question, else the one
    /// typed.
    private func performSwap(tons chosen: Double? = nil) {
        guard let leaving else { return }
        // Read before the pickup, which clears them.
        let customer = out.customer
        let location = out.location
        let takenNumber = out.number

        out.markPickedUp(actualWeightTons: chosen ?? actualTons, ratePerTon: ratePerTon)
        leaving.dropOff(
            to: customer,
            location: location,
            on: Dates.startOfToday(),
            dueBack: dueBackDate,
            price: Parse.money(priceText),
            agreedWeightTons: Parse.tons(agreedTonsText),
            notes: notes
        )
        try? context.save()
        saved.toggle()
        onFinish("Dumpster \(takenNumber) swapped for Dumpster \(leaving.number).")
    }
}

// MARK: - Change a rental

/// "Harborview is keeping the dumpster till Monday." A dumpster that is
/// out: a new due-back day, price, agreed weight or place, or a note.
struct UpdateRentalView: View {
    let action: AssistantAction
    let issues: [PlanIssue]
    let candidates: [Dumpster]
    let notFoundMessage: String
    var onFinish: (String) -> Void
    var onSkip: () -> Void
    var onStartOver: () -> Void

    @State private var picked: Dumpster?

    private var dumpster: Dumpster? {
        if let picked { return picked }
        return candidates.count == 1 ? candidates.first : nil
    }

    var body: some View {
        if let dumpster {
            UpdateRentalForm(
                dumpster: dumpster,
                action: action,
                issues: issues,
                onFinish: onFinish,
                onStartOver: onStartOver
            )
        } else if candidates.isEmpty {
            NothingFoundView(message: notFoundMessage, onSkip: onSkip, onStartOver: onStartOver)
        } else {
            WhichDumpsterList(dumpsters: candidates, onPick: { picked = $0 }, onStartOver: onStartOver)
        }
    }
}

private struct UpdateRentalForm: View {
    @Environment(\.modelContext) private var context

    let dumpster: Dumpster
    private let flags: AssistantFlags
    var onFinish: (String) -> Void
    var onStartOver: () -> Void

    @State private var dueBackDate: Date
    @State private var priceText: String
    @State private var agreedTonsText: String
    @State private var location: String
    @State private var noteToAdd: String
    @State private var saved = false
    @State private var flagged = 0

    init(dumpster: Dumpster, action: AssistantAction, issues: [PlanIssue],
         onFinish: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.dumpster = dumpster
        self.onFinish = onFinish
        self.onStartOver = onStartOver

        let newAddress = action.newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = action.note.trimmingCharacters(in: .whitespacesAndNewlines)
        _dueBackDate = State(initialValue: JobDraft.day(from: action.dueBack) ?? dumpster.dueBackAt ?? Dates.startOfToday())
        _priceText = State(initialValue: action.price.isEmpty ? Parse.moneyText(dumpster.price) : action.price)
        _agreedTonsText = State(initialValue: action.agreedTons.isEmpty ? Parse.tonsText(dumpster.agreedWeightTons) : action.agreedTons)
        _location = State(initialValue: newAddress.isEmpty ? dumpster.location : newAddress)
        _noteToAdd = State(initialValue: note)

        var flags = AssistantFlags(issues: issues)
        let heardAChange = !action.dueBack.isEmpty || !action.price.isEmpty || !action.agreedTons.isEmpty
            || !newAddress.isEmpty || !note.isEmpty
        if !heardAChange {
            flags.add("dueBack", "No change was heard.")
        }
        self.flags = flags
    }

    var body: some View {
        Form {
            rentalSection
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

    private var rentalSection: some View {
        Section("Rental") {
            FlaggedRow(flags["dumpsterNumber"] ?? flags["ref"]) {
                LabeledContent("Dumpster", value: dumpster.displayName)
            }
            LabeledContent("Customer", value: dumpster.customer?.name ?? "—")
            if let droppedOffAt = dumpster.droppedOffAt {
                LabeledContent("Dropped off", value: Dates.shortDay(droppedOffAt))
            }
            if let dueBackAt = dumpster.dueBackAt {
                LabeledContent("Due back now", value: Dates.shortDay(dueBackAt))
            }
        }
    }

    private var changesSection: some View {
        Section("Changes") {
            FlaggedRow(flags["dueBack"]) {
                DatePicker("Due back", selection: $dueBackDate, displayedComponents: .date)
            }
            FlaggedRow(flags["price"]) {
                LabeledContent("Price") {
                    TextField("Price", text: $priceText, prompt: Text("$0"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
            }
            FlaggedRow(flags["agreedTons"]) {
                LabeledContent("Agreed weight, tons") {
                    TextField("Agreed weight", text: $agreedTonsText, prompt: Text("e.g. 2"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
            }
            FlaggedRow(flags["newAddress"]) {
                TextField("Location", text: $location, axis: .vertical)
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
            if !dumpster.notes.isEmpty {
                Text("Added under the rental's notes: " + dumpster.notes)
            }
        }
    }

    private func save() {
        dumpster.dueBackAt = dueBackDate
        dumpster.price = Parse.money(priceText)
        dumpster.agreedWeightTons = Parse.tons(agreedTonsText)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLocation.isEmpty { dumpster.location = trimmedLocation }
        let note = noteToAdd.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            dumpster.notes = dumpster.notes.isEmpty ? note : dumpster.notes + "\n" + note
        }
        dumpster.updatedAt = Date()
        try? context.save()
        saved.toggle()
        onFinish("Dumpster \(dumpster.number) rental saved.")
    }
}

// MARK: - A note about the dumpster

/// "Dumpster 2 has a cracked door, don't send it out." The note stays on
/// the dumpster, shown on its row and screen, until changed.
struct DumpsterNoteView: View {
    @Environment(\.modelContext) private var context

    let dumpsters: [Dumpster]
    private let flags: AssistantFlags
    var onFinish: (String) -> Void
    var onStartOver: () -> Void

    @State private var number: Int
    @State private var note: String
    @State private var saved = false
    @State private var flagged = 0

    init(action: AssistantAction, issues: [PlanIssue], dumpsters: [Dumpster], preselected: Int?,
         onFinish: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.dumpsters = dumpsters
        self.onFinish = onFinish
        self.onStartOver = onStartOver

        let sorted = dumpsters.sorted { $0.number < $1.number }
        var known: Int? = nil
        if let preselected, sorted.contains(where: { $0.number == preselected }) {
            known = preselected
        }
        _number = State(initialValue: known ?? sorted.first?.number ?? 0)
        _note = State(initialValue: action.note.trimmingCharacters(in: .whitespacesAndNewlines))

        var flags = AssistantFlags(issues: issues)
        if let preselected, known == nil {
            flags.add("dumpsterNumber", "There is no Dumpster \(preselected).")
        } else if preselected == nil {
            flags.add("dumpsterNumber", "No dumpster number was said.")
        }
        self.flags = flags
    }

    private var sorted: [Dumpster] {
        dumpsters.sorted { $0.number < $1.number }
    }

    private var selected: Dumpster? {
        sorted.first { $0.number == number }
    }

    var body: some View {
        Form {
            Section("Dumpster") {
                FlaggedRow(flags["dumpsterNumber"] ?? flags["ref"]) {
                    Picker("Dumpster", selection: $number) {
                        ForEach(sorted) { dumpster in
                            Text(dumpster.displayName).tag(dumpster.number)
                        }
                    }
                }
                if let current = selected?.conditionNote, !current.isEmpty {
                    LabeledContent("Note now") {
                        Text(current)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            Section {
                FlaggedRow(flags["note"]) {
                    TextField("Dumpster note", text: $note, axis: .vertical)
                }
            } header: {
                Text("Note")
            } footer: {
                Text("Shown on the dumpster's row and screen until changed. Leave it empty to clear it.")
            }
            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(selected == nil)
            }
        }
        .onAppear {
            if !flags.isEmpty { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private func save() {
        guard let dumpster = selected else { return }
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        dumpster.conditionNote = text
        dumpster.updatedAt = Date()
        try? context.save()
        saved.toggle()
        onFinish(text.isEmpty ? "Dumpster \(dumpster.number) note cleared." : "Dumpster \(dumpster.number) note saved.")
    }
}

import SwiftData
import SwiftUI

/// "Picked up dumpster 3, 2.8 tons." Finds the dumpster, shows the weigh-in
/// with the overweight charge, and marks it picked up the same way the
/// dumpster screen does.
struct DumpsterPickupView: View {
    let draft: JobDraft
    let dumpsters: [Dumpster]
    var onSaved: () -> Void
    var onStartOver: () -> Void
    var onDone: () -> Void

    @State private var picked: Dumpster?

    private var candidates: [Dumpster] {
        matchDumpster(draft, dumpsters: dumpsters, wantOut: true)
    }

    private var dumpster: Dumpster? {
        if let picked { return picked }
        let found = candidates
        return found.count == 1 ? found.first : nil
    }

    var body: some View {
        if let dumpster {
            DumpsterPickupForm(
                dumpster: dumpster,
                draft: draft,
                onSaved: {
                    // Keep showing this dumpster while the sheet closes, even
                    // though it is no longer out.
                    picked = dumpster
                    onSaved()
                },
                onStartOver: onStartOver
            )
        } else if candidates.isEmpty {
            notFound
        } else {
            whichDumpster
        }
    }

    // MARK: Which dumpster?

    private var whichDumpster: some View {
        List {
            Section {
                ForEach(candidates) { candidate in
                    Button {
                        picked = candidate
                    } label: {
                        DumpsterRow(dumpster: candidate)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Which dumpster?")
            }
            Section {
                Button("Start over") { onStartOver() }
            }
        }
    }

    // MARK: Nothing found

    private var notFound: some View {
        Form {
            Section {
                Text(notFoundMessage)
            }
            Section {
                Button("Done") { onDone() }
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
    }

    private var notFoundMessage: String {
        if let number = Int(draft.dumpsterNumber.filter(\.isNumber)) {
            if dumpsters.contains(where: { $0.number == number }) {
                return "Dumpster \(number) is in the yard. Nothing to pick up."
            }
            return "There is no Dumpster \(number)."
        }
        let address = draft.address.trimmingCharacters(in: .whitespaces)
        if !address.isEmpty { return "No dumpster is out at \(address)." }
        let name = draft.customerName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return "No dumpster is out at \(name)'s." }
        return "No dumpster is out."
    }
}

/// The current rental and the weigh-in, as on the dumpster screen.
private struct DumpsterPickupForm: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.overweightRateKey) private var ratePerTon = AppSettings.defaultOverweightRate

    let dumpster: Dumpster
    let draft: JobDraft
    var onSaved: () -> Void
    var onStartOver: () -> Void

    @State private var actualTonsText: String
    @State private var saved = false
    @State private var flagged = 0

    private let flags: AssistantFlags

    init(dumpster: Dumpster, draft: JobDraft, onSaved: @escaping () -> Void, onStartOver: @escaping () -> Void) {
        self.dumpster = dumpster
        self.draft = draft
        self.onSaved = onSaved
        self.onStartOver = onStartOver
        _actualTonsText = State(initialValue: draft.actualTons)
        var flags = AssistantFlags(draft: draft)
        if Parse.tons(draft.actualTons) == nil {
            flags.add("actualTons", "No weight was said.")
        }
        self.flags = flags
    }

    private var actualTons: Double? { Parse.tons(actualTonsText) }

    private var charge: Double {
        Overweight.charge(agreedTons: dumpster.agreedWeightTons, actualTons: actualTons, ratePerTon: ratePerTon)
    }

    /// The weight note clears as soon as a weight is typed in.
    private var weightNote: String? {
        actualTons == nil ? (flags["actualTons"] ?? "No weight was said.") : nil
    }

    var body: some View {
        Form {
            rentalSection
            pickupSection
            Section {
                Button("Start over") { onStartOver() }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Mark Picked Up") { markPickedUp() }
            }
        }
        .onAppear {
            if !flags.isEmpty { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    private var rentalSection: some View {
        Section("Dumpster") {
            LabeledContent("Dumpster", value: dumpster.displayName)
            LabeledContent("Customer", value: dumpster.customer?.name ?? "—")
            LabeledContent("Location") {
                Text(dumpster.location.isEmpty ? "—" : dumpster.location)
                    .multilineTextAlignment(.trailing)
            }
            if let droppedOffAt = dumpster.droppedOffAt {
                LabeledContent("Dropped off", value: Dates.shortDay(droppedOffAt))
            }
            if let dueBackAt = dumpster.dueBackAt {
                LabeledContent("Due back", value: Dates.shortDay(dueBackAt))
            }
            LabeledContent("Price", value: dumpster.price.map(Money.text) ?? "—")
            LabeledContent("Agreed weight", value: dumpster.agreedWeightTons.map { Tons.text($0) } ?? "—")
        }
    }

    private var pickupSection: some View {
        Section {
            FlaggedRow(weightNote) {
                TextField("Actual weight in tons", text: $actualTonsText, prompt: Text("Actual weight in tons"))
                    .decimalKeyboard()
            }
            if let actualTons, let agreed = dumpster.agreedWeightTons {
                if actualTons > agreed {
                    LabeledContent("Over by", value: Tons.text(actualTons - agreed))
                    LabeledContent("Overweight charge") {
                        Text(Money.text(charge))
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Within the agreed weight. No extra charge.")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Pickup")
        } footer: {
            Text("Rate: \(Money.text(ratePerTon)) per ton over the agreed weight. Change it in Settings.")
        }
    }

    private func markPickedUp() {
        dumpster.markPickedUp(actualWeightTons: actualTons, ratePerTon: ratePerTon)
        try? context.save()
        saved.toggle()
        onSaved()
    }
}

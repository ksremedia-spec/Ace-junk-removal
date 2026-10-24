import SwiftData
import SwiftUI

/// One past dumpster rental, opened from Past rentals on the dumpster or
/// customer page, so a weight that came later from the scale ticket can be
/// added and a typo (28 for 2.8 tons) fixed (audit Oct 21, M11). How the
/// overweight charge gets billed is still Kyle's decision.
struct RentalRecordView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let record: RentalRecord

    @State private var droppedOff: Date
    @State private var pickedUp: Date
    @State private var priceText: String
    @State private var agreedText: String
    @State private var actualText: String
    @State private var confirmDelete = false
    @State private var saved = 0
    /// "28 tons is more than a dumpster holds. Was it 2.8 tons?"
    @State private var askHeavy = false

    init(record: RentalRecord) {
        self.record = record
        _droppedOff = State(initialValue: record.droppedOffAt)
        _pickedUp = State(initialValue: record.pickedUpAt)
        _priceText = State(initialValue: Parse.moneyText(record.price))
        _agreedText = State(initialValue: Parse.tonsText(record.agreedWeightTons))
        _actualText = State(initialValue: Parse.tonsText(record.actualWeightTons))
    }

    private var charge: Double {
        Overweight.charge(agreedTons: Parse.tons(agreedText), actualTons: Parse.tons(actualText), ratePerTon: record.ratePerTon)
    }

    private var hasChanges: Bool {
        droppedOff != record.droppedOffAt || pickedUp != record.pickedUpAt
            || Parse.money(priceText) != record.price
            || Parse.tons(agreedText) != record.agreedWeightTons
            || Parse.tons(actualText) != record.actualWeightTons
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Customer", value: record.customer?.name ?? "No customer")
                if let dumpster = record.dumpster {
                    LabeledContent("Dumpster", value: "Dumpster \(dumpster.number)")
                }
                LabeledContent("Location", value: record.location.isEmpty ? "Not noted" : record.location)
            }
            Section("Dates") {
                DatePicker("Dropped off", selection: $droppedOff, displayedComponents: .date)
                DatePicker("Picked up", selection: $pickedUp, in: droppedOff..., displayedComponents: .date)
            }
            Section {
                LabeledContent("Price") {
                    TextField("Price", text: $priceText, prompt: Text("$0"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
                LabeledContent("Agreed weight, tons") {
                    TextField("Agreed", text: $agreedText, prompt: Text("0"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
                LabeledContent("Actual weight, tons") {
                    TextField("Actual", text: $actualText, prompt: Text("From the scale ticket"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
                if let note = WeightCheck.note(for: Parse.tons(actualText)) {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Tint.warning)
                }
                LabeledContent("Overweight charge", value: Money.text(charge))
            } header: {
                Text("Price and weight")
            } footer: {
                Text("\(Money.text(record.ratePerTon)) a ton over the agreed weight, the rate when it was picked up.")
            }
            Section {
                Button("Delete this rental", role: .destructive) { confirmDelete = true }
                    .confirmationDialog("Delete this rental from the history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            context.delete(record)
                            try? context.save()
                            dismiss()
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Rental")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if WeightCheck.suggestion(for: Parse.tons(actualText)) != nil {
                        askHeavy = true
                    } else {
                        save()
                    }
                }
                .disabled(!hasChanges)
            }
        }
        .heavyWeightQuestion(isPresented: $askHeavy, tons: Parse.tons(actualText)) { tons in
            save(actualTons: tons)
        }
        .sensoryFeedback(.success, trigger: saved)
    }

    /// `actualTons`: the weight chosen in the heavy-weight question, else
    /// the one typed.
    private func save(actualTons chosen: Double? = nil) {
        record.droppedOffAt = Calendar.current.startOfDay(for: droppedOff)
        record.pickedUpAt = Calendar.current.startOfDay(for: pickedUp)
        record.price = Parse.money(priceText)
        record.agreedWeightTons = Parse.tons(agreedText)
        record.actualWeightTons = chosen ?? Parse.tons(actualText)
        record.updatedAt = Date()
        try? context.save()
        saved += 1
        dismiss()
    }
}

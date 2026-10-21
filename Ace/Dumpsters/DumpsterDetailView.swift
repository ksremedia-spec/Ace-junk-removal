import SwiftData
import SwiftUI

/// One dumpster. In the yard: a drop-off form. Out: the current rental, the
/// weigh-in at pickup with the overweight charge, and past rentals.
struct DumpsterDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Bindable var dumpster: Dumpster

    @AppStorage(AppSettings.overweightRateKey) private var ratePerTon = AppSettings.defaultOverweightRate

    // Drop-off form (used while the dumpster is in the yard).
    @State private var dropOffCustomer: Customer?
    @State private var dropOffLocation = ""
    @State private var dropOffDate = Dates.startOfToday()
    @State private var dueBackDate = Calendar.current.date(byAdding: .day, value: 7, to: Dates.startOfToday()) ?? Date()
    @State private var dropOffPriceText = ""
    @State private var dropOffAgreedTonsText = ""
    @State private var dropOffNotes = ""
    @State private var showingCustomerPicker = false

    // Pickup (used while the dumpster is out).
    @State private var actualTonsText = ""
    @State private var confirmPickup = false

    @State private var saved = false
    @State private var flagged = 0
    /// The address filled in from the chosen customer, so choosing another
    /// customer replaces it rather than keeping the first one's.
    @State private var autoFilledLocation = ""
    /// "Dumpster 1 picked up. Overweight charge $137.50." until leaving.
    @State private var savedNote: String?

    private var actualTons: Double? { Parse.tons(actualTonsText) }

    private var pickupCharge: Double {
        Overweight.charge(agreedTons: dumpster.agreedWeightTons, actualTons: actualTons, ratePerTon: ratePerTon)
    }

    private var historyNewestFirst: [RentalRecord] {
        dumpster.history.sorted { $0.pickedUpAt > $1.pickedUpAt }
    }

    /// Rentals picked up this calendar month.
    private var thisMonth: [RentalRecord] {
        dumpster.history.filter { Dates.isInCurrentMonth($0.pickedUpAt) }
    }

    private var thisMonthTotal: Double {
        thisMonth.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        Form {
            Section {
                header
                    .bareRow()
            }

            if let savedNote {
                Section {
                    Label(savedNote, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Tint.paid)
                }
            }

            // Out: the pickup comes first, the thing Alex does at the curb
            // (Oct 20 phone audit: the weight box was below the fold).
            if dumpster.isOut {
                pickupSection
                currentRentalSection
            } else {
                dropOffSection
            }

            aboutSection


            if !historyNewestFirst.isEmpty {
                Section("Past rentals") {
                    ForEach(historyNewestFirst) { record in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.customer?.name ?? "No customer")
                                .font(.headline)
                            Text(Dates.shortDay(record.droppedOffAt) + " to " + Dates.shortDay(record.pickedUpAt))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(historyLine(record))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .readableWidth()
        .navigationTitle("Dumpster \(dumpster.number)")
        .sheet(isPresented: $showingCustomerPicker) {
            NavigationStack {
                CustomerPickerView(selection: $dropOffCustomer)
            }
        }
        .onChange(of: dropOffCustomer) { _, customer in
            guard let customer else { return }
            if dropOffLocation.isEmpty || dropOffLocation == autoFilledLocation {
                dropOffLocation = customer.address
                autoFilledLocation = customer.address
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    // MARK: Header

    private var header: some View {
        DetailHeader(
            title: dumpster.displayName,
            subtitle: headerSubtitle,
            caption: dumpster.isOut && !dumpster.location.isEmpty ? dumpster.location : nil,
            value: dumpster.isOut ? dumpster.price.map(Money.text) : nil,
            hasActions: dumpster.isOut && (renterPhone != nil || placeDirections != nil)
        ) {
            DumpsterBadge(dumpster: dumpster, size: 52)
        } pills: {
            HStack(spacing: Space.xs) {
                StatusPill(text: dumpster.status().rawValue, tint: dumpster.status().tint)
                if !thisMonth.isEmpty {
                    StatusPill(text: "This month " + Plural.text(thisMonth.count, "rental") + ", " + Money.text(thisMonthTotal),
                               tint: .secondary)
                }
            }
            // On its own line, so a long note wraps instead of running off.
            if !dumpster.conditionNote.isEmpty {
                Label(dumpster.conditionNote, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Tint.owed)
            }
        } actions: {
            if let url = renterPhone {
                Button { openURL(url) } label: { Label("Call", systemImage: "phone.fill") }
                    .buttonStyle(.action())
            }
            if let url = placeDirections {
                Button { openURL(url) } label: { Label("Directions", systemImage: "map.fill") }
                    .buttonStyle(.action())
            }
        }
    }

    private var renterPhone: URL? { dumpster.customer?.phoneURL }

    /// Where the dumpster is, else the renter's address.
    private var placeDirections: URL? {
        Maps.directions(to: dumpster.location) ?? dumpster.customer?.directionsURL
    }

    /// "Out with Harborview Realty · due back Sat, Oct 17" or "In the yard".
    private var headerSubtitle: String {
        guard dumpster.isOut else { return "In the yard, ready to go out" }
        var text = "With " + (dumpster.customer?.name ?? "no customer")
        if let dueBackAt = dumpster.dueBackAt {
            text += " · due back " + Dates.shortDay(dueBackAt)
        }
        return text
    }

    // MARK: Out

    /// The header already shows who, where and the price.
    private var currentRentalSection: some View {
        Section("Current rental") {
            if let customer = dumpster.customer {
                NavigationLink {
                    CustomerDetailView(customer: customer)
                } label: {
                    LabeledContent("Customer", value: customer.name)
                }
            }
            if let droppedOffAt = dumpster.droppedOffAt {
                LabeledContent("Dropped off", value: Dates.shortDay(droppedOffAt))
            }
            DatePicker("Due back", selection: Binding(
                get: { dumpster.dueBackAt ?? Date() },
                set: { dumpster.dueBackAt = $0; dumpster.updatedAt = Date() }
            ), displayedComponents: .date)
            if !dumpster.notes.isEmpty {
                Text(dumpster.notes)
            }
        }
    }

    private var pickupSection: some View {
        Section {
            LabeledContent("Agreed weight", value: dumpster.agreedWeightTons.map { Tons.text($0) } ?? "None")
            LabeledContent("Actual weight, tons") {
                TextField("Actual weight in tons", text: $actualTonsText, prompt: Text("e.g. 2.8"))
                    .multilineTextAlignment(.trailing)
                    .decimalKeyboard()
            }
            if actualTons != nil, dumpster.agreedWeightTons == nil {
                Text("No agreed weight on this rental. No overweight charge.")
                    .font(.footnote)
                    .foregroundStyle(Tint.owed)
            }
            if let actualTons, let agreed = dumpster.agreedWeightTons {
                if actualTons > agreed {
                    LabeledContent("Over by", value: Tons.text(actualTons - agreed))
                    LabeledContent("Overweight charge") {
                        Text(Money.text(pickupCharge))
                            .foregroundStyle(Tint.owed)
                    }
                } else {
                    Text("Within the agreed weight. No extra charge.")
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                if pickupCharge > 0 { flagged += 1 }
                confirmPickup = true
            } label: {
                Label("Mark picked up", systemImage: "tray.and.arrow.up.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.action(.accentColor, prominent: true))
            .confirmationDialog(pickupQuestion, isPresented: $confirmPickup, titleVisibility: .visible) {
                Button("Mark picked up") { markPickedUp() }
            }
        } header: {
            Text("Pickup")
        } footer: {
            Text("Rate: \(Money.text(ratePerTon)) per ton over the agreed weight. Change it in Settings.")
        }
    }

    private var pickupQuestion: String {
        if pickupCharge > 0 {
            return "Overweight charge \(Money.text(pickupCharge)). Mark Dumpster \(dumpster.number) as picked up?"
        }
        if actualTons == nil {
            return "No weight entered. Mark Dumpster \(dumpster.number) as picked up without one?"
        }
        if dumpster.agreedWeightTons == nil {
            return "No agreed weight, so no overweight charge. Mark Dumpster \(dumpster.number) as picked up?"
        }
        return "Mark Dumpster \(dumpster.number) as picked up?"
    }

    private func markPickedUp() {
        let charge = pickupCharge
        dumpster.markPickedUp(actualWeightTons: actualTons, ratePerTon: ratePerTon)
        try? context.save()
        actualTonsText = ""
        savedNote = "Dumpster \(dumpster.number) picked up." + (charge > 0 ? " Overweight charge \(Money.text(charge))." : "")
        saved.toggle()
    }

    // MARK: In the yard

    private var dropOffSection: some View {
        Section {
            LabeledContent("Customer") {
                Button(dropOffCustomer?.name ?? "Choose…") {
                    showingCustomerPicker = true
                }
            }
            TextField("Location", text: $dropOffLocation, prompt: Text("Address, or where on the lot"), axis: .vertical)
                .wordsCapitalized()
            DatePicker("Drop-off", selection: $dropOffDate, displayedComponents: .date)
            DatePicker("Due back", selection: $dueBackDate, displayedComponents: .date)
            // Labelled: a bare "450" and "2" once typed said nothing.
            LabeledContent("Price") {
                TextField("Price", text: $dropOffPriceText, prompt: Text("$0"))
                    .multilineTextAlignment(.trailing)
                    .decimalKeyboard()
            }
            LabeledContent("Agreed weight, tons") {
                TextField("Agreed weight", text: $dropOffAgreedTonsText, prompt: Text("e.g. 2"))
                    .multilineTextAlignment(.trailing)
                    .decimalKeyboard()
            }
            TextField("Notes", text: $dropOffNotes, prompt: Text("Gate code, where to put it"), axis: .vertical)
            Button {
                markDroppedOff()
            } label: {
                Label("Mark dropped off", systemImage: "tray.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.action(.accentColor, prominent: true))
            .disabled(dropOffCustomer == nil)
            .opacity(dropOffCustomer == nil ? 0.5 : 1)
        } header: {
            Text("Drop off")
        }
    }

    private func markDroppedOff() {
        dumpster.dropOff(
            to: dropOffCustomer,
            location: dropOffLocation,
            on: dropOffDate,
            dueBack: dueBackDate,
            price: Parse.money(dropOffPriceText),
            agreedWeightTons: Parse.tons(dropOffAgreedTonsText),
            notes: dropOffNotes
        )
        try? context.save()
        savedNote = "Dumpster \(dumpster.number) dropped off" + (dropOffLocation.isEmpty ? "." : " at \(dropOffLocation).")

        dropOffCustomer = nil
        autoFilledLocation = ""
        dropOffLocation = ""
        dropOffPriceText = ""
        dropOffAgreedTonsText = ""
        dropOffNotes = ""
        saved.toggle()
    }

    // MARK: About

    /// What stays with the dumpster between rentals.
    private var aboutSection: some View {
        Section {
            LabeledContent("Size") {
                TextField("Size or nickname", text: $dumpster.label, prompt: Text("e.g. 15 yard"))
                    .multilineTextAlignment(.trailing)
            }
            TextField("Condition", text: $dumpster.conditionNote, prompt: Text("Condition, e.g. cracked door, don't send out"), axis: .vertical)
        } header: {
            Text("About this dumpster")
        } footer: {
            Text("Stays with the dumpster between rentals.")
        }
        .onChange(of: dumpster.label) { _, _ in dumpster.updatedAt = Date() }
        .onChange(of: dumpster.conditionNote) { _, _ in dumpster.updatedAt = Date() }
    }

    // MARK: Text

    private func historyLine(_ record: RentalRecord) -> String {
        var parts: [String] = []
        if let price = record.price { parts.append(Money.text(price)) }
        if let agreed = record.agreedWeightTons, let actual = record.actualWeightTons {
            parts.append("\(Tons.text(actual)) of \(Tons.text(agreed))")
        }
        if record.overweightCharge > 0 {
            parts.append("overweight " + Money.text(record.overweightCharge))
        }
        return parts.isEmpty ? "No details" : parts.joined(separator: " · ")
    }
}

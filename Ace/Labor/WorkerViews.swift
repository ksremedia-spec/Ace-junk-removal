import SwiftData
import SwiftUI

/// Adding someone to the crew: a name, how they are paid, and a rate for
/// hourly crew (optional). Seasonal help is added the same way.
struct NewWorkerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Called with the person just added.
    var onAdded: ((Worker) -> Void)? = nil

    @State private var name = ""
    @State private var payType: PayType = .hourly
    @State private var rateText = ""
    @State private var saved = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("First and last name"))
                Picker("Paid", selection: $payType) {
                    ForEach(PayType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                if payType == .hourly {
                    TextField("Rate", text: $rateText, prompt: Text("Dollars an hour (optional)"))
                        .decimalKeyboard()
                }
            } footer: {
                Text(payType == .salary
                     ? "Salaried crew count as working every work day. Mark a day off on the timesheet."
                     : "Type or say their hours each day. With a rate, the week's pay is worked out.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New person")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add() }
                    .disabled(trimmedName.isEmpty)
            }
        }
        .sensoryFeedback(.success, trigger: saved)
    }

    private func add() {
        let worker = Worker(name: trimmedName, payType: payType,
                            hourlyRate: payType == .hourly ? Parse.money(rateText) : nil)
        context.insert(worker)
        try? context.save()
        saved.toggle()
        onAdded?(worker)
        dismiss()
    }
}

/// One crew member's page: their details (changes save as they are made),
/// the last few weeks, and Retire for someone who has left.
struct WorkerPage: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var worker: Worker
    /// Called after the person is deleted, so the page can close. Without
    /// it (the iPhone) the page goes back first and then deletes, so it
    /// never shows a person who is gone.
    var onDeleted: (() -> Void)? = nil

    @State private var rateText = ""
    @State private var confirmDelete = false

    /// The last four weeks, newest first.
    private var recentWeeks: [[Date]] {
        let calendar = Calendar.current
        return (0..<4).compactMap { back in
            guard let day = calendar.date(byAdding: .weekOfYear, value: -back, to: Dates.startOfToday()) else { return nil }
            return Labor.week(containing: day)
        }
    }

    var body: some View {
        Form {
            Section {
                DetailHeader(
                    title: worker.name.isEmpty ? "No name" : worker.name,
                    subtitle: worker.payText,
                    caption: worker.isActive ? nil : "Retired",
                    hasActions: false
                ) {
                    Avatar(name: worker.name)
                } pills: {
                    EmptyView()
                } actions: {
                    EmptyView()
                }
                .bareRow()
            }
            Section {
                TextField("Name", text: $worker.name, prompt: Text("First and last name"))
                TextField("Phone", text: $worker.phone, prompt: Text("508-555-0123"))
                    .phoneKeyboard()
                Picker("Paid", selection: payBinding) {
                    ForEach(PayType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                if !worker.isSalaried {
                    TextField("Rate", text: $rateText, prompt: Text("Dollars an hour"))
                        .decimalKeyboard()
                        .onChange(of: rateText) { _, text in
                            worker.hourlyRate = Parse.money(text)
                            touch()
                        }
                }
            }
            Section("Last four weeks") {
                ForEach(recentWeeks, id: \.first) { days in
                    LabeledContent("Week of " + Dates.shortDay(days.first ?? Date())) {
                        Text(weekText(days))
                            .monospacedDigit()
                    }
                }
            }
            Section("Notes") {
                TextEditor(text: $worker.notes)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60)
            }
            Section {
                Button(worker.isActive ? "Retire" : "Bring back") {
                    worker.isActive.toggle()
                    touch()
                }
                .help(worker.isActive ? "Off the timesheet; past hours are kept." : "Back on the timesheet.")
                if worker.entries.isEmpty {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete person", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .confirmationDialog("Delete \(worker.name)?", isPresented: $confirmDelete) {
                        Button("Delete", role: .destructive) {
                            if let onDeleted {
                                context.delete(worker)
                                try? context.save()
                                onDeleted()
                            } else {
                                let gone = worker
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    context.delete(gone)
                                    try? context.save()
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text(worker.isActive
                     ? "Someone who has left is retired, not deleted, so their hours stay on past weeks."
                     : "Retired: not on the timesheet. Past hours are kept.")
            }
        }
        .formStyle(.grouped)
        .readableWidth()
        #if os(iOS)
        .navigationTitle("Person")
        #endif
        .onAppear {
            rateText = worker.hourlyRate.map { Parse.moneyText($0) } ?? ""
        }
        .onChange(of: worker.name) { _, _ in touch() }
        .onChange(of: worker.phone) { _, _ in touch() }
        .onDisappear { try? context.save() }
    }

    private var payBinding: Binding<PayType> {
        Binding(
            get: { worker.payType },
            set: { worker.payType = $0; touch() }
        )
    }

    private func weekText(_ days: [Date]) -> String {
        if worker.isSalaried {
            return Plural.text(Labor.daysWorked(worker, over: days), "day")
        }
        var text = Labor.hoursLabel(Labor.hours(worker, over: days))
        if let pay = Labor.pay(worker, over: days), pay > 0 { text += " · " + Money.text(pay) }
        return text
    }

    private func touch() {
        worker.updatedAt = Date()
    }
}

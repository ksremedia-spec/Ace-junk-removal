import SwiftData
import SwiftUI

/// "Joey worked 8 today and Chris 6 and a half." Every log_hours action in
/// the note on one screen, a row per person: who (matched to the crew, or
/// offered as someone new), the day, and the hours (worked or off for
/// salaried crew). Save writes them to the timesheet. The spec is
/// docs/labor.md, "The Assistant".
struct AssistantLaborView: View {
    @Environment(\.modelContext) private var context

    /// The plan's question for a row, by its action's position.
    let questions: [Int: String]
    var onFinish: (String) -> Void
    var onStartOver: () -> Void

    struct Line: Identifiable {
        let id: Int
        var worker: Worker?
        /// The name as said, for someone not on the crew.
        var name: String
        var day: Date
        var hoursText: String
        /// Salaried crew: working that day, or off.
        var worked: Bool
        /// Someone not on the crew: add them when saving.
        var addNew: Bool
        var newPay: PayType
    }

    @State private var lines: [Line]
    @State private var saved = false
    @State private var flagged = 0

    init(actions: [AssistantAction], issues: [PlanIssue], refs: RecordRefs, workers: [Worker],
         onFinish: @escaping (String) -> Void, onStartOver: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onStartOver = onStartOver
        var questions: [Int: String] = [:]
        for issue in issues where questions[issue.action] == nil {
            questions[issue.action] = issue.question
        }
        self.questions = questions
        let crew = workers.filter(\.isActive)
        _lines = State(initialValue: actions.map { action in
            let worker = refs.worker(action.ref) ?? Self.match(action.workerName, in: crew)
            let hours = Labor.parseHours(action.hours)
            return Line(
                id: action.index,
                worker: worker,
                name: action.workerName.trimmingCharacters(in: .whitespaces),
                day: JobDraft.day(from: action.date) ?? Dates.startOfToday(),
                hoursText: hours.map { $0 > 0 ? Labor.hoursText($0) : "" } ?? "",
                worked: hours.map { $0 > 0 } ?? true,
                addNew: worker == nil && !action.workerName.trimmingCharacters(in: .whitespaces).isEmpty,
                newPay: .hourly
            )
        })
    }

    /// The crew member a spoken name means: the whole name, else a first or
    /// last name only one person has.
    static func match(_ said: String, in crew: [Worker]) -> Worker? {
        let spoken = SpokenName(said)
        guard !spoken.words.isEmpty else { return nil }
        if let exact = crew.first(where: { SpokenName($0.name).text == spoken.text }) { return exact }
        let byPart = crew.filter { worker in
            let words = SpokenName(worker.name).words
            return spoken.words.allSatisfy(words.contains)
        }
        return byPart.count == 1 ? byPart.first : nil
    }

    var body: some View {
        Form {
            ForEach($lines) { $line in
                Section {
                    row($line)
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
                    .disabled(!canSave)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .onAppear {
            if !questions.isEmpty || lines.contains(where: { $0.worker == nil }) { flagged += 1 }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.warning, trigger: flagged)
    }

    @ViewBuilder
    private func row(_ line: Binding<Line>) -> some View {
        let value = line.wrappedValue
        if let worker = value.worker {
            HStack(spacing: Space.m) {
                Avatar(name: worker.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(worker.name)
                        .font(.body.weight(.semibold))
                    Text(worker.isSalaried ? "Salary" : worker.payText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            FlaggedRow(value.name.isEmpty ? "No name was said." : "\(value.name) is not on the crew.") {
                TextField("Name", text: line.name, prompt: Text("Name"))
            }
            if !value.name.isEmpty {
                Toggle("Add \(value.name) to the crew", isOn: line.addNew)
                if value.addNew {
                    Picker("Paid", selection: line.newPay) {
                        ForEach(PayType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }
            }
        }
        DatePicker("Day", selection: line.day, displayedComponents: .date)
        if isSalaried(value) {
            Toggle("Worked", isOn: line.worked)
        } else {
            FlaggedRow(Labor.parseHours(value.hoursText) == nil ? "No hours were said." : nil) {
                // Labelled on the iPhone too, where a form hides a text
                // box's own label and "8" alone said nothing.
                LabeledContent("Hours") {
                    TextField("Hours", text: line.hoursText, prompt: Text("8 or 7.5"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                }
            }
        }
        if let question = questions[value.id] {
            Text(question)
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private func isSalaried(_ line: Line) -> Bool {
        line.worker?.isSalaried ?? (line.addNew && line.newPay == .salary)
    }

    /// Lines that will be written: on the crew (or being added), with
    /// hours for hourly people.
    private var ready: [Line] {
        lines.filter { line in
            guard line.worker != nil || (line.addNew && !line.name.trimmingCharacters(in: .whitespaces).isEmpty) else { return false }
            return isSalaried(line) || Labor.parseHours(line.hoursText) != nil
        }
    }

    private var canSave: Bool { !ready.isEmpty }

    private func save() {
        for line in ready {
            let worker: Worker
            if let existing = line.worker {
                worker = existing
            } else {
                worker = Worker(name: line.name.trimmingCharacters(in: .whitespaces), payType: line.newPay)
                // Counted from the day logged, so a new hire's first day counts.
                worker.createdAt = min(Date(), line.day)
                context.insert(worker)
            }
            if worker.isSalaried {
                Labor.setWorked(line.worked, for: worker, on: line.day, in: context)
            } else {
                Labor.setHours(Labor.parseHours(line.hoursText), for: worker, on: line.day, in: context)
            }
        }
        try? context.save()
        saved.toggle()
        onFinish(ready.count == 1 ? "Hours saved." : "Hours saved for \(ready.count) people.")
    }
}

import Observation
import SwiftData
import SwiftUI

/// The one-tap changes on a job (Done, Not done, Paid, Unpaid) in one place,
/// so every button behaves the same (audit Oct 21, design ideas 1 and 2):
/// - Mark paid asks how it was paid (Check asks for the number);
/// - every change shows "Job marked paid. Undo" for a few seconds.
/// Undo puts the old values back with a new time, so the reversal syncs
/// like any other change (SwiftData's own undo would roll the time back).
/// It puts back only what the action changed, and only while that field
/// still holds what the action set: a note typed meanwhile, or a change
/// from another device, is never undone with it (audit Oct 24, 38 and 63).
@MainActor @Observable
final class JobActions {
    static let shared = JobActions()

    /// A job waiting for "How was it paid?".
    var askingPayment: Job?
    /// Chose Check: waiting for the number.
    var askingCheckNumber: Job?
    var checkNumber = ""

    private(set) var message: String?
    private(set) var shown = 0
    @ObservationIgnored private var undo: (() -> Void)?
    /// The job the Undo bar is about, so deleting it takes the bar away.
    @ObservationIgnored private var undoJobID: PersistentIdentifier?
    @ObservationIgnored private var hide: Task<Void, Never>?

    private init() {}

    func setDone(_ done: Bool, _ job: Job, in context: ModelContext) {
        guard !Self.isGone(job) else { return }
        let before = job.isDone
        job.isDone = done
        save(job, in: context)
        offerUndo(done ? "Job marked done." : "Job marked not done.", job: job, in: context) { job in
            guard job.isDone == done, before != done else { return false }
            job.isDone = before
            return true
        }
    }

    /// Paid asks how first; Unpaid happens at once.
    func setPaid(_ paid: Bool, _ job: Job, in context: ModelContext) {
        guard !Self.isGone(job) else { return }
        if paid {
            askingPayment = job
        } else {
            let wasPaid = job.isPaid
            job.isPaid = false
            save(job, in: context)
            offerUndo("Job marked unpaid.", job: job, in: context) { job in
                guard !job.isPaid, wasPaid else { return false }
                job.isPaid = true
                return true
            }
        }
    }

    func paid(_ job: Job, by type: PaymentType, checkNumber: String? = nil, in context: ModelContext) {
        guard !Self.isGone(job) else { return }
        let wasPaid = job.isPaid
        let typeBefore = job.paymentType
        let notesBefore = job.notes
        job.isPaid = true
        job.paymentType = type
        if let number = checkNumber?.trimmingCharacters(in: .whitespaces), !number.isEmpty {
            job.notes = Self.notes(job.notes, check: number)
        } else if type != .check, Self.checkNumber(in: job.notes) != nil {
            // Paid another way after a check: the old number would show in
            // the sheet's Check # column beside Cash (audit Oct 24, 65).
            job.notes = Self.notes(job.notes, check: nil)
        }
        let notesAfter = job.notes
        save(job, in: context)
        offerUndo("Job marked paid by \(type.rawValue).", job: job, in: context) { job in
            var changed = false
            if job.isPaid && !wasPaid { job.isPaid = false; changed = true }
            if job.paymentType == type && typeBefore != type { job.paymentType = typeBefore; changed = true }
            if notesAfter != notesBefore && job.notes == notesAfter { job.notes = notesBefore; changed = true }
            return changed
        }
    }

    func performUndo() {
        undo?()
        dismiss()
    }

    func dismiss() {
        hide?.cancel()
        message = nil
        undo = nil
        undoJobID = nil
    }

    /// Called just before a job is deleted: its Undo bar and any open "How
    /// was it paid?" question go, so neither writes to the deleted job
    /// (audit Oct 24, 22).
    func forget(_ job: Job) {
        let id = job.persistentModelID
        if undoJobID == id { dismiss() }
        if askingPayment?.persistentModelID == id { askingPayment = nil }
        if askingCheckNumber?.persistentModelID == id { askingCheckNumber = nil }
    }

    /// Deleted here, by the Assistant or by another device: nothing may be
    /// written to it.
    static func isGone(_ job: Job) -> Bool {
        job.modelContext == nil || job.isDeleted
    }

    /// The notes with "Check #1234" in place of any earlier check number
    /// (the same wording the sheet link and the import use). A nil number
    /// takes the check number out.
    nonisolated static func notes(_ notes: String, check: String?) -> String {
        let without = notes.replacingOccurrences(of: #"Check #\S+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let check else { return without }
        return ["Check #\(check)", without].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "1234" from notes holding "Check #1234"; nil when there is none.
    nonisolated static func checkNumber(in notes: String) -> String? {
        guard let range = notes.range(of: #"Check #\S+"#, options: .regularExpression) else { return nil }
        return String(notes[range].dropFirst("Check #".count))
    }

    /// How long the Undo bar stays. Debug builds can lengthen it for
    /// testing with `-debug.undoSeconds 60`.
    private static var barSeconds: Double {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-debug.undoSeconds"), i + 1 < args.count, let v = Double(args[i + 1]) { return v }
        #endif
        return 8
    }

    // MARK: Inside

    private func save(_ job: Job, in context: ModelContext) {
        job.updatedAt = Date()
        try? context.save()
        CalendarStore.shared.jobSaved(job)
    }

    /// `restore` puts back what the action changed and says whether it
    /// changed anything; nothing is saved when it did not.
    private func offerUndo(_ text: String, job: Job, in context: ModelContext, restore: @escaping (Job) -> Bool) {
        undo = { [weak self] in
            // Deleted since: writing to it would bring back a ghost event.
            guard !Self.isGone(job) else { return }
            if restore(job) { self?.save(job, in: context) }
        }
        undoJobID = job.persistentModelID
        message = text
        shown += 1
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.barSeconds))
            guard !Task.isCancelled else { return }
            self?.message = nil
            self?.undo = nil
            self?.undoJobID = nil
        }
    }
}

/// Hosts "How was it paid?", the check-number question and the Undo bar.
/// Put once on each app's main view.
struct JobActionsHost: ViewModifier {
    @Environment(\.modelContext) private var context
    @State private var actions = JobActions.shared

    private static let choices: [PaymentType] = [.cash, .check, .card, .venmo, .cashApp]

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: askingBinding, titleVisibility: .visible, presenting: actions.askingPayment) { job in
                ForEach(Self.choices, id: \.self) { type in
                    Button(type == .check ? "Check…" : type.rawValue) {
                        if type == .check {
                            guard !JobActions.isGone(job) else { return }
                            actions.checkNumber = ""
                            actions.askingCheckNumber = job
                        } else {
                            actions.paid(job, by: type, in: context)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Check number", isPresented: checkBinding, presenting: actions.askingCheckNumber) { job in
                TextField("Number", text: $actions.checkNumber)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Save") { actions.paid(job, by: .check, checkNumber: actions.checkNumber, in: context) }
                Button("Skip") { actions.paid(job, by: .check, in: context) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Kept in the job's notes, like the sheet's Check # column.")
            }
            #if os(macOS)
            .undoBar()
            #endif
            .sensoryFeedback(.success, trigger: actions.shown)
    }

    private var title: String {
        guard let job = actions.askingPayment, !JobActions.isGone(job) else { return "How was it paid?" }
        if let price = job.price { return "How was \(Money.text(price)) paid?" }
        return "How was it paid?"
    }

    private var askingBinding: Binding<Bool> {
        Binding(get: { actions.askingPayment != nil }, set: { if !$0 { actions.askingPayment = nil } })
    }

    private var checkBinding: Binding<Bool> {
        Binding(get: { actions.askingCheckNumber != nil }, set: { if !$0 { actions.askingCheckNumber = nil } })
    }
}

/// "Job marked paid, cash.  Undo"
private struct UndoBar: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Text(message)
                .font(.callout.weight(.medium))
                .lineLimit(2)
            // No ⌘Z here: it stays with Edit › Undo, so a typo in a text box
            // is undone instead of the payment (audit Oct 24, 33 and 64).
            Button(action: onUndo) {
                Text("Undo")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
                .font(.callout.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal, Space.l)
        .accessibilityElement(children: .contain)
    }
}

/// The Undo bar along the bottom. On iPhone it goes on each tab's own
/// screen: laid over the whole TabView it showed but could not be tapped.
private struct UndoBarOverlay: ViewModifier {
    @State private var actions = JobActions.shared

    func body(content: Content) -> some View {
        // An inset, not an overlay: laid over an iPhone list, an overlay
        // showed but taps went through it to the row underneath.
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let message = actions.message {
                    UndoBar(message: message) { actions.performUndo() }
                        .padding(.bottom, Space.s)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: actions.message)
    }
}

extension View {
    func jobActionsHost() -> some View { modifier(JobActionsHost()) }
    func undoBar() -> some View { modifier(UndoBarOverlay()) }
}

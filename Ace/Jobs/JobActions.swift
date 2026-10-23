import Observation
import SwiftData
import SwiftUI

/// The one-tap changes on a job (Done, Not done, Paid, Unpaid) in one place,
/// so every button behaves the same (audit Oct 21, design ideas 1 and 2):
/// - Mark paid asks how it was paid (Check asks for the number);
/// - every change shows "Job marked paid. Undo" for a few seconds.
/// Undo puts the old values back with a new time, so the reversal syncs
/// like any other change (SwiftData's own undo would roll the time back).
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
    @ObservationIgnored private var hide: Task<Void, Never>?

    private init() {}

    func setDone(_ done: Bool, _ job: Job, in context: ModelContext) {
        let before = Snapshot(job)
        job.isDone = done
        save(job, in: context)
        offerUndo(done ? "Job marked done." : "Job marked not done.", job: job, before: before, in: context)
    }

    /// Paid asks how first; Unpaid happens at once.
    func setPaid(_ paid: Bool, _ job: Job, in context: ModelContext) {
        if paid {
            askingPayment = job
        } else {
            let before = Snapshot(job)
            job.isPaid = false
            save(job, in: context)
            offerUndo("Job marked unpaid.", job: job, before: before, in: context)
        }
    }

    func paid(_ job: Job, by type: PaymentType, checkNumber: String? = nil, in context: ModelContext) {
        let before = Snapshot(job)
        job.isPaid = true
        job.paymentType = type
        if let number = checkNumber?.trimmingCharacters(in: .whitespaces), !number.isEmpty {
            job.notes = Self.notes(job.notes, check: number)
        }
        save(job, in: context)
        offerUndo("Job marked paid by \(type.rawValue).", job: job, before: before, in: context)
    }

    func performUndo() {
        undo?()
        dismiss()
    }

    func dismiss() {
        hide?.cancel()
        message = nil
        undo = nil
    }

    /// The notes with "Check #1234" in place of any earlier check number
    /// (the same wording the sheet link and the import use).
    static func notes(_ notes: String, check: String) -> String {
        let without = notes.replacingOccurrences(of: #"Check #\S+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ["Check #\(check)", without].filter { !$0.isEmpty }.joined(separator: " ")
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

    private struct Snapshot {
        let isDone: Bool, isPaid: Bool, paymentType: PaymentType, notes: String
        init(_ job: Job) {
            isDone = job.isDone; isPaid = job.isPaid; paymentType = job.paymentType; notes = job.notes
        }
    }

    private func save(_ job: Job, in context: ModelContext) {
        job.updatedAt = Date()
        try? context.save()
        CalendarStore.shared.jobSaved(job)
    }

    private func offerUndo(_ text: String, job: Job, before: Snapshot, in context: ModelContext) {
        undo = { [weak self] in
            job.isDone = before.isDone
            job.isPaid = before.isPaid
            job.paymentType = before.paymentType
            job.notes = before.notes
            self?.save(job, in: context)
        }
        message = text
        shown += 1
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.barSeconds))
            guard !Task.isCancelled else { return }
            self?.message = nil
            self?.undo = nil
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
        guard let job = actions.askingPayment else { return "How was it paid?" }
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
            Button("Undo", action: onUndo)
                .font(.callout.weight(.semibold))
                .buttonStyle(.borderless)
                #if os(macOS)
                .keyboardShortcut("z", modifiers: .command)
                #endif
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

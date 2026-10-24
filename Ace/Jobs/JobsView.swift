import SwiftData
import SwiftUI

/// All jobs: upcoming by day, unpaid, or done. Search works across all three.
struct JobsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]

    @State private var searchText = ""
    @State private var showingNewJob = false
    @State private var filter: JobsFilter = .upcoming
    /// Set by the Calendar's Owed figure: open on Unpaid once.
    static let openOnUnpaidKey = "jobs.openOnUnpaid"
    @AppStorage(JobsView.openOnUnpaidKey) private var openOnUnpaid = false
    /// A job swiped for deletion, waiting for "Delete this job?".
    @State private var pendingDelete: Job?
    @State private var paidTick = 0

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var filtered: [Job] { JobSearch.filter(jobs, searchText) }
    private var shown: [Job] { filter.apply(to: filtered) }
    private var days: [JobDay] { JobDay.group(shown) }

    /// Jobs before today that were never marked done. Shown above Upcoming.
    private var slipped: [Job] {
        let today = Dates.startOfToday()
        return filtered.filter { !$0.isDone && $0.scheduledAt < today }
    }

    var body: some View {
        List {
            // While searching, every job is searched (a past customer is
            // found too), so the Upcoming / Unpaid / Done switch steps aside.
            if isSearching {
                searchSections
            } else {
                Section {
                    Picker("Show", selection: $filter) {
                        ForEach(JobsFilter.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                switch filter {
                case .upcoming:
                    upcomingSections
                case .unpaid:
                    flatSection(header: unpaidHeader, empty: "Nothing owed.")
                case .done:
                    flatSection(header: doneHeader, empty: "No done jobs yet.")
                }
            }
        }
        .navigationTitle("Jobs")
        .refreshable { await SyncEngine.shared.syncNow(manual: true) }
        .onAppear { if openOnUnpaid { filter = .unpaid; openOnUnpaid = false } }
        .onChange(of: openOnUnpaid) { _, on in if on { filter = .unpaid; openOnUnpaid = false } }
        .searchable(text: $searchText, prompt: "Name, phone, address or notes")
        .navigationDestination(for: Job.self) { job in
            JobEditView(job: job)
        }
        .confirmationDialog("Delete this job?", isPresented: deleteAsked, titleVisibility: .visible, presenting: pendingDelete) { job in
            Button("Delete", role: .destructive) {
                JobActions.shared.forget(job)
                job.remove(from: context)
                pendingDelete = nil
            }
        } message: { job in
            Text(job.customer.map { "\($0.name), \(Dates.shortDay(job.scheduledAt))" } ?? Dates.shortDay(job.scheduledAt))
        }
        .sensoryFeedback(.success, trigger: paidTick)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewJob = true
                } label: {
                    Label("New job", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showingNewJob) {
            NavigationStack {
                JobEditView(job: nil)
            }
        }
        .onAppear {
            // Give the tab a moment to settle before the sheet opens.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { openNewJobIfAsked() }
        }
    }

    /// Screenshot aid: a launch with `-open newjob` opens a blank new job
    /// once. Normal launches carry no such argument and nothing happens.
    private static var openedNewJobFromLaunch = false

    private func openNewJobIfAsked() {
        guard !Self.openedNewJobFromLaunch else { return }
        Self.openedNewJobFromLaunch = true
        let args = ProcessInfo.processInfo.arguments
        let asked = args.contains("-open=newjob")
            || zip(args, args.dropFirst()).contains { $0.0 == "-open" && $0.1.lowercased() == "newjob" }
        if asked { showingNewJob = true }
    }

    private var deleteAsked: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: Sections

    /// Search results: jobs from today on, soonest first, then past jobs,
    /// newest first.
    @ViewBuilder
    private var searchSections: some View {
        let today = Dates.startOfToday()
        let coming = filtered.filter { $0.scheduledAt >= today }
        let past = filtered.filter { $0.scheduledAt < today }.reversed()
        if filtered.isEmpty {
            Section {
                Text("No matching jobs.")
                    .foregroundStyle(.secondary)
            }
        }
        if !coming.isEmpty {
            Section("Upcoming") {
                ForEach(coming) { job in row(job) }
            }
        }
        if !past.isEmpty {
            Section("Past") {
                ForEach(Array(past)) { job in row(job) }
            }
        }
    }

    @ViewBuilder
    private var upcomingSections: some View {
        if !slipped.isEmpty {
            Section("Not marked done") {
                ForEach(slipped) { job in
                    row(job)
                }
            }
        }
        if days.isEmpty {
            Section("Upcoming") {
                Text(searchText.isEmpty ? "No jobs scheduled." : "No matching jobs.")
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(days) { day in
            Section(day.title) {
                ForEach(day.jobs) { job in
                    row(job, showDate: false)
                }
            }
        }
    }

    private func flatSection(header: String, empty: String) -> some View {
        Section(header) {
            if shown.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { job in
                row(job)
            }
        }
    }

    private var unpaidHeader: String {
        shown.isEmpty ? "Unpaid" : "Unpaid · " + Plural.text(shown.count, "job") + " · " + Money.text(shown.priceTotal)
    }

    private var doneHeader: String {
        shown.isEmpty ? "Done" : "Done · \(shown.count)"
    }

    /// Opened by value rather than by a destination, so the page stays open
    /// when Mark paid or Mark done moves the job off this list (audit Oct
    /// 24, 24 and 37; the same as Quotes).
    private func row(_ job: Job, showDate: Bool = true) -> some View {
        NavigationLink(value: job) {
            // The list's own name tells the row which pills to leave out.
            JobRow(job: job, showDate: showDate, context: isSearching ? nil : filter)
        }
        .jobSwipeActions(job, filter: isSearching ? nil : filter,
                         onDelete: { pendingDelete = $0 },
                         onPaid: { paidTick += 1 })
        .contextMenu { JobQuickMenu(job: job) }
    }
}

/// Swipe right to mark a job done (or not done) or paid, left to delete
/// it. Delete never happens on a full swipe: it asks first through
/// `onDelete` (Oct 20 phone audit: a gloved slip deleted a job at once).
@MainActor
struct JobSwipeActions: ViewModifier {
    @Environment(\.modelContext) private var context
    let job: Job
    /// The list the row is in; Unpaid puts Paid first.
    var filter: JobsFilter?
    var onDelete: (Job) -> Void
    var onPaid: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                if filter == .unpaid {
                    paidButton
                    doneButton
                } else {
                    doneButton
                    if job.price != nil { paidButton }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    onDelete(job)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
    }

    private var doneButton: some View {
        Button {
            JobActions.shared.setDone(!job.isDone, job, in: context)
        } label: {
            Label(job.isDone ? "Not done" : "Done", systemImage: job.isDone ? "arrow.uturn.backward" : "checkmark")
        }
        .tint(.blue)
    }

    private var paidButton: some View {
        Button {
            if !job.isPaid { onPaid() }
            JobActions.shared.setPaid(!job.isPaid, job, in: context)
        } label: {
            Label(job.isPaid ? "Unpaid" : "Paid", systemImage: "dollarsign.circle")
        }
        .tint(Tint.paid)
    }
}

extension View {
    func jobSwipeActions(_ job: Job, filter: JobsFilter? = nil, onDelete: @escaping (Job) -> Void, onPaid: @escaping () -> Void = {}) -> some View {
        modifier(JobSwipeActions(job: job, filter: filter, onDelete: onDelete, onPaid: onPaid))
    }
}

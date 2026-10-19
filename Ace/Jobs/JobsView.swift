import SwiftData
import SwiftUI

/// All jobs: upcoming by day, unpaid, or done. Search works across all three.
struct JobsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]

    @State private var searchText = ""
    @State private var showingNewJob = false
    @State private var filter: JobsFilter = .upcoming

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
                flatSection(header: unpaidHeader, empty: searchText.isEmpty ? "Nothing owed." : "No matching jobs.")
            case .done:
                flatSection(header: doneHeader, empty: searchText.isEmpty ? "No done jobs yet." : "No matching jobs.")
            }
        }
        .navigationTitle("Jobs")
        .searchable(text: $searchText, prompt: "Customer, address or notes")
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
    }

    // MARK: Sections

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
                    row(job)
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

    private func row(_ job: Job) -> some View {
        NavigationLink {
            JobEditView(job: job)
        } label: {
            JobRow(job: job)
        }
        .swipeActions(edge: .leading) {
            Button {
                job.isDone.toggle()
                job.updatedAt = Date()
                try? context.save()
            } label: {
                Label(job.isDone ? "Not done" : "Done", systemImage: job.isDone ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                context.delete(job)
                try? context.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

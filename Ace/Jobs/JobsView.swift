import SwiftData
import SwiftUI

/// All jobs, soonest first, with the ones that slipped at the top.
struct JobsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]

    @State private var searchText = ""
    @State private var showingNewJob = false
    @State private var showDone = false

    private var filtered: [Job] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return jobs }
        let digits = query.filter(\.isNumber)
        return jobs.filter { job in
            let name = job.customer?.name.lowercased() ?? ""
            let address = job.customer?.address.lowercased() ?? ""
            let phone = job.customer?.phoneDigits ?? ""
            return name.contains(query)
                || address.contains(query)
                || (!digits.isEmpty && phone.contains(digits))
                || job.notes.lowercased().contains(query)
                || job.jobType.rawValue.lowercased().contains(query)
        }
    }

    private var overdue: [Job] {
        let today = Dates.startOfToday()
        return filtered.filter { !$0.isDone && $0.scheduledAt < today }
    }

    private var upcoming: [Job] {
        let today = Dates.startOfToday()
        return filtered.filter { !$0.isDone && $0.scheduledAt >= today }
    }

    private var done: [Job] {
        filtered.filter(\.isDone).reversed()
    }

    var body: some View {
        List {
            if !overdue.isEmpty {
                Section("Not marked done") {
                    ForEach(overdue) { job in
                        row(job)
                    }
                }
            }
            Section(upcoming.isEmpty ? "Upcoming" : "Upcoming · \(upcoming.count)") {
                if upcoming.isEmpty {
                    Text(searchText.isEmpty ? "No jobs scheduled." : "No matching jobs.")
                        .foregroundStyle(.secondary)
                }
                ForEach(upcoming) { job in
                    row(job)
                }
            }
            if !done.isEmpty {
                Section {
                    Button(showDone ? "Hide done jobs" : "Show \(done.count) done jobs") {
                        showDone.toggle()
                    }
                    if showDone {
                        ForEach(done) { job in
                            row(job)
                        }
                    }
                }
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

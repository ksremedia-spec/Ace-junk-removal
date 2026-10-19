import SwiftData
import SwiftUI

/// The day at a glance: dumpsters that need attention, today's jobs, tomorrow's.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]

    @State private var showingNewJob = false

    private var calendar: Calendar { .current }

    private var attentionDumpsters: [Dumpster] {
        dumpsters.filter { [.dueToday, .overdue].contains($0.status()) }
    }

    private var todaysJobs: [Job] {
        jobs.filter { calendar.isDateInToday($0.scheduledAt) && !$0.isDone }
    }

    private var tomorrowsJobs: [Job] {
        jobs.filter { calendar.isDateInTomorrow($0.scheduledAt) && !$0.isDone }
    }

    private var slippedJobs: [Job] {
        let today = Dates.startOfToday()
        return jobs.filter { !$0.isDone && $0.scheduledAt < today }
    }

    var body: some View {
        List {
            Section("Dumpsters") {
                if attentionDumpsters.isEmpty {
                    Text(dumpsters.isEmpty ? "No dumpsters set up yet." : "Nothing due back today.")
                        .foregroundStyle(.secondary)
                }
                ForEach(attentionDumpsters) { dumpster in
                    NavigationLink {
                        DumpsterDetailView(dumpster: dumpster)
                    } label: {
                        DumpsterRow(dumpster: dumpster)
                    }
                }
            }

            Section(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                if todaysJobs.isEmpty {
                    Text("No jobs today.")
                        .foregroundStyle(.secondary)
                }
                ForEach(todaysJobs) { job in
                    NavigationLink {
                        JobEditView(job: job)
                    } label: {
                        JobRow(job: job, showDate: false)
                    }
                }
                Button {
                    showingNewJob = true
                } label: {
                    Label("New job", systemImage: "plus")
                }
            }

            if !slippedJobs.isEmpty {
                Section("Not marked done") {
                    ForEach(slippedJobs) { job in
                        NavigationLink {
                            JobEditView(job: job)
                        } label: {
                            JobRow(job: job)
                        }
                    }
                }
            }

            Section("Tomorrow") {
                if tomorrowsJobs.isEmpty {
                    Text("No jobs tomorrow.")
                        .foregroundStyle(.secondary)
                }
                ForEach(tomorrowsJobs) { job in
                    NavigationLink {
                        JobEditView(job: job)
                    } label: {
                        JobRow(job: job, showDate: false)
                    }
                }
            }
        }
        .navigationTitle("Today")
        .sheet(isPresented: $showingNewJob) {
            NavigationStack {
                JobEditView(job: nil)
            }
        }
    }
}

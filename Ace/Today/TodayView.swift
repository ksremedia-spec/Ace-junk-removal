import SwiftData
import SwiftUI

/// The day at a glance: the numbers, what is owed, dumpsters that need
/// attention, today's jobs, tomorrow's.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]
    @Query(sort: \Quote.quotedOn) private var quotes: [Quote]

    /// Opens the Quotes tab on Open. Set by the tab bar.
    var onShowQuotes: (() -> Void)? = nil

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

    /// Done jobs that have not been paid.
    private var owedJobs: [Job] {
        jobs.filter { $0.owedAmount > 0 }
    }

    private var owedTotal: Double {
        owedJobs.reduce(0) { $0 + $1.owedAmount }
    }

    private var openQuotes: [Quote] {
        quotes.filter { $0.status == .open }
    }

    /// Open quotes whose call-back day is today or earlier.
    private var quotesToFollowUp: Int {
        openQuotes.filter { $0.isFollowUpDue() }.count
    }

    var body: some View {
        List {
            numbersSection

            if owedTotal > 0 {
                Section("Owed") {
                    Text(Money.text(owedTotal) + " from " + Plural.text(owedJobs.count, "job"))
                }
            }

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
                .buttonStyle(.borderless)
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

    /// "2 jobs today · $750", when any "1 dumpster due back or overdue",
    /// and, while any quote is open, "Quotes to follow up" with the count.
    private var numbersSection: some View {
        Section {
            Text(todayLine)
            if !attentionDumpsters.isEmpty {
                Text(Plural.text(attentionDumpsters.count, "dumpster") + " due back or overdue")
            }
            if !openQuotes.isEmpty {
                Button {
                    onShowQuotes?()
                } label: {
                    LabeledContent("Quotes to follow up") {
                        Text("\(quotesToFollowUp)")
                            .monospacedDigit()
                            .foregroundStyle(quotesToFollowUp > 0 ? Color.orange : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var todayLine: String {
        var text = Plural.text(todaysJobs.count, "job") + " today"
        let total = todaysJobs.priceTotal
        if total > 0 { text += " · " + Money.text(total) }
        return text
    }
}

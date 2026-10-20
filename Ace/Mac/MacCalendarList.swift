#if os(macOS)
import SwiftData
import SwiftUI

/// The Mac's Calendar list (middle column): the full-width month pinned at
/// the top (Today sits in its header), then the same sections as
/// the iPhone Calendar screen for the chosen day. The selected job,
/// dumpster, quote or event shows in the detail column. The spec is
/// docs/calendar-tab.md.
struct MacCalendarList: View {
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]
    @Query(sort: \Quote.quotedOn) private var quotes: [Quote]
    @Query(sort: \RentalRecord.pickedUpAt) private var rentals: [RentalRecord]
    @Binding var selection: MacMainView.CalendarItem?
    @Binding var day: Date

    @State private var showingNewJob = false
    @State private var jobToDelete: Job?

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDateInToday(day) }

    /// The month picker's choice, kept to the start of the day.
    private var dayBinding: Binding<Date> {
        Binding(
            get: { day },
            set: { day = Calendar.current.startOfDay(for: $0) }
        )
    }

    private var schedule: DaySchedule {
        DaySchedule(day: day, jobs: jobs, dumpsters: dumpsters, rentals: rentals, quotes: quotes)
    }

    private var otherEvents: [OtherEvent] {
        CalendarStore.shared.events(on: day, hidingJobs: Set(jobs.compactMap(\.jobID)))
    }

    var body: some View {
        let daySchedule = self.schedule
        let events = self.otherEvents
        // The month stays put above the list: it never scrolls away, and the
        // Calendar always reopens with it in view (Oct 20 audit).
        VStack(spacing: 0) {
            MacMonthGrid(selectedDay: dayBinding, dottedDays: DaySchedule.daysWithOpenJobs(jobs))
                .padding(.horizontal, Space.m)
                .padding(.top, Space.xs)
            Divider()
            List(selection: $selection) {
                if isToday {
                    todaySections(daySchedule, otherEvents: events)
                } else {
                    daySections(daySchedule, otherEvents: events)
                }
            }
        }
        .confirmJobDelete($jobToDelete) { deleted in
            if selection == .job(deleted) { selection = nil }
        }
        .sheet(isPresented: $showingNewJob) {
            NavigationStack {
                JobEditView(job: nil, prefill: isToday ? nil : JobFormData(day: day))
            }
            .frame(minWidth: 480, minHeight: 560)
        }
    }

    // MARK: Today

    private var attentionDumpsters: [Dumpster] {
        dumpsters.filter { [.dueToday, .overdue].contains($0.status()) }
    }

    private var tomorrowsJobs: [Job] { jobs.filter { calendar.isDateInTomorrow($0.scheduledAt) && !$0.isDone } }
    private var slippedJobs: [Job] { jobs.filter { !$0.isDone && $0.scheduledAt < Dates.startOfToday() } }

    @ViewBuilder
    private func todaySections(_ schedule: DaySchedule, otherEvents: [OtherEvent]) -> some View {
        Section {
            TodayFigures(jobs: jobs, dumpsters: dumpsters, quotes: quotes)
                .bareRow()
                .padding(.vertical, Space.xs)
        }
        Section("Dumpsters") {
            if attentionDumpsters.isEmpty {
                Text(dumpsters.isEmpty ? "No dumpsters set up yet." : "Nothing due back today.")
                    .foregroundStyle(.secondary)
            }
            ForEach(attentionDumpsters) { dumpster in
                DumpsterRow(dumpster: dumpster)
                    .tag(MacMainView.CalendarItem.dumpster(dumpster))
            }
        }
        jobsSection(schedule, empty: "No jobs today.")
        if !slippedJobs.isEmpty {
            Section("Not marked done") {
                ForEach(slippedJobs) { job in
                    jobRow(job, showDate: true)
                }
            }
        }
        callBackSection(schedule)
        otherCalendarsSection(otherEvents)
        Section("Tomorrow") {
            if tomorrowsJobs.isEmpty {
                Text("No jobs tomorrow.").foregroundStyle(.secondary)
            }
            ForEach(tomorrowsJobs) { job in
                jobRow(job, showDate: false)
            }
        }
    }

    // MARK: Another day

    @ViewBuilder
    private func daySections(_ schedule: DaySchedule, otherEvents: [OtherEvent]) -> some View {
        jobsSection(schedule, empty: "No jobs.")
        if !schedule.dumpsterItems.isEmpty {
            Section("Dumpsters") {
                ForEach(schedule.dumpsterItems) { item in
                    DumpsterDayRow(item: item)
                        .tag(MacMainView.CalendarItem.dumpster(item.dumpster))
                }
            }
        }
        callBackSection(schedule)
        otherCalendarsSection(otherEvents)
    }

    // MARK: Shared sections

    private func jobsSection(_ schedule: DaySchedule, empty: String) -> some View {
        Section(schedule.title) {
            if schedule.jobs.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            }
            ForEach(schedule.jobs) { job in
                jobRow(job, showDate: false)
            }
            Button {
                showingNewJob = true
            } label: {
                Label("New job", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func callBackSection(_ schedule: DaySchedule) -> some View {
        if !schedule.callBacks.isEmpty {
            Section("Call back") {
                ForEach(schedule.callBacks) { quote in
                    QuoteRow(quote: quote)
                        .tag(MacMainView.CalendarItem.quote(quote))
                }
            }
        }
    }

    @ViewBuilder
    private func otherCalendarsSection(_ events: [OtherEvent]) -> some View {
        if !events.isEmpty {
            Section("Other calendars") {
                ForEach(events) { item in
                    OtherEventRow(item: item)
                        .tag(MacMainView.CalendarItem.event(item))
                }
            }
        }
    }

    private func jobRow(_ job: Job, showDate: Bool) -> some View {
        JobRow(job: job, showDate: showDate)
            .tag(MacMainView.CalendarItem.job(job))
            .contextMenu { JobContextMenu(job: job, onDelete: { jobToDelete = $0 }) }
    }
}
#endif

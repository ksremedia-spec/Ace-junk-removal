import EventKit
import SwiftData
import SwiftUI

/// The first iPhone tab: a month at the top and the chosen day under it.
/// On today it shows the day at a glance, as the old Today screen did: the
/// numbers, what is owed, dumpsters that need attention, today's jobs,
/// jobs not marked done, quotes to call back, other calendars, tomorrow.
/// On another day: that day's jobs, dumpsters, call-backs and other
/// calendars. The spec is docs/calendar-tab.md.
struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]
    @Query(sort: \Quote.quotedOn) private var quotes: [Quote]
    @Query(sort: \RentalRecord.pickedUpAt) private var rentals: [RentalRecord]

    /// The chosen day. Held by the tab bar, which shows the Today button.
    @Binding var selectedDay: Date
    /// Opens the Quotes tab on Open. Set by the tab bar.
    var onShowQuotes: (() -> Void)? = nil

    @State private var showingNewJob = false
    @State private var shownEvent: OtherEvent?

    private var calendar: Calendar { .current }
    private var calendarStore: CalendarStore { .shared }

    private var isToday: Bool { calendar.isDateInToday(selectedDay) }

    private var schedule: DaySchedule {
        DaySchedule(day: selectedDay, jobs: jobs, dumpsters: dumpsters, rentals: rentals, quotes: quotes)
    }

    /// The day's events from the other calendars on the device.
    private var otherEvents: [OtherEvent] {
        calendarStore.events(on: selectedDay, hidingJobs: Set(jobs.compactMap(\.jobID)))
    }

    var body: some View {
        let day = self.schedule
        let events = self.otherEvents
        List {
            Section {
                MonthCalendar(selectedDay: $selectedDay, dottedDays: DaySchedule.daysWithOpenJobs(jobs))
            }
            if isToday {
                todaySections(day, otherEvents: events)
            } else {
                daySections(day, otherEvents: events)
            }
        }
        .navigationTitle("Calendar")
        .navigationDestination(for: Quote.self) { quote in
            QuoteEditView(quote: quote)
        }
        .sheet(isPresented: $showingNewJob) {
            NavigationStack {
                JobEditView(job: nil, prefill: isToday ? nil : JobFormData(day: selectedDay))
            }
        }
        .sheet(item: $shownEvent) { item in
            EventViewer(event: item.event, onDone: { shownEvent = nil })
                .ignoresSafeArea()
        }
    }

    // MARK: Today

    private var attentionDumpsters: [Dumpster] {
        dumpsters.filter { [.dueToday, .overdue].contains($0.status()) }
    }

    private var tomorrowsJobs: [Job] {
        jobs.filter { calendar.isDateInTomorrow($0.scheduledAt) && !$0.isDone }
    }

    private var slippedJobs: [Job] {
        let today = Dates.startOfToday()
        return jobs.filter { !$0.isDone && $0.scheduledAt < today }
    }

    @ViewBuilder
    private func todaySections(_ schedule: DaySchedule, otherEvents: [OtherEvent]) -> some View {
        Section {
            TodayFigures(jobs: jobs, dumpsters: dumpsters, quotes: quotes, onShowQuotes: onShowQuotes)
                .bareRow()
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
                Text("No jobs tomorrow.")
                    .foregroundStyle(.secondary)
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
                    NavigationLink {
                        DumpsterDetailView(dumpster: item.dumpster)
                    } label: {
                        DumpsterDayRow(item: item)
                    }
                }
            }
        }

        callBackSection(schedule)
        otherCalendarsSection(otherEvents)
    }

    // MARK: Shared sections

    /// The day's jobs, done ones included and crossed out, headed with the
    /// date, then New job.
    private func jobsSection(_ schedule: DaySchedule, empty: String) -> some View {
        Section(schedule.title) {
            if schedule.jobs.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
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
                    // Opened by value, so the form stays open when Mark Lost
                    // or Book Job moves the quote off this list.
                    NavigationLink(value: quote) {
                        QuoteRow(quote: quote)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func otherCalendarsSection(_ events: [OtherEvent]) -> some View {
        if !events.isEmpty {
            Section("Other calendars") {
                ForEach(events) { item in
                    Button {
                        shownEvent = item
                    } label: {
                        OtherEventRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A job, opened by tapping, with the same swipe actions as the Jobs list.
    private func jobRow(_ job: Job, showDate: Bool) -> some View {
        NavigationLink {
            JobEditView(job: job)
        } label: {
            JobRow(job: job, showDate: showDate)
        }
        .jobSwipeActions(job)
    }
}

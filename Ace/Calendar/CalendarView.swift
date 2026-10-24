import EventKit
import SwiftData
import SwiftUI

/// The first iPhone tab, in the same look as the Mac Calendar (Kyle, Oct 20:
/// bright cards and the week board): today's four figures, the week as a
/// strip of days (or the full month), the chosen day's jobs as cards tinted
/// by the kind of work, the six dumpsters as tiles, then jobs not marked
/// done and quotes waiting. The Quotes list lives here now that Labor has
/// the fifth tab. The spec is docs/calendar-tab.md.
struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]
    @Query(sort: \Quote.quotedOn) private var quotes: [Quote]
    @Query(sort: \RentalRecord.pickedUpAt) private var rentals: [RentalRecord]
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Pushed on the Calendar tab's stack.
    enum Route: Hashable {
        case quotes
    }

    enum Mode: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        var id: String { rawValue }
    }

    /// The chosen day. Held by the tab bar, which shows the Today button.
    @Binding var selectedDay: Date
    /// Opens the Quotes list. Set by the tab bar.
    var onShowQuotes: (() -> Void)? = nil

    @AppStorage("phone.calendarMode") private var modeRaw = Mode.week.rawValue
    @State private var quotesFilter: QuoteStatus = .open
    @State private var showingNewJob = false
    @State private var shownEvent: OtherEvent?

    private var calendar: Calendar { .current }
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .week }
    private var isToday: Bool { calendar.isDateInToday(selectedDay) }

    private var schedule: DaySchedule {
        DaySchedule(day: selectedDay, jobs: jobs, dumpsters: dumpsters, rentals: rentals, quotes: quotes)
    }

    /// The day's events from the other calendars on the device.
    private var otherEvents: [OtherEvent] {
        CalendarStore.shared.events(on: selectedDay, hidingJobs: Set(jobs.compactMap(\.jobID)))
    }

    private var slippedJobs: [Job] {
        jobs.filter { !$0.isDone && $0.scheduledAt < Dates.startOfToday() }
    }

    /// Today's next job not done yet, for the run-sheet card at the top
    /// (audit Oct 21, design idea 3).
    private var nextJob: Job? {
        DaySchedule(day: Dates.startOfToday(), jobs: jobs, dumpsters: dumpsters, rentals: rentals, quotes: quotes)
            .jobs.first { !$0.isDone }
    }

    private var openQuotes: [Quote] {
        quotes.filter { $0.status == .open }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if isToday, let next = nextJob {
                        NextJobCard(job: next)
                    }
                    TodayFigures(jobs: jobs, dumpsters: dumpsters, quotes: quotes, onShowQuotes: {
                        // The Quotes figure counts open quotes, so it opens on Open.
                        quotesFilter = .open
                        onShowQuotes?()
                    }, onShowOwed: {
                        NotificationCenter.default.post(name: .aceShowUnpaid, object: nil)
                    }, onShowDumpsters: {
                        NotificationCenter.default.post(name: .aceShowDumpsters, object: nil)
                    })
                    calendarCard
                    dayCard
                    yard
                    if !slippedJobs.isEmpty {
                        slippedCard
                    }
                    quotesCard
                    SyncFootnote()
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
            }
            // Month view: picking a day tucks the figures away, so the month
            // and the chosen day's jobs show together (Oct 20 phone audit).
            .onChange(of: selectedDay) { _, _ in
                guard mode == .month else { return }
                withAnimation { proxy.scrollTo("calendar", anchor: .top) }
            }
            .onChange(of: modeRaw) { _, _ in
                guard mode == .month else { return }
                withAnimation { proxy.scrollTo("calendar", anchor: .top) }
            }
        }
        .background(Tint.boardPage)
        .environment(\.cardFill, Tint.boardCard)
        .navigationTitle("Calendar")
        .refreshable { await SyncEngine.shared.syncNow(manual: true) }
        .navigationDestination(for: Quote.self) { quote in
            QuoteEditView(quote: quote)
        }
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .quotes:
                QuotesView(filter: $quotesFilter)
            }
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

    // MARK: The week or the month

    private var calendarCard: some View {
        VStack(spacing: Space.m) {
            Picker("Show", selection: $modeRaw) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch mode {
            case .week:
                WeekStrip(day: $selectedDay, marked: DaySchedule.daysWithOpenJobs(jobs))
            case .month:
                MonthCalendar(selectedDay: $selectedDay, dottedDays: DaySchedule.daysWithOpenJobs(jobs))
            }
        }
        .padding(Space.m)
        .cardBackground()
        .id("calendar")
    }

    // MARK: The chosen day

    private var dayCard: some View {
        let day = schedule
        let events = otherEvents
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(isToday ? "Today" : Dates.longDay(selectedDay))
                    .font(.title3.weight(.semibold))
                Spacer()
                if !day.jobs.isEmpty {
                    Text(dayTotal(day))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ForEach(day.jobs) { job in
                // By value, so the page stays open after Mark done
                // (audit Oct 24, 24 and 37).
                NavigationLink(value: job) {
                    JobCard(job: job, isSelected: false, showsAddress: true)
                }
                .buttonStyle(.plain)
                .contextMenu { JobQuickMenu(job: job) }
            }
            ForEach(day.dumpsterItems) { item in
                NavigationLink {
                    DumpsterDetailView(dumpster: item.dumpster)
                } label: {
                    SmallCard(title: item.title, detail: item.customer?.name ?? item.location,
                              symbol: "shippingbox.fill", tint: item.dumpster.status().tint, isSelected: false)
                }
                .buttonStyle(.plain)
            }
            ForEach(events) { item in
                Button { shownEvent = item } label: {
                    SmallCard(title: item.title, detail: item.timeLine, symbol: "calendar",
                              tint: item.color, isSelected: false)
                }
                .buttonStyle(.plain)
            }
            if day.jobs.isEmpty && day.dumpsterItems.isEmpty && events.isEmpty {
                Text("Nothing booked.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Space.xs)
            }
            Button {
                showingNewJob = true
            } label: {
                Label("New job", systemImage: "plus")
            }
            .buttonStyle(.action(.accentColor))
            .padding(.top, Space.xs)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// "2 jobs · $525"
    private func dayTotal(_ day: DaySchedule) -> String {
        let total = day.jobs.priceTotal
        let count = Plural.text(day.jobs.count, "job")
        return total > 0 ? count + " · " + Money.text(total) : count
    }

    // MARK: Dumpsters

    /// Three tiles a row, fewer as the text grows.
    private var yardColumns: Int {
        if typeSize.isAccessibilitySize { return 1 }
        return typeSize >= .xxLarge ? 2 : 3
    }

    private var yard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Dumpsters")
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: yardColumns), spacing: Space.s) {
                ForEach(dumpsters) { dumpster in
                    NavigationLink {
                        DumpsterDetailView(dumpster: dumpster)
                    } label: {
                        DumpsterTile(dumpster: dumpster, isSelected: false)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { DumpsterQuickMenu(dumpster: dumpster) }
                }
            }
            if dumpsters.isEmpty {
                Text("No dumpsters set up yet. Set them up on the Dumpsters tab.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Below

    private var slippedCard: some View {
        BoardListCard(title: "Not marked done", count: slippedJobs.count) {
            ForEach(slippedJobs) { job in
                NavigationLink(value: job) {
                    JobRow(job: job, showDate: true)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { JobQuickMenu(job: job) }
            }
        }
    }

    private var quotesCard: some View {
        BoardListCard(title: "Quotes waiting", count: openQuotes.count) {
            if openQuotes.isEmpty {
                Text("No quotes waiting.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.s)
            }
            ForEach(openQuotes.prefix(5)) { quote in
                // Opened by value, so the form stays open when Mark Lost or
                // Book Job moves the quote off this list.
                NavigationLink(value: quote) {
                    QuoteRow(quote: quote)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            NavigationLink(value: Route.quotes) {
                Label(openQuotes.count > 5 ? "All \(openQuotes.count) quotes" : "All quotes", systemImage: "doc.text")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
            }
        }
    }
}

/// Long-press menu on a job card: the two things done most often from the
/// truck, without opening the job.
struct JobQuickMenu: View {
    @Environment(\.modelContext) private var context
    let job: Job

    var body: some View {
        Button {
            JobActions.shared.setDone(!job.isDone, job, in: context)
        } label: {
            Label(job.isDone ? "Mark not done" : "Mark done", systemImage: job.isDone ? "arrow.uturn.backward" : "checkmark.circle")
        }
        Button {
            JobActions.shared.setPaid(!job.isPaid, job, in: context)
        } label: {
            Label(job.isPaid ? "Mark unpaid" : "Mark paid", systemImage: "dollarsign.circle")
        }
    }
}

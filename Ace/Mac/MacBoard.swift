#if os(macOS)
import SwiftData
import SwiftUI

/// The Mac's Calendar: one wide page instead of a list beside an empty
/// "Nothing selected" pane (Kyle, Oct 20: the app "looks kind of blah";
/// picked the bright-cards and week-board sketches, "BNC", in the existing
/// teal). Four figures across the top, the week as columns of job cards
/// like the office whiteboard (or the full month), the six dumpsters as
/// tiles, then jobs not marked done and open quotes. Clicking anything
/// opens it in the inspector on the right. The spec is
/// docs/calendar-tab.md, "Mac".
struct MacBoard: View {
    @Query(sort: \Job.scheduledAt) private var jobs: [Job]
    @Query(sort: \Dumpster.number) private var dumpsters: [Dumpster]
    @Query(sort: \Quote.quotedOn) private var quotes: [Quote]
    @Query(sort: \RentalRecord.pickedUpAt) private var rentals: [RentalRecord]
    @Binding var selection: MacMainView.CalendarItem?
    /// The chosen day; the week (or month) on show is the one holding it.
    @Binding var day: Date

    enum Mode: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        var id: String { rawValue }
    }

    @AppStorage("mac.calendarMode") private var modeRaw = Mode.week.rawValue
    @State private var newJobDay: NewJobDay?
    @State private var jobToDelete: Job?

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .week }
    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                TodayFigures(jobs: jobs, dumpsters: dumpsters, quotes: quotes,
                             onShowOwed: { NotificationCenter.default.post(name: .aceShowUnpaid, object: nil) },
                             onShowDumpsters: { NotificationCenter.default.post(name: .aceShowDumpsters, object: nil) },
                             columns: 4)
                switch mode {
                case .week:
                    WeekBoard(days: weekDays, day: $day, selection: $selection,
                              jobs: jobs, dumpsters: dumpsters, rentals: rentals, quotes: quotes,
                              onNewJob: { newJobDay = NewJobDay(day: $0) }, onDelete: { jobToDelete = $0 })
                case .month:
                    monthSection
                }
                DumpsterYard(dumpsters: dumpsters, selection: $selection)
                lowerCards
            }
            .padding(Space.xl)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Tint.boardPage)
        .environment(\.cardFill, Tint.boardCard)
        .confirmJobDelete($jobToDelete) { deleted in
            if selection == .job(deleted) { selection = nil }
        }
        .sheet(item: $newJobDay) { item in
            NavigationStack {
                JobEditView(job: nil, prefill: calendar.isDateInToday(item.day) ? nil : JobFormData(day: item.day))
            }
            .frame(minWidth: 480, minHeight: 560)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.isDateInToday(day) ? "Today" : Dates.longDay(day))
                    .font(.largeTitle.weight(.bold))
                Text(calendar.isDateInToday(day) ? Dates.longDay(day) : rangeText)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.m)
            Picker("Show", selection: $modeRaw) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            // The month has its own arrows and Today in its header.
            if mode == .week {
                HStack(spacing: 2) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .help("Previous week")
                    Button("Today") { day = Dates.startOfToday() }
                        .disabled(calendar.isDateInToday(day))
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .help("Next week")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// "Week of October 19" or "October 2026".
    private var rangeText: String {
        switch mode {
        case .week:
            return "Week of " + (weekDays.first ?? day).formatted(.dateTime.month(.wide).day())
        case .month:
            return Dates.monthYear(day)
        }
    }

    private func step(_ direction: Int) {
        if let moved = calendar.date(byAdding: .weekOfYear, value: direction, to: day) {
            day = calendar.startOfDay(for: moved)
        }
    }

    /// The seven days of the week holding the chosen day, in the order the
    /// month grid uses.
    private var weekDays: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return [day] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: Month

    private var monthSection: some View {
        HStack(alignment: .top, spacing: Space.l) {
            MacMonthGrid(selectedDay: $day, dottedDays: DaySchedule.daysWithOpenJobs(jobs))
                .padding(Space.m)
                .cardBackground()
                .frame(minWidth: 380, maxWidth: 560)
            DayColumn(day: day, isChosen: true, showsHeader: false, selection: $selection, chosenDay: $day,
                      jobs: jobs, dumpsters: dumpsters, rentals: rentals, quotes: quotes,
                      onNewJob: { newJobDay = NewJobDay(day: $0) }, onDelete: { jobToDelete = $0 })
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Below the week

    private var slippedJobs: [Job] {
        jobs.filter { !$0.isDone && $0.scheduledAt < Dates.startOfToday() }
    }

    private var openQuotes: [Quote] {
        quotes.filter { $0.status == .open }
    }

    @ViewBuilder
    private var lowerCards: some View {
        if !slippedJobs.isEmpty || !openQuotes.isEmpty {
            HStack(alignment: .top, spacing: Space.l) {
                if !slippedJobs.isEmpty {
                    BoardListCard(title: "Not marked done", count: slippedJobs.count) {
                        ForEach(slippedJobs) { job in
                            BoardRow(isSelected: selection == .job(job)) {
                                JobRow(job: job, showDate: true)
                            } action: {
                                selection = .job(job)
                            }
                            .contextMenu { JobContextMenu(job: job, onDelete: { jobToDelete = $0 }) }
                        }
                    }
                }
                if !openQuotes.isEmpty {
                    BoardListCard(title: "Quotes waiting", count: openQuotes.count) {
                        ForEach(openQuotes) { quote in
                            BoardRow(isSelected: selection == .quote(quote)) {
                                QuoteRow(quote: quote)
                            } action: {
                                selection = .quote(quote)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// The day a new job from the board is for.
private struct NewJobDay: Identifiable {
    let day: Date
    var id: Date { day }
}

// MARK: - The week

/// Seven columns, one per day, of job cards in time order.
private struct WeekBoard: View {
    let days: [Date]
    @Binding var day: Date
    @Binding var selection: MacMainView.CalendarItem?
    let jobs: [Job]
    let dumpsters: [Dumpster]
    let rentals: [RentalRecord]
    let quotes: [Quote]
    var onNewJob: (Date) -> Void
    var onDelete: (Job) -> Void

    var body: some View {
        // Narrow windows (or the inspector open) scroll sideways rather than
        // squeezing a day below a readable width.
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.s) {
                ForEach(days, id: \.self) { date in
                    DayColumn(day: date, isChosen: Calendar.current.isDate(date, inSameDayAs: day), showsHeader: true,
                              selection: $selection, chosenDay: $day,
                              jobs: jobs, dumpsters: dumpsters, rentals: rentals, quotes: quotes,
                              onNewJob: onNewJob, onDelete: onDelete)
                        .frame(minWidth: 108, maxWidth: .infinity)
                }
            }
            .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                max(width, 7 * 108 + 6 * Space.s)
            }
        }
        .scrollIndicators(.automatic)
    }
}

/// One day: its date at the top, then its jobs, dumpster comings and goings
/// and other calendars' events as cards, and a quiet "New job" at the end.
private struct DayColumn: View {
    let day: Date
    let isChosen: Bool
    let showsHeader: Bool
    @Binding var selection: MacMainView.CalendarItem?
    /// The board's chosen day; clicking the date header chooses this one.
    @Binding var chosenDay: Date
    let jobs: [Job]
    let dumpsters: [Dumpster]
    let rentals: [RentalRecord]
    let quotes: [Quote]
    var onNewJob: (Date) -> Void
    var onDelete: (Job) -> Void

    @State private var hovering = false

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDateInToday(day) }

    var body: some View {
        let schedule = DaySchedule(day: day, jobs: jobs, dumpsters: dumpsters, rentals: rentals, quotes: quotes)
        let events = CalendarStore.shared.events(on: day, hidingJobs: Set(jobs.compactMap(\.jobID)))
        VStack(alignment: .leading, spacing: Space.s) {
            if showsHeader {
                Button {
                    chosenDay = day
                } label: {
                    dateHeader
                }
                .buttonStyle(.plain)
            } else {
                Text(Dates.longDay(day))
                    .font(.headline)
            }
            ForEach(schedule.jobs) { job in
                Button { selection = .job(job) } label: {
                    JobCard(job: job, isSelected: selection == .job(job))
                }
                .buttonStyle(.plain)
                .contextMenu { JobContextMenu(job: job, onDelete: onDelete) }
            }
            ForEach(schedule.dumpsterItems) { item in
                Button { selection = .dumpster(item.dumpster) } label: {
                    SmallCard(title: item.title, detail: item.customer?.name ?? item.location,
                              symbol: "shippingbox.fill", tint: item.dumpster.status().tint,
                              isSelected: selection == .dumpster(item.dumpster))
                }
                .buttonStyle(.plain)
            }
            ForEach(events) { item in
                Button { selection = .event(item) } label: {
                    SmallCard(title: item.title, detail: item.timeLine, symbol: "calendar",
                              tint: item.color, isSelected: selection == .event(item))
                }
                .buttonStyle(.plain)
            }
            if schedule.jobs.isEmpty && schedule.dumpsterItems.isEmpty && events.isEmpty {
                Text("Nothing booked")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            }
            Button {
                onNewJob(day)
            } label: {
                Label("New job", systemImage: "plus")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .opacity(hovering || !showsHeader ? 1 : 0)
            .help("New job on " + Dates.shortDay(day))
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, minHeight: showsHeader ? 260 : 0, alignment: .topLeading)
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isChosen && showsHeader ? 2 : 0)
        )
        .onHover { hovering = $0 }
    }

    /// "TUE" over a big "20"; today's number in a teal circle.
    private var dateHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
            Spacer(minLength: 0)
            Text(day.formatted(.dateTime.day()))
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(minWidth: 30, minHeight: 30)
                .background(Circle().fill(isToday ? Color.accentColor : .clear))
        }
        .contentShape(Rectangle())
        .accessibilityLabel(Dates.longDay(day) + (isToday ? ", today" : ""))
    }
}

// MARK: - Dumpsters

/// The six dumpsters as tiles in their status colour: where each one is and
/// when it is due, at a glance.
struct DumpsterYard: View {
    let dumpsters: [Dumpster]
    @Binding var selection: MacMainView.CalendarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Dumpsters")
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: Space.s)], spacing: Space.s) {
                ForEach(dumpsters) { dumpster in
                    Button { selection = .dumpster(dumpster) } label: {
                        DumpsterTile(dumpster: dumpster, isSelected: selection == .dumpster(dumpster))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#endif

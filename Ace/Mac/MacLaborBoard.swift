#if os(macOS)
import SwiftData
import SwiftUI

/// Labor on the Mac (Alex, Oct 20): the week's timesheet, one row per
/// person and one column per day. Hourly crew have a box to type their
/// hours in; salaried crew show a check on each work day, clicked to mark
/// them off. Totals per person and per day, and the week's pay where a rate
/// is set. Clicking a name opens the person in the inspector. The spec is
/// docs/labor.md.
struct MacLaborBoard: View {
    @Query(sort: \Worker.name) private var workers: [Worker]
    @Binding var selection: Worker?

    @State private var day = Dates.startOfToday()
    @State private var showingNewWorker = false

    private var calendar: Calendar { .current }
    private var days: [Date] { Labor.week(containing: day) }
    private var isThisWeek: Bool { days.contains { calendar.isDateInToday($0) } }

    /// On the timesheet: everyone still working here, salaried first.
    private var crew: [Worker] {
        workers.filter(\.isActive).sorted { a, b in
            if a.isSalaried != b.isSalaried { return a.isSalaried }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var retired: [Worker] { workers.filter { !$0.isActive } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                figures
                if crew.isEmpty {
                    emptyCrew
                } else {
                    Timesheet(crew: crew, days: days, selection: $selection)
                }
                if !retired.isEmpty {
                    retiredCard
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Tint.boardPage)
        .environment(\.cardFill, Tint.boardCard)
        .sheet(isPresented: $showingNewWorker) {
            NavigationStack {
                NewWorkerSheet(onAdded: { selection = $0 })
            }
            .frame(minWidth: 420, minHeight: 300)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Labor")
                    .font(.largeTitle.weight(.bold))
                Text((isThisWeek ? "This week, " : "Week of ") + (days.first ?? day).formatted(.dateTime.month(.wide).day())
                     + " to " + (days.last ?? day).formatted(.dateTime.month(.wide).day()))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.m)
            Button {
                showingNewWorker = true
            } label: {
                Label("Add person", systemImage: "person.badge.plus")
            }
            .buttonStyle(.action(.accentColor))
            HStack(spacing: 2) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous week")
                Button("This week") { day = Dates.startOfToday() }
                    .disabled(isThisWeek)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next week")
            }
            .buttonStyle(.bordered)
        }
    }

    private func step(_ direction: Int) {
        if let moved = calendar.date(byAdding: .weekOfYear, value: direction, to: day) {
            day = calendar.startOfDay(for: moved)
        }
    }

    private var figures: some View {
        LaborFigures(crew: crew, days: days, columns: 4)
    }

    // MARK: No one yet, and former crew

    private var emptyCrew: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Add the crew")
                .font(.title3.weight(.semibold))
            Text("Add each person once, hourly or salary. Hours then go in here each day, or by telling the Assistant, like \"Joey worked 8 today\".")
                .foregroundStyle(.secondary)
            Button {
                showingNewWorker = true
            } label: {
                Label("Add person", systemImage: "person.badge.plus")
            }
            .buttonStyle(.action(.accentColor, prominent: true))
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var retiredCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Retired")
                .font(.headline)
            FlowRow(spacing: Space.s) {
                ForEach(retired) { worker in
                    Button(worker.name) { selection = worker }
                        .buttonStyle(.action(.secondary))
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

// MARK: - The timesheet

private struct Timesheet: View {
    let crew: [Worker]
    let days: [Date]
    @Binding var selection: Worker?

    private var calendar: Calendar { .current }

    /// Narrower than this, the timesheet scrolls sideways instead of
    /// pushing the window wider than the screen (Oct 20: it did, with the
    /// inspector open).
    private let narrowest: CGFloat = 640

    var body: some View {
        ScrollView(.horizontal) {
            grid
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                    max(width, narrowest)
                }
        }
        .scrollIndicators(.automatic)
        .cardBackground()
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Text("")
                    .gridColumnAlignment(.leading)
                ForEach(days, id: \.self) { date in
                    dayHeader(date)
                }
                Text("Week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
            }
            Divider()
            ForEach(crew) { worker in
                GridRow {
                    nameCell(worker)
                    ForEach(days, id: \.self) { date in
                        if worker.isSalaried {
                            SalaryCell(worker: worker, day: date)
                        } else {
                            HoursCell(worker: worker, day: date)
                        }
                    }
                    totalCell(worker)
                }
            }
            Divider()
            GridRow {
                Text("Hourly total")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach(days, id: \.self) { date in
                    let total = crew.filter { !$0.isSalaried }.reduce(0) { $0 + ($1.hours(on: date) ?? 0) }
                    Text(total > 0 ? Labor.hoursText(total) : "–")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                Text(Labor.hoursLabel(crew.filter { !$0.isSalaried }.reduce(0) { $0 + Labor.hours($1, over: days) }))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayHeader(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        return VStack(spacing: 1) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
            Text(date.formatted(.dateTime.day()))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(minWidth: 26, minHeight: 26)
                .background(Circle().fill(isToday ? Color.accentColor : .clear))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Dates.longDay(date) + (isToday ? ", today" : ""))
    }

    private func nameCell(_ worker: Worker) -> some View {
        Button {
            selection = worker
        } label: {
            HStack(spacing: Space.s) {
                Avatar(name: worker.name, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(worker.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(worker.isSalaried ? "Salary" : (worker.hourlyRate.map { Money.text($0) + "/hr" } ?? "Hourly"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selection == worker ? Color.accentColor.opacity(0.16) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 150, alignment: .leading)
    }

    private func totalCell(_ worker: Worker) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            if worker.isSalaried {
                Text(Plural.text(Labor.daysWorked(worker, over: days), "day"))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            } else {
                Text(Labor.hoursLabel(Labor.hours(worker, over: days)))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                if let pay = Labor.pay(worker, over: days), pay > 0 {
                    Text(Money.text(pay))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .frame(minWidth: 64, alignment: .trailing)
    }
}

#endif

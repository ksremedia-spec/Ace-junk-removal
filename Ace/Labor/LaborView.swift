import SwiftData
import SwiftUI

/// Labor on the iPhone (Alex, Oct 20: hours each guy worked every day). A
/// week strip to pick the day, then everyone on the crew for that day:
/// hourly crew get a box for their hours, salaried crew a Worked switch
/// (on by itself on their work days). Under it the week's totals, and
/// people who have left. The Mac shows the whole week as a grid; the data
/// is the same. The spec is docs/labor.md.
struct LaborView: View {
    @Query(sort: \Worker.name) private var workers: [Worker]
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var day = Dates.startOfToday()
    @State private var showingNewWorker = false

    private var calendar: Calendar { .current }
    private var days: [Date] { Labor.week(containing: day) }

    /// Everyone still working here, salaried first.
    private var crew: [Worker] {
        workers.filter(\.isActive).sorted { a, b in
            if a.isSalaried != b.isSalaried { return a.isSalaried }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var retired: [Worker] { workers.filter { !$0.isActive } }

    /// Days in the week on show with hourly hours logged, for the dots.
    private var loggedDays: Set<Date> {
        Set(days.filter { date in crew.contains { $0.hours(on: date) != nil } })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if crew.isEmpty {
                        emptyCrew
                    } else {
                        LaborFigures(crew: crew, days: days)
                        WeekStrip(day: $day, marked: loggedDays)
                            .padding(Space.m)
                            .cardBackground()
                        dayCard(proxy)
                        weekCard
                    }
                    if !retired.isEmpty {
                        retiredCard
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Tint.boardPage)
        .environment(\.cardFill, Tint.boardCard)
        .navigationTitle("Labor")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showingNewWorker = true
                } label: {
                    Label("Add person", systemImage: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingNewWorker) {
            NavigationStack {
                NewWorkerSheet()
            }
        }
    }

    // MARK: The chosen day

    /// Brings the hours box being typed in up to the middle, clear of the
    /// keyboard and its Done button, once the keyboard is up.
    private func scrollToRow(_ worker: Worker, _ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation {
                proxy.scrollTo(worker.persistentModelID, anchor: UnitPoint(x: 0.5, y: 0.35))
            }
        }
    }

    /// Name and box side by side; at the largest text sizes the box goes
    /// under the name, full width, so the name is not cut short.
    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs))
            : AnyLayout(HStackLayout(spacing: Space.m))
    }

    private func dayCard(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(calendar.isDateInToday(day) ? "Today" : Dates.longDay(day))
                .font(.title3.weight(.semibold))
            ForEach(crew) { worker in
                rowLayout {
                    NavigationLink {
                        WorkerPage(worker: worker)
                    } label: {
                        HStack(spacing: Space.s) {
                            Avatar(name: worker.name, size: 32)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(worker.name)
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                                Text(worker.isSalaried ? "Salary" : (worker.hourlyRate.map { Money.text($0) + "/hr" } ?? "Hourly"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Space.s)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Group {
                        if worker.isSalaried {
                            SalaryCell(worker: worker, day: day)
                        } else {
                            HoursCell(worker: worker, day: day, onFocus: { scrollToRow(worker, proxy) })
                        }
                    }
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 88)
                    .frame(width: typeSize.isAccessibilitySize ? nil : 88)
                }
                .padding(.vertical, 2)
                .id(worker.persistentModelID)
            }
            Text("Type hours like 8 or 7.5. Tap a salaried day to mark it off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: The week

    private var weekCard: some View {
        BoardListCard(title: weekTitle, count: crew.count) {
            ForEach(crew) { worker in
                HStack {
                    Text(worker.name)
                        .lineLimit(1)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(worker.isSalaried
                             ? Plural.text(Labor.daysWorked(worker, over: days), "day")
                             : Labor.hoursLabel(Labor.hours(worker, over: days)))
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
                .padding(.horizontal, Space.s)
                .padding(.vertical, 2)
            }
        }
    }

    private var weekTitle: String {
        days.contains { calendar.isDateInToday($0) } ? "This week" : "Week of " + Dates.shortDay(days.first ?? day)
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
                    NavigationLink {
                        WorkerPage(worker: worker)
                    } label: {
                        Text(worker.name)
                    }
                    .buttonStyle(.action(.secondary))
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

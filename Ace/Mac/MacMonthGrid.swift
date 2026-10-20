#if os(macOS)
import SwiftUI

/// The Mac Calendar's month: the full width of the middle column, with a dot
/// under each day that has a job not yet done, as on iPhone. Replaced Apple's
/// small graphical date picker (Kyle, 2026-10-19; docs/decisions.md). The
/// spec is docs/calendar-tab.md, "Mac".
struct MacMonthGrid: View {
    @Binding var selectedDay: Date
    /// Start of each day that gets a dot.
    let dottedDays: Set<Date>

    /// Any day in the month on show.
    @State private var month: Date
    @State private var hovered: Date?

    init(selectedDay: Binding<Date>, dottedDays: Set<Date>) {
        _selectedDay = selectedDay
        self.dottedDays = dottedDays
        _month = State(initialValue: selectedDay.wrappedValue)
    }

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 10) {
            header
            VStack(spacing: 2) {
                weekdayRow
                ForEach(weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { day in
                            dayCell(day)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        // A day's own hover-out can be missed when the list redraws; leaving
        // the month always clears it.
        .onHover { inside in
            if !inside { hovered = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aceGoToToday)) { _ in
            month = Dates.startOfToday()
        }
        .onChange(of: selectedDay) { _, newValue in
            // The Today button or ⌘T chose a day in another month.
            if !calendar.isDate(newValue, equalTo: month, toGranularity: .month) {
                month = newValue
            }
        }
    }

    // MARK: Month and arrows

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(month.formatted(.dateTime.month(.wide)))
                    .font(.title2.weight(.semibold))
                Text(month.formatted(.dateTime.year()))
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            HStack(spacing: 2) {
                arrow("chevron.left", label: "Previous month", by: -1)
                // Always here, so the month never moves; greyed out when
                // today is already chosen and on show.
                Button("Today") {
                    selectedDay = Dates.startOfToday()
                    month = selectedDay
                }
                .buttonStyle(.borderless)
                .font(.callout.weight(.medium))
                .padding(.horizontal, Space.xs)
                .disabled(showingToday)
                .help("Go to today (⌘T)")
                arrow("chevron.right", label: "Next month", by: 1)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Today is chosen and its month is the one on show.
    private var showingToday: Bool {
        calendar.isDateInToday(selectedDay) && calendar.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    private func arrow(_ symbol: String, label: String, by months: Int) -> some View {
        Button {
            if let moved = calendar.date(byAdding: .month, value: months, to: month) {
                month = moved
            }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: Days

    /// "Sun", "Mon", … starting on the week's first day for this Mac.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    /// Six weeks, so the month keeps its height from month to month.
    private var weeks: [[Date]] {
        guard let first = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -lead, to: first) else { return [] }
        return (0..<6).map { week in
            (0..<7).compactMap { calendar.date(byAdding: .day, value: week * 7 + $0, to: start) }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let hasJobs = dottedDays.contains(calendar.startOfDay(for: day))
        let isHovered = hovered.map { calendar.isDate($0, inSameDayAs: day) } ?? false

        return Button {
            selectedDay = calendar.startOfDay(for: day)
            if !inMonth { month = day }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.body.monospacedDigit())
                    .fontWeight(isToday || isSelected ? .semibold : .regular)
                    .foregroundStyle(numberColor(inMonth: inMonth, isSelected: isSelected, isToday: isToday))
                    .frame(width: 32, height: 32)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isHovered {
                            Circle().fill(Color.primary.opacity(0.08))
                        }
                    }
                Circle()
                    .fill(hasJobs ? dotColor(inMonth: inMonth) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hovered = day
            } else if isHovered {
                hovered = nil
            }
        }
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (isToday ? ", today" : "") + (hasJobs ? ", has jobs" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func numberColor(inMonth: Bool, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return inMonth ? .primary : Color(nsColor: .tertiaryLabelColor)
    }

    private func dotColor(inMonth: Bool) -> Color {
        inMonth ? Color.secondary : Color(nsColor: .quaternaryLabelColor)
    }
}
#endif
